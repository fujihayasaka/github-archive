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
  #
  # org_ids is an optional list of org IDs to scope the update to.
  #   When nil, all orgs in the business are processed.
  # target_value is an optional policy value to force-set on orgs.
  #   When nil, the value is read from the business config.
  sig { params(business_id: Integer, feature: Symbol, org_ids: T.nilable(T::Array[Integer]), target_value: T.nilable(String)).void }
  def perform(business_id, feature, org_ids = nil, target_value = nil)
    GitHub.logger.with_named_tags("gh.business.id" => business_id, "gh.feature" => feature) do
      business = T.let(::Business.find_by(id: business_id), T.nilable(::Business))
      return unless business
      GitHub.logger.info(
        "info.message" => "Starting copilot new_batch_update_org_settings_job",
      )
      copilot_business = Copilot::Business.new(business)

      perform_with_org_ids_scope(copilot_business, feature, org_ids: org_ids, target_value: target_value)
    end
  end

  # only update the single policy specified by the feature argument
  #
  # @param org_ids [Array<Integer>, nil] when provided, only these org IDs are considered.
  # @param target_value [String, nil] when provided, this value is used instead of reading from the business config.
  sig { params(copilot_business: Copilot::Business, feature: Symbol, org_ids: T.nilable(T::Array[Integer]), target_value: T.nilable(String)).void }
  def perform_with_org_ids_scope(copilot_business, feature, org_ids: nil, target_value: nil)
    GitHub.logger.info(
      "info.message" => "Starting copilot new_batch_update_org_settings_job perform_with_org_ids_scope",
    )
    return if copilot_business.is_standalone_business?

    policy = Copilot::Policies::PROPAGATABLE.find { |p| p.config_name.to_sym == feature }

    return unless policy

    biz_val = target_value || policy.value(copilot_business)

    # find all the configs for the orgs in this business
    copilot_orgs = copilot_business.copilot_organizations
    copilot_orgs = copilot_orgs.select { |co| org_ids.include?(co.id) } if org_ids
    copilot_orgs_by_id = copilot_orgs.index_by(&:id)
    scoped_org_ids = copilot_orgs_by_id.keys

    # use the org ids to find all corresponding configs in a single query
    Copilot::Configuration.where(configurable_id: scoped_org_ids, configurable_type: "Organization").find_each do |org_config|
      copilot_org = copilot_orgs_by_id[org_config.configurable_id]
      next unless copilot_org
      org_val = org_config[policy.config_name.to_sym]

      if target_value.nil?
        if policy.is_a?(Copilot::Policies::Concerns::Ruleable)
          biz_val = policy.inherited_value(copilot_org)
        end

        if biz_val == policy.config_values[:no_policy]
          if policy.is_a?(Copilot::Policies::Concerns::Business::Mailable)
            next unless policy.available_for?(copilot_org)

            policy.send_policy_updated_email_to_admins(copilot_org, value: "no_policy", previous_value: org_val)
          end
          next
        end

        next if biz_val == policy.config_values[:unconfigured]
      end

      if biz_val != org_val
        # only update the policy if the newly set business val is not equal to the org val
        policy.propagate_to_org_candidate(copilot_org, org_config, biz_val, org_val, send_email: feature == policy.config_name.to_sym)

        # only enqueue a single update if the policy changes
        Copilot::BatchUpdateUserSettingsJob.perform_later(copilot_org.id)
      end
    end
  end

  # Enqueue one `perform_later(business_id, feature)` for each propagatable
  # Copilot model policy that the given business has a setting rule for.
  #
  # Used by stafftools "resync from rules" actions. Returns the count of jobs
  # enqueued so callers can surface that to the operator.
  #
  # Note: `Copilot::BatchUpdateAllEnterpriseOrgSettingsJob` performs the same
  # intersection across every business. That job is temporary and is expected
  # to be removed shortly after the Copilot enterprise rules rollout
  # completes; this method is the canonical single-business helper that
  # outlives it.
  sig { params(business_id: Integer).returns(Integer) }
  def self.enqueue_for_all_features(business_id)
    propagatable_features = Copilot::Policies::PROPAGATABLE
      .select(&:setting_rules_supported_policy?)
      .map { |p| p.config_name.to_sym }
      .to_set

    return 0 if propagatable_features.empty?

    features = T.let(Set.new, T::Set[Symbol])

    Copilot::Settings::Setting
      .where(resource_type: "Business", resource_id: business_id, name: Copilot::Settings::CopilotModelsGroup::NAME)
      .includes(:rules)
      .find_each do |setting|
        setting.rules.each do |rule|
          values = rule.parameters.is_a?(Hash) ? rule.parameters["values"] : nil
          next unless values.is_a?(Hash)

          values.each_key do |model_name|
            feature = model_name.to_sym
            features << feature if propagatable_features.include?(feature)
          end
        end
      end

    features.each do |feature|
      perform_later(business_id, feature)
    end

    features.size
  end
end
