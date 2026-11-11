# typed: true
# frozen_string_literal: true

module SecurityProductsEnablement
  module SecretScanningBackfillHelper
    BATCH_SIZE = 100_000

    sig { params(security_configuration: SecurityConfiguration, owner: User, repository_ids: T::Array[Integer]).void }
    def publish_secret_scanning_backfill(security_configuration:, owner:, repository_ids:)
      repository_ids.each_slice(BATCH_SIZE) do |batch_of_repository_ids|
        GitHub.logger.info("security_products_enablement.publish_secret_scanning_backfill", {
          "gh.security_configuration.id": security_configuration.id,
          "gh.org.id": owner.id,
          "gh.org.login": owner.display_login,
          "gh.repo.count": batch_of_repository_ids.count,
        })

        GlobalInstrumenter.instrument("secret_scanning.backfill.group", {
          action: :START,
          owner:,
          requested_at: Time.current.utc,
          type: :FULL,
          feature_flags: SecretScanning::Instrumentation::OwnerServiceFlags.new(owner).group_backfill_service_flags(security_configuration),
          repository_ids: batch_of_repository_ids,
          security_configuration_id: security_configuration.id,
        })
      end
    end
  end
end
