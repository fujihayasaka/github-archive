# typed: strict
# frozen_string_literal: true

module Stafftools::Users::ControllerPackageRegistryMethods
  extend T::Helpers

  requires_ancestor { StafftoolsController }

  sig { returns(Integer) }
  def unmigrated_package_count
    ::Registry::Package
      .unmigrated
      .where(owner_id: this_user.id)
      .count(:id)
  end

  sig { returns(Integer) }
  def organization_package_count
    client = PackageRegistry::Twirp.metadata_client
    organization_packages_resp = client.get_all_packages(
      namespace: this_user.login,
      limit: 1,
      offset: 0,
      exclude_deleted: true,
      full_response: true,
    )
    organization_packages_resp.total_packages
  rescue PackageRegistry::Twirp::BaseError
    0
  end
end
