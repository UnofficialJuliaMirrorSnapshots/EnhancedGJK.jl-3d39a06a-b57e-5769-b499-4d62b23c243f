"""
The NeighborMesh is what actually makes EnhancedGJK "enhanced". It consists
of a mesh and a pre-computed set of neighbors for each vertex. These neighbors
will be searched when the GJK simplex is refined. Searching over just the
neighbors of a particular vertex allows us to avoid repeatedly searching over
every vertex in the mesh.

Note that constructing a new NeighborMesh is expensive (and unoptimized). We
recommend constructing the NeighborMesh for each of your meshes ahead of time.
"""
mutable struct NeighborMesh{MeshType <: gt.AbstractMesh}
    mesh::MeshType
    neighbors::Vector{Set{Int}}
end

function plane_fit(data)
    centroid = mean(data, dims=2)
    U, s, V = svd(data .- centroid)
    i = argmin(s)
    normal = U[:,i]
    offset = dot(normal, centroid)
    normal, offset
end


function NeighborMesh(mesh::gt.AbstractMesh{gt.Point{N, T}}) where {N,T}
    neighbors = Set{Int}[Set{Int}() for vertex in gt.vertices(mesh)]
    for face in gt.faces(mesh)
        for i in 1:length(face)
            for j in i+1:length(face)
                if face[i] != face[j]
                    push!(neighbors[face[i]], face[j])
                    push!(neighbors[face[j]], face[i])
                end
            end
        end
    end

    # The enhanced GJK algorithm is susceptible to becoming stuck in local minima
    # if all of the neighbors of a given vertex are coplanar. It also benefits from
    # having some distant neighbors for each node, to avoid having to always take the
    # long way around the mesh to get to the other side.
    # To try to fix this, we will compute a fitting plane for all of the existing
    # neighbors for each vertex. We will then add neighbors corresponding to the
    # vertices at the maximum distance on each side of that plane.
    verts = gt.vertices(mesh)
    for i in eachindex(neighbors)
        @assert length(neighbors[i]) >= 2
        normal, offset = plane_fit(reshape(reinterpret(T,
            [verts[n] for n in neighbors[i]]), (N, length(neighbors[i]))))
        push!(neighbors[i], argmin(map(v -> dot(convert(gt.Point{N, T}, normal), v), verts)))
        push!(neighbors[i], argmax(map(v -> dot(convert(gt.Point{N, T}, normal), v), verts)))
    end
    NeighborMesh{typeof(mesh)}(mesh, neighbors)
end

any_inside(mesh::NeighborMesh) = Tagged(SVector( first(gt.vertices(mesh.mesh))), 1)

function support_vector_max(mesh::NeighborMesh, direction,
                                  initial_guess::Tagged{P, Tag}) where {P,Tag}
    verts = gt.vertices(mesh.mesh)
    best = Tagged{P, Tag}(SVector(verts[initial_guess.tag]), initial_guess.tag)
    score = dot(direction, best.point)
    while true
        candidates = mesh.neighbors[best.tag]
        improved = false
        for index in candidates
            candidate_point = SVector(verts[index])
            candidate_score = dot(direction, candidate_point)
            if candidate_score > score || (candidate_score == score && index > best.tag)
                score = candidate_score
                best = Tagged{P, Tag}(candidate_point, index)
                improved = true
                break
            end
        end
        if !improved
            break
        end
    end
    best
end

dimension(::Type{NeighborMesh{M}}) where {M} = dimension(M)
