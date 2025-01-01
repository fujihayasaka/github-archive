# typed: true
# frozen_string_literal: true

module Api::Serializer::FineGrainedPermissionsDependency
  def fine_grained_permission_hash(fgp, options = {})
    metadata = RepoFgpMetadata.for(fgp)
    {
      name: metadata.label,
      description: metadata.description
    }
  end

  def fine_grained_permissions_hash(data, options = {})
    fgps = data.fetch(:fgps, [])

    fgps.map { |fgp| fine_grained_permission_hash(fgp, options) }
  end
end
