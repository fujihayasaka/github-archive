# typed: strict
# frozen_string_literal: true

class Copilot::NewBatchUpdateOrgSettingsJob < CopilotJob
  queue_as :copilot_update_org_settings
  retry_on_dirty_exit
  retry_on_recoverable_exceptions
  locked_by timeout: 1.minute, key: DEFAULT_LOCK_PROC

  resolve_tenant_context do |business_id|
    ::Business.find_by(id: business_id)
  end

  # this job enqueues member updates in batches of BATCH_SIZE to parallelize writes
  sig { params(business_id: Integer, feature: Symbol).void }
  def perform(business_id, feature)
    GitHub.logger.with_named_tags("gh.business.id" => business_id, "gh.feature" => feature) do
      business = T.let(::Business.find_by(id: business_id), T.nilable(::Business))
      return unless business
      GitHub.logger.info(
        "info.message" => "Starting copilot batch_update_org_settings_job",
      )
      copilot_business = Copilot::Business.new(business)

      business.organizations.find_in_batches do |batch|
        batch.each do |organization|
          copilot_org = Copilot::Organization.new(organization)
          Copilot::Policies::PROPAGATABLE.each do |policy|
            if policy.propagate_business_updates?(copilot_business, copilot_org)
              policy.propagate_to_org(copilot_business, copilot_org, send_email: feature == policy.config_name.to_sym)
            end
          end
        end
      end
    end
  end
end
