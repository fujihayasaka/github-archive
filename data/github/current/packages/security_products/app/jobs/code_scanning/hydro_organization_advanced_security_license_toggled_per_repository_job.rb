# typed: strict
# frozen_string_literal: true

module CodeScanning
  class HydroOrganizationAdvancedSecurityLicenseToggledPerRepositoryJob < HydroMessageJob
    include RepositoryHydroMessageJobTenantContext

    queue_as :hydro_code_scanning_organization_advanced_security_license_toggled_per_repository
    retry_on_dirty_exit

    sig { override.returns(Integer) }
    attr_reader :repository_id

    sig { params(protobuf: T.untyped, headers: T.untyped, schema: T.untyped, timestamp: T.untyped, timestamp_nano: T.untyped, message: T.untyped, queue: T.untyped).void }
    def initialize(protobuf:, headers:, schema:, timestamp:, timestamp_nano:, message:, queue:)
      super

      @repository_id = T.let(message[:repository_id], Integer)

      GitHub.context.push(repository_id:)
    end

    # Public: process a Hydro message
    #
    # Returns nothing
    sig { void }
    def perform
      CodeScanning::Instrumentation::FeatureToggledPublisher.instrument_features_toggled(repository_id: repository_id)
    end

    protected

    sig { override.returns(T::Hash[String, T.untyped]) }
    def logging_context
      super.merge({
        "gh.repo.id": repository_id,
      })
    end

    sig { override.returns(T::Hash[Symbol, T.untyped]) }
    def failbot_log_context
      super.merge({
        "gh.repo.id": repository_id
      })
    end
  end
end
