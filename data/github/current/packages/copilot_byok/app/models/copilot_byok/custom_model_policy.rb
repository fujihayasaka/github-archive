# typed: true
# frozen_string_literal: true

# Public: Represents the policy set by an enterprise about which of its bring your own key (BYOK) custom models can be
# used by its organizations. Does not govern custom models owned by the enterprise's organizations, only those
# owned by the enterprise itself.
class CopilotByok::CustomModelPolicy
  ORG_LIMIT = 1000

  sig { params(business: Business).void }
  def initialize(business:)
    @business = business
  end

  # Public: Represents the result of trying to make an enterprise custom model policy change.
  class Result
    sig { returns T::Array[String] }
    attr_reader :errors

    sig { params(success: T::Boolean, errors: T::Array[String]).void }
    def initialize(success:, errors: [])
      @success = success
      @errors = errors
    end

    sig { returns(T::Boolean) }
    def success?
      @success
    end
  end

  # Public: Returns all the enterprise's custom models that the specified organization is allowed to use.
  sig { params(org: Organization).returns(T::Array[CopilotByok::CustomModel]) }
  def enabled_models_for(org)
    custom_models.select { |custom_model| custom_model_enabled?(custom_model, org: org) }
  end

  # Public: Returns organizations within the enterprise that have at least one enterprise custom model enabled
  # by an organization-specific rule.
  sig { returns T::Array[Organization] }
  def targeted_orgs_with_enabled_models
    @business.copilot_custom_model_rules.org_specific.enabled.select(:organization_id).distinct
      .includes(:organization).map(&:organization).compact
  end

  # Public: Allow a particular custom model to be used by all the specified organizations within this enterprise.
  sig do
    params(custom_model: CopilotByok::CustomModel, org_ids: T::Array[T.any(Integer, String)]).returns(Result)
  end
  def enable_custom_model_for_orgs(custom_model, org_ids:)
    bulk_update_custom_model_rules(custom_model, org_ids: org_ids) do |rule|
      rule.status = :enabled
    end
  end

  # Public: Disallow a particular custom model from being used by any of the specified organizations within
  # this enterprise.
  sig do
    params(custom_model: CopilotByok::CustomModel, org_ids: T::Array[T.any(Integer, String)]).returns(Result)
  end
  def disable_custom_model_for_orgs(custom_model, org_ids:)
    bulk_update_custom_model_rules(custom_model, org_ids: org_ids) do |rule|
      rule.status = :disabled
    end
  end

  # Public: Allow a particular custom model to be used by every organization currently within this enterprise as well
  # as any new organizations that get added later.
  sig { params(custom_model: CopilotByok::CustomModel).returns(Result) }
  def enable_custom_model_for_all_orgs(custom_model)
    update_global_rule_for(custom_model) do |global_rule|
      global_rule.status = :enabled
    end
  end

  # Public: Delete the rule that allows or disallows access for all organizations in the enterprise, so that access
  # can be controlled per organization.
  sig { params(target: CopilotByok::CustomModel).returns(Result) }
  def clear_all_org_rule_for(target)
    global_rule = global_rule_for(target)
    return Result.new(success: true) if global_rule.nil?

    global_rule.destroy
    return Result.new(success: true) if global_rule.destroyed?

    Result.new(success: false, errors: global_rule.errors.full_messages)
  end

  # Public: Returns a mapping of custom models owned by this enterprise to their status for the organizations in the
  # enterprise.
  #
  # Returns a Hash whose keys are custom model IDs.
  sig { returns T::Hash[Integer, CopilotByok::Types::EnterpriseCustomModelAccessStatus] }
  def to_h
    custom_models.each_with_object({}) do |custom_model, hash|
      enabled_for_all_orgs = enabled_for_all_orgs?(custom_model)
      hash[custom_model.id] = T.let({
        enabledForAllOrgs: enabled_for_all_orgs,
        allowedOrgIds: enabled_for_all_orgs ? nil : allowed_org_ids_for(custom_model),
      }, CopilotByok::Types::EnterpriseCustomModelAccessStatus)
    end
  end

  # Public: Was the given enterprise-owned model allowed for all organizations within the enterprise, those currently
  # in it as well as any added later?
  sig { params(custom_model: CopilotByok::CustomModel).returns(T::Boolean) }
  def enabled_for_all_orgs?(custom_model)
    # If the model is turned off entirely, it's not enabled for anyone:
    return false unless custom_model.copilot_chat_enabled?

    global_model_rule = global_rule_for(custom_model)
    return global_model_rule.enabled? if global_model_rule.persisted?

    custom_key = custom_model.custom_key
    if custom_key
      global_key_rule = global_rule_for(custom_key)
      return global_key_rule.enabled? if global_key_rule.persisted?
    end

    false
  end

  # Public: Get a list of the database IDs of organizations that the enterprise has allowed to use the given
  # enterprise-owned model.
  sig { params(target: CopilotByok::CustomModel).returns(T::Array[Integer]) }
  def allowed_org_ids_for(target)
    orgs.select { |org| custom_model_enabled?(target, org: org) }.map(&:id)
  end

  # Public: Returns all the custom models this enterprise has added. Does not include custom models added by the
  # individual orgs within the enterprise.
  sig { returns T::Array[CopilotByok::CustomModel] }
  def custom_models
    return @custom_models if @custom_models
    result = CopilotByok::CustomModel.for_enterprise(@business.id).includes(:custom_key).order(:id).to_a
    GitHub::PrefillAssociations.prefill_associations(result, :organization, available_records: orgs)
    GitHub::PrefillAssociations.prefill_associations(result, :business, available_records: [@business])
    @custom_models = result
  end

  # Public: Returns all the custom keys that provide custom models for this enterprise.
  sig { returns T::Array[CopilotByok::CustomKey] }
  def custom_keys
    return @custom_keys if @custom_keys
    result = custom_models.map(&:custom_key).uniq.compact
    GitHub::PrefillAssociations.prefill_associations(result, :organization, available_records: orgs)
    @custom_keys = result
  end

  private

  sig do
    params(target: T.any(CopilotByok::CustomModel, CopilotByok::CustomKey)).returns(CopilotByok::CustomModelRule)
  end
  def global_rule_for(target)
    existing_rule = rules.detect { |r| r.global? && r.target_type == target.class.name && r.target_id == target.id }
    existing_rule || @business.copilot_custom_model_rules.new(target: target, organization_id: nil)
  end

  sig { params(custom_model: CopilotByok::CustomModel, org: Organization).returns(T::Boolean) }
  def custom_model_enabled?(custom_model, org:)
    # If the model is turned off entirely, it's not enabled for anyone:
    return false unless custom_model.copilot_chat_enabled?

    return true if custom_model_enabled_by_model_specific_rule?(custom_model, org: org)

    if enabled_for_all_orgs?(custom_model) || custom_key_enabled_by_rule?(custom_model.custom_key, org: org)
      # Unless a model has been explicitly disabled, then its custom key having been allowed or the model having
      # been globally allowed is enough to allow it:
      return !custom_model_disabled_by_model_specific_rule?(custom_model, org: org)
    end

    false
  end

  # Private: Does the enterprise have a rule that applies to the given org that allows the specified model
  # in particular?
  sig { params(custom_model: CopilotByok::CustomModel, org: Organization).returns(T::Boolean) }
  def custom_model_enabled_by_model_specific_rule?(custom_model, org:)
    applicable_rules = rules.select do |r|
      r.custom_model_specific? && r.custom_model_id == custom_model.id && r.applies_to_org?(org)
    end
    # If there's a rule about this org in particular, prefer it over any global rule:
    org_specific_rule = applicable_rules.detect { |r| r.organization_id == org.id }
    org_specific_rule ? org_specific_rule.enabled? : applicable_rules.any?(&:enabled?)
  end

  # Private: Does the enterprise have a rule that applies to the given org that allows the specified key?
  sig { params(custom_key: T.nilable(CopilotByok::CustomKey), org: Organization).returns(T::Boolean) }
  def custom_key_enabled_by_rule?(custom_key, org:)
    return false if custom_key.nil?

    key_specific_rules = rules.select { |r| r.custom_key_specific? && r.custom_key_id == custom_key.id }
    key_specific_rules.any? { |r| r.enabled? && r.applies_to_org?(org) }
  end

  # Private: Does the enterprise have a rule that applies to the given org that disallows the specified model
  # in particular?
  sig { params(custom_model: CopilotByok::CustomModel, org: Organization).returns(T::Boolean) }
  def custom_model_disabled_by_model_specific_rule?(custom_model, org:)
    model_specific_rules = rules.select { |r| r.custom_model_specific? && r.custom_model_id == custom_model.id }
    model_specific_rules.any? { |r| r.disabled? && r.applies_to_org?(org) }
  end

  sig { returns T::Array[Organization] }
  def orgs
    return @orgs if @orgs
    result = @business.organizations.order(:id).limit(ORG_LIMIT).to_a
    GitHub::PrefillAssociations.prefill_associations(result, :business_membership)
    @orgs = result
  end

  sig { returns T::Array[CopilotByok::CustomModelRule] }
  def rules
    rules_by_id.values
  end

  sig { returns T::Hash[Integer, CopilotByok::CustomModelRule] }
  def rules_by_id
    return @rules_by_id if @rules_by_id
    rules = @business.copilot_custom_model_rules.to_a
    GitHub::PrefillAssociations.prefill_associations(rules, :organization, available_records: orgs)
    GitHub::PrefillAssociations.prefill_associations(rules, :business, available_records: [@business])
    GitHub::PrefillAssociations.prefill_associations(rules, :target, available_records: custom_models + custom_keys)
    @rules_by_id = rules.index_by(&:id)
  end

  sig do
    params(
      target: CopilotByok::CustomModel,
      block: T.proc.params(rule: CopilotByok::CustomModelRule).void
    ).returns(Result)
  end
  def update_global_rule_for(target, &block)
    global_rule = global_rule_for(target)
    block.call(global_rule)
    errors = save_rule(global_rule)
    errors.nil? ? Result.new(success: true) : Result.new(success: false, errors: errors)
  end

  sig do
    params(
      custom_model: CopilotByok::CustomModel,
      org_ids: T::Array[T.any(Integer, String)],
      block: T.proc.params(rule: CopilotByok::CustomModelRule).void
    ).returns(Result)
  end
  def bulk_update_custom_model_rules(custom_model, org_ids:, &block)
    org_ids = org_ids.map(&:to_i).to_set
    custom_model_rules = rules.select do |r|
      r.custom_model_specific? && org_ids.include?(r.organization_id) && r.custom_model == custom_model
    end
    rules_by_org_id = custom_model_rules.index_by(&:organization_id)
    org_ids.each do |org_id|
      # Make sure there's a rule targeting the custom model for each of the specified organizations:
      rules_by_org_id[org_id] ||= @business.copilot_custom_model_rules.new(
        target: custom_model,
        organization_id: org_id,
      )
    end
    success = T.let(true, T::Boolean)
    errors = T.let([], T::Array[String])
    rules_by_org_id.values.each do |rule|
      block.call(rule)
      rule_errors = save_rule(rule)
      if rule_errors.present?
        success = false
        errors += rule_errors
      end
    end
    Result.new(success: success, errors: errors)
  end

  # Private: Save the given rule and return any errors that occurred. A return value of nil indicates the save
  # was successful.
  sig { params(rule: CopilotByok::CustomModelRule).returns(T.nilable(T::Array[String])) }
  def save_rule(rule)
    if rule.save
      # Update memoization so the new or updated rule will be returned by #rules on subsequent calls:
      @rules_by_id[rule.id] = rule if defined?(@rules_by_id)
      nil
    else
      rule.errors.full_messages
    end
  end
end
