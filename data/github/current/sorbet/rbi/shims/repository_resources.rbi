# typed: true

class Repository
  class Resources

    # dynamically defined in Permissions::FineGrainedResource
    sig { returns(Repository) }
    def repository; end

    sig { returns(IntegrationInstallation::AbilityCollection) }
    def contents; end
  end
end
