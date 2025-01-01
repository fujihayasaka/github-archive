# typed: strict
# frozen_string_literal: true

module SecurityProductsEnablement
  class HydroRepositoryPurgedJob < Repositories::RepositoryHydroMessageJob
    queue_as :hydro_security_products_enablement_repository_purged

    retry_on_dirty_exit

    MAX_THROTTLE_RETRIES = 5

    sig { void }
    def perform
      ActiveRecord::Base.connected_to(role: :writing) do
        # A single repository is limited to 1 setting per security product, so a batch size of 50 is effectively a
        # select all, but let's set a limit as good practice.
        RepositorySecuritySetting.where(repository_id: repository_id).find_each do |setting|
          RepositorySecuritySetting.throttle_with_retry(max_retry_count: MAX_THROTTLE_RETRIES) do
            setting.destroy
          end
        end
      end
    end
  end
end
