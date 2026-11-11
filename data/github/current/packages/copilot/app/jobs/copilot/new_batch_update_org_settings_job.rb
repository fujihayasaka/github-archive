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

      if business.feature_flag_enabled?(:copilot_batch_org_update_opt, default: false)
        perform_candidate(copilot_business, feature)
      else
        perform_control(business, copilot_business, feature)
      end
    end
  end

  # only update the single policy specified by the feature argument
  sig { params(copilot_business: Copilot::Business, feature: Symbol).void }
  def perform_candidate(copilot_business, feature)
    return if copilot_business.is_standalone_business?

    policy = Copilot::Policies::PROPAGATABLE.find { |p| p.config_name.to_sym == feature }

    return unless policy

    # If business is set to no_policy, we still need to send admin emails
    # to notify org admins that the business no longer controls the policy
    if policy.no_policy?(copilot_business)
      if policy.is_a?(Copilot::Policies::Concerns::Business::Mailable)
        copilot_business.organizations.each do |org|
          copilot_org = Copilot::Organization.new(org)
          next unless policy.available_for?(copilot_org)

          previous_value = policy.value(copilot_org)
          policy.send_policy_updated_email_to_admins(copilot_org, value: "no_policy", previous_value: previous_value)
        end
      end
      return
    end

    return if policy.unconfigured?(copilot_business)
    biz_val = policy.value(copilot_business)

    # find all the configs for the orgs in this business
    copilot_orgs = copilot_business.copilot_organizations.index_by(&:id)
    org_ids = copilot_orgs.keys

    # use the org ids to find all corresponding configs in a single query
    Copilot::Configuration.where(configurable_id: org_ids, configurable_type: "Organization").where.not(feature => biz_val).find_each do |org_config|
      copilot_org = copilot_orgs[org_config.configurable_id]
      next unless copilot_org

      org_val = org_config[policy.config_name.to_sym]
      if biz_val != org_val
        # only update the policy if the newly set business val is not equal to the org val
        policy.propagate_to_org_candidate(copilot_org, org_config, biz_val, org_val, send_email: feature == policy.config_name.to_sym)

        # only enqueue a single update if the policy changes
        Copilot::BatchUpdateUserSettingsJob.perform_later(copilot_org.id)
      end
    end
  end

  sig { params(business: ::Business, copilot_business: Copilot::Business, feature: Symbol).void }
  def perform_control(business, copilot_business, feature)
    business.organizations.find_in_batches do |batch|
      batch.each do |organization|
        copilot_org = Copilot::Organization.new(organization)
        Copilot::Policies::PROPAGATABLE.each do |policy|
          policy.propagate_to_org(copilot_business, copilot_org, send_email: feature == policy.config_name.to_sym)
        end
      end
    end
  end
end
