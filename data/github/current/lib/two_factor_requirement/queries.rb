# typed: true
# frozen_string_literal: true

module TwoFactorRequirement
  module Queries
    autoload :Base, "two_factor_requirement/queries/base"
    autoload :ManualEnrollment, "two_factor_requirement/queries/manual_enrollment"
    autoload :PublishedPackage, "two_factor_requirement/queries/published_package"
    autoload :PublishedApp, "two_factor_requirement/queries/published_app"
    autoload :CreatedRelease, "two_factor_requirement/queries/created_release"
    autoload :OpenSSFAdmin, "two_factor_requirement/queries/open_ssf_admin"
    autoload :EnterpriseOrgAdmin, "two_factor_requirement/queries/enterprise_and_org_admin"
    autoload :OpenSSFContributor, "two_factor_requirement/queries/open_ssf_contributor"
    autoload :RegistryRepoAdmin, "two_factor_requirement/queries/registry_repo_admin"
    autoload :RegistryRepoContributor, "two_factor_requirement/queries/registry_repo_contributor"
    autoload :PopularAdmin, "two_factor_requirement/queries/popular_admin"
    autoload :PopularContributor, "two_factor_requirement/queries/popular_contributor"
    autoload :PackageAdmin, "two_factor_requirement/queries/package_admin"
    autoload :PackageContributor, "two_factor_requirement/queries/package_contributor"

    # Each class is in a purposeful order in this array to prioritize the "reason" for requirement
    # determined by the discovery job.
    def self.all
      [
        ManualEnrollment.new,
        PublishedPackage.new,
        PublishedApp.new,
        CreatedRelease.new,
        OpenSSFAdmin.new,
        EnterpriseOrgAdmin.new,
        OpenSSFContributor.new,
        RegistryRepoAdmin.new,
        RegistryRepoContributor.new,
        PopularAdmin.new,
        PopularContributor.new,
        PackageAdmin.new,
        PackageContributor.new,
      ]
    end

    def self.find(reason:)
      all.find { |q| q.reason.to_s == reason.to_s }
    end
  end
end
