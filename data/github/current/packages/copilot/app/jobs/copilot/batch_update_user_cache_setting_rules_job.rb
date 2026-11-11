# typed: strict
# frozen_string_literal: true

# Job used by setting rules to ensure that user cache settings are updated
# after organization or enterprise level settings or rules are changed.
class Copilot::BatchUpdateUserCacheSettingRulesJob < CopilotJob
  queue_as :copilot_update_enterprise_user_settings
  retry_on_dirty_exit
  retry_on_recoverable_exceptions
  locked_by timeout: 1.minute, key: DEFAULT_LOCK_PROC

  resolve_tenant_context do |business_id|
    ::Business.find_by(id: business_id)
  end

  sig { params(business_id: Integer).void }
  def perform(business_id)
    GitHub.logger.with_named_tags("gh.business.id" => business_id) do
      business = T.let(::Business.find_by(id: business_id), T.nilable(::Business))
      return unless business
      GitHub.logger.info(
        "info.message" => "Starting copilot batch_update_user_cache_setting_rules",
      )

      Copilot::BatchUpdateEnterpriseUserSettingsJob.perform_later(business)
      business.organizations.find_in_batches do |batch|
        batch.each do |organization|
          Copilot::BatchUpdateUserSettingsJob.perform_later(organization.id)
        end
      end
    end
  end
end
