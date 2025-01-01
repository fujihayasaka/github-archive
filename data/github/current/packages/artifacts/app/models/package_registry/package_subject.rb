# typed: true
# frozen_string_literal: true

module PackageRegistry
  class PackageSubject
    include Ability::Subject
    attr_reader :id
    attr_reader :access_type

    def initialize(id:, access_type:)
      @id = id
      @access_type = access_type
    end

    # Internal: an abstract collection, for the sub-resources of a Package available for abilities
    def resources
      ::PackageRegistry::Resources.new(self)
    end

    # Packages Permissions Availability TODO: Keep this until we know what to do with Codespaces.
    # See https://github.com/github/package-registry-team/issues/7344
    # This method is responsible for looking up the book-keeping table
    # to find all packages that are accessible to the repository in the call
    # for the specific integration given
    def self.get_packages_accessible_by_repo(integration:, repository:)
      allowed_packages = IntegrationAllowedPackage.where(integration: integration, repository: repository)
      allowed_packages.map do |allowed_package|
        ::PackageRegistry::PackageSubject.new(id: allowed_package.package_id, access_type: allowed_package.access_type)
      end
    end
  end
end
