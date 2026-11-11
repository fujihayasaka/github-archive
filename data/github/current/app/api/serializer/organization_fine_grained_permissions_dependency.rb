# typed: true
# frozen_string_literal: true

module Api::Serializer::OrganizationFineGrainedPermissionsDependency
  def org_fine_grained_permission_hash(fgp, options = {})
    metadata = OrgFgpMetadata.for(fgp)
    {
      name: metadata.label,
      description: metadata.description
    }
  end

  def org_fine_grained_permissions_hash(data, options = {})
    fgps = data.fetch(:fgps, [])

    fgps.map { |fgp| org_fine_grained_permission_hash(fgp, options) }
  end
end
