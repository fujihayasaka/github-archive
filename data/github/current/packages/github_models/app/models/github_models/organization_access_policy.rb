# typed: true
# frozen_string_literal: true

class GitHubModels::OrganizationAccessPolicy
  include GitHub::Memoizer

  sig { params(org: Organization).void }
  def initialize(org:)
    @org = org
  end

  sig { returns(GitHubModels::Types::OrganizationAccessPolicy) }
  def to_h
    allowed_custom_model_ids = allowed_custom_models
      .sort { |model_a, model_b| ModelsByok::CustomModel.key_and_name_sort(model_a, model_b) }
      .map { |model| model.id }

    {
      isAllowlist: allowlist?,
      isModelsEnabled: models_enabled_for_org?,
      isAccessConfigurable: models_available_for_org? && @org.models_access_configurable?,
      allowedModelKeys: allowed_default_models.map(&:slug).sort,
      allowedCustomModelIds: allowed_custom_model_ids,
      isMarketplaceEnabled: GitHub.marketplace_enabled?,
    }
  end

  sig { returns T::Boolean }
  def allowlist?
    global_block_rule.present?
  end

  sig { returns T::Array[GitHubModels::IModel] }
  def allowed_default_models
    T.cast(allowed_models.select { |model| model.is_a?(GitHubModels::IModel) }, T::Array[GitHubModels::IModel])
  end

  sig { returns T::Array[ModelsByok::CustomModel] }
  def allowed_custom_models
    T.cast(allowed_models.select { |model| model.is_a?(ModelsByok::CustomModel) }, T::Array[ModelsByok::CustomModel])
  end

  sig { returns T::Array[DefaultAndCustomModels::IModel] }
  def all_models
    all_default_models + all_custom_models
  end

  sig { returns T::Array[DefaultAndCustomModels::IModel] }
  def allowed_models
    return [] unless GitHub.models_enabled? && models_enabled_for_org?
    return @allowed_models if defined?(@allowed_models)

    result = all_models
    explicitly_allowed_default_model_slugs = self.explicitly_allowed_default_model_slugs.to_set
    explicitly_allowed_custom_model_ids = self.explicitly_allowed_custom_model_ids

    result = filter_out_blocked_models(result)

    if global_block_rule
      explicitly_allowed_publisher_ids = allowing_rules.select(&:publisher_specific?)
        .map(&:models_publisher_id).to_set
      explicitly_allowed_custom_key_ids = allowing_rules.select(&:custom_key_specific?)
        .map(&:custom_key_id).to_set
      result = result.select do |model|
        if model.respond_to?(:models_publisher_id) # default model
          explicitly_allowed_default_model_slugs.include?(model.slug) ||
            explicitly_allowed_publisher_ids.include?(T.unsafe(model).models_publisher_id)
        else # custom model
          explicitly_allowed_custom_model_ids.include?(T.unsafe(model).id) ||
            explicitly_allowed_custom_key_ids.include?(T.unsafe(model).custom_key_id)
        end
      end
    end

    @allowed_models = result
  end

  sig { params(actor: T.nilable(T.any(IntegrationInstallation, OauthApplication, OauthAccess, UserProgrammaticAccess))).returns(T::Boolean) }
  def programmatic_actor_with_write_access?(actor)
    async_is_programmatic_actor_with_write_access?(actor).sync
  end

  sig { params(actor: T.nilable(T.any(IntegrationInstallation, OauthApplication, OauthAccess, UserProgrammaticAccess))).returns(Promise[T::Boolean]) }
  def async_is_programmatic_actor_with_write_access?(actor)
    authzd_actor = case actor
    when UserProgrammaticAccess
      OrganizationProgrammaticAccessGrant.find_by(
        organization_id: @org.id,
        user_programmatic_access_id: actor.id
      )
    when IntegrationInstallation
      actor
    else
      nil
    end
    return Promise.resolve(T.let(false, T::Boolean)) if authzd_actor.nil?

    Platform::Loaders::Permissions::BatchAuthorize.load(
      action: :read_organization_models,
      actor: authzd_actor,
      subject: @org,
    ).then { |decision| decision.allow? }
  end

  # Public: Does the organization allow users to access a particular model?
  sig { params(model: DefaultAndCustomModels::IModel).returns(T::Boolean) }
  def model_allowed?(model)
    return false unless GitHub.models_enabled? && models_enabled_for_org?
    return true if rules.empty?

    relevant_rule = rule_for_model(model) || parent_rule_for(model)
    return relevant_rule.allow? if relevant_rule

    global_block_rule.nil?
  end

  # Public: Disable access to any model except for those that are explicitly allowed. Returns a Boolean indicating
  # success.
  sig { params(actor: User).returns(T::Boolean) }
  def use_allowlist(actor:)
    return true unless GitHub.models_enabled? # Models isn't a feature, nothing to do
    return true if global_block_rule # Models access is already restricted, nothing to do

    rule = @org.github_models_access_rules.new(allow: false)
    save_rule(rule, actor: actor)
  end

  # Public: Delete any global block rule the organization has, meaning particular models will be allowed unless
  # they're explicitly blocked. Returns a Boolean indicating success.
  sig { params(actor: User).returns(T::Boolean) }
  def use_blocklist(actor:)
    # Nothing to do if the Models feature as a whole isn't enabled.
    return false unless GitHub.models_enabled?

    global_block_rule = self.global_block_rule
    return true if global_block_rule.nil?

    delete_rule(global_block_rule, actor: actor)
  end

  # Public: Allow access to all models by deleting any existing policy rules. Returns a Boolean indicating success.
  sig { params(actor: User).returns(T::Boolean) }
  def allow_all_models(actor:)
    return true unless GitHub.models_enabled?

    # This will be less efficient than a bulk delete, but it avoids duplicating our rule-deletion tracking and
    # memoization logic, and should only be slow in the very rare case that an org with many rules is deleting them all.
    # Even then, there can only be as many rules as there are models and publishers (i.e. less than a hundred).
    success = rules.map do |rule|
      delete_rule(rule, actor: actor)
    end

    success.all?
  end

  # Public: Block many models at once. Returns a count of how many were successfully blocked.
  sig { params(models: T::Array[DefaultAndCustomModels::IModel], actor: User).returns(Integer) }
  def block_models(models, actor:)
    return 0 if models.empty?
    bulk_update_rules(-> { models.map { |model| block_model(model, actor: actor) } })
  end

  # Public: Block a particular model for the organization such that its members cannot use that model through the org.
  sig { params(model: DefaultAndCustomModels::IModel, actor: User).returns(T::Boolean) }
  def block_model(model, actor:)
    model_rule = rule_for_model(model)
    return true if already_blocked?(model_rule, actor: actor)

    # If there's no rule targeting the particular model, see if any rule targets the model's publisher:
    unless model_rule
      parent_rule = parent_rule_for(model)
      return true if parent_rule&.block?
      return true if parent_rule.nil? && global_block_rule.present?
    end

    model_rule ||= build_model_rule(model)
    model_rule.allow = false
    save_rule(model_rule, actor: actor)
  end

  # Public: Block many publishers at once. Returns a count of how many were successfully blocked.
  sig { params(publishers: T::Array[GitHubModels::Publisher], actor: User).returns(Integer) }
  def block_publishers(publishers, actor:)
    return 0 if publishers.empty?
    bulk_update_rules(-> { publishers.map { |publisher| block_publisher(publisher, actor: actor) } })
  end

  # Public: Block many custom keys at once. Returns a count of how many were successfully blocked.
  sig { params(custom_keys: T::Array[ModelsByok::CustomKey], actor: User).returns(Integer) }
  def block_custom_keys(custom_keys, actor:)
    return 0 if custom_keys.empty?
    bulk_update_rules(-> { custom_keys.map { |custom_key| block_custom_key(custom_key, actor: actor) } })
  end

  # Public: Block a particular publisher for the organization such that its members cannot use any of that publisher's
  # models through the org, unless a more specific rule overrides that.
  sig { params(publisher: GitHubModels::Publisher, actor: User).returns(T::Boolean) }
  def block_publisher(publisher, actor:)
    rule = rule_for_publisher(publisher.id)
    return true if already_blocked?(rule, actor: actor)
    return true if rule.nil? && global_block_rule.present?

    rule ||= @org.github_models_access_rules.new(publisher: publisher)
    rule.allow = false
    save_rule(rule, actor: actor)
  end

  # Public: Block a particular custom key for the organization such that its members cannot use any of the models
  # provided by that key, unless a more specific rule overrides that.
  sig { params(custom_key: ModelsByok::CustomKey, actor: User).returns(T::Boolean) }
  def block_custom_key(custom_key, actor:)
    rule = rule_for_custom_key(custom_key.id)
    return true if already_blocked?(rule, actor: actor)
    return true if rule.nil? && global_block_rule.present?

    rule ||= @org.github_models_access_rules.new(custom_key: custom_key)
    rule.allow = false
    save_rule(rule, actor: actor)
  end

  # Public: Allow many models at once. Returns a count of how many were successfully allowed.
  sig { params(models: T::Array[DefaultAndCustomModels::IModel], actor: User).returns(Integer) }
  def allow_models(models, actor:)
    return 0 if models.empty?
    bulk_update_rules(-> { models.map { |model| allow_model(model, actor: actor) } })
  end

  # Public: Allow a particular model for the organization such that its members can use that model through the org.
  sig { params(model: DefaultAndCustomModels::IModel, actor: User).returns(T::Boolean) }
  def allow_model(model, actor:)
    model_rule = rule_for_model(model)
    return true if already_allowed?(model_rule, actor: actor)

    if model_rule.nil?
      # If the model has no specific rule, then any rule for its publisher or custom key takes precedence:
      parent_rule = parent_rule_for(model)
      return true if parent_rule&.allow?

      # Otherwise if no rules target the default model or its publisher, or the custom model and its custom key, then
      # so long as the org hasn't turned off Models entirely, the model is allowed:
      return true if global_block_rule.nil? && parent_rule.nil?
    end

    model_rule ||= build_model_rule(model)
    model_rule.allow = true
    save_rule(model_rule, actor: actor)
  end

  # Public: Allow many publishers at once. Returns a count of how many were successfully allowed.
  sig { params(publishers: T::Array[GitHubModels::Publisher], actor: User).returns(Integer) }
  def allow_publishers(publishers, actor:)
    return 0 if publishers.empty?
    bulk_update_rules(-> { publishers.map { |publisher| allow_publisher(publisher, actor: actor) } })
  end

  # Public: Allow many custom keys at once. Returns a count of how many were successfully allowed.
  sig { params(custom_keys: T::Array[ModelsByok::CustomKey], actor: User).returns(Integer) }
  def allow_custom_keys(custom_keys, actor:)
    return 0 if custom_keys.empty?
    bulk_update_rules(-> { custom_keys.map { |custom_key| allow_custom_key(custom_key, actor: actor) } })
  end

  # Public: Allow a particular publisher for the organization such that its members are allowed to use any of that
  # publisher's models through the org, unless a more specific rule overrides that.
  sig { params(publisher: GitHubModels::Publisher, actor: User).returns(T::Boolean) }
  def allow_publisher(publisher, actor:)
    rule = rule_for_publisher(publisher.id)
    return true if already_allowed?(rule, actor: actor)
    return true if global_block_rule.nil? && rule.nil? # no rule governs this publisher specifically, nothing to do

    rule ||= @org.github_models_access_rules.new(publisher: publisher)
    rule.allow = true
    save_rule(rule, actor: actor)
  end

  # Public: Allow a particular custom key for the organization such that its members are allowed to use any of that
  # custom key's models through the org, unless a more specific rule overrides that.
  sig { params(custom_key: ModelsByok::CustomKey, actor: User).returns(T::Boolean) }
  def allow_custom_key(custom_key, actor:)
    rule = rule_for_custom_key(custom_key.id)
    return true if already_allowed?(rule, actor: actor)
    return true if global_block_rule.nil? && rule.nil? # no rule governs this custom key specifically, nothing to do

    rule ||= @org.github_models_access_rules.new(custom_key: custom_key)
    rule.allow = true
    save_rule(rule, actor: actor)
  end

  sig { returns T::Array[GitHubModels::IModel] }
  def all_default_models
    return @all_default_models if @all_default_models
    # Includes restricted models even if the orgs' users aren't allowed by GitHub to try them in the playground,
    # so that org admins can set rules around them since they're visible in the public catalog:
    result = GitHubModels.domain.models.find_many(publicly_visible_only: true)
    if @rules_by_id
      rules = @rules_by_id.values
      GitHub::PrefillAssociations.prefill_associations(rules, :model, available_records: result)
    end
    @all_default_models = result
  end

  sig { returns T::Array[ModelsByok::CustomModel] }
  def all_custom_models
    return [] unless @org.custom_models_enabled?

    return @all_custom_models if @all_custom_models
    result = ModelsByok::CustomModel.for_org(@org).includes(:custom_key).to_a.sort do |model_a, model_b|
      ModelsByok::CustomModel.key_and_name_sort(model_a, model_b)
    end
    if @rules_by_id
      rules = @rules_by_id.values
      GitHub::PrefillAssociations.prefill_associations(rules, :custom_model, available_records: result)
    end
    @all_custom_models = result
  end

  # Public: Is models access available for this org? (the user can turn it on in org settings)
  sig { returns T::Boolean }
  def models_available_for_org?
    !!GitHub.models_enabled?
  end

  # Public: Are members of the organization allowed to use Models at all?
  sig { returns T::Boolean }
  memoize def models_enabled_for_org?
    models_available_for_org? && @org.models_access_enabled?
  end

  private

  sig { params(model: DefaultAndCustomModels::IModel).returns(T.nilable(GitHubModels::OrganizationAccessRule)) }
  def parent_rule_for(model)
    if model.respond_to?(:models_publisher_id)
      rule_for_publisher(T.unsafe(model).models_publisher_id)
    elsif model.respond_to?(:custom_key_id)
      rule_for_custom_key(T.unsafe(model).custom_key_id)
    end
  end

  sig do
    params(model: DefaultAndCustomModels::IModel).returns(GitHubModels::OrganizationAccessRule)
  end
  def build_model_rule(model)
    if model.is_a?(GitHubModels::IModel) # default model
      @org.github_models_access_rules.new(model_slug: model.slug)
    else # custom model
      @org.github_models_access_rules.new(custom_model: model)
    end
  end

  # Private: Returns the IDs of model publishers who have been explicitly allowed by the org. Does not include the
  # publishers of models when the model itself was allowed.
  sig { returns T::Array[Integer] }
  def allowed_publisher_ids
    allowing_rules.select(&:publisher_specific?).map(&:models_publisher_id).uniq.sort
  end

  sig { params(models: T::Array[DefaultAndCustomModels::IModel]).returns(T::Array[DefaultAndCustomModels::IModel]) }
  def filter_out_blocked_models(models)
    blocked_publisher_ids = self.blocked_publisher_ids
    blocked_default_model_slugs = self.blocked_default_model_slugs
    blocked_custom_key_ids = self.blocked_custom_key_ids
    blocked_custom_model_ids = self.blocked_custom_model_ids

    models = models.reject do |model|
      if model.is_a?(GitHubModels::IModel) # default model
        blocked_default_model_slugs.include?(model.slug)
      else # custom model
        blocked_custom_model_ids.include?(model.id)
      end
    end

    models.reject do |model|
      if model.respond_to?(:models_publisher_id) # default model
        blocked_publisher_ids.include?(T.unsafe(model).models_publisher_id) &&
          !explicitly_allowed_default_model_slugs.include?(model.slug)
      else # custom model
        blocked_custom_key_ids.include?(T.unsafe(model).custom_key_id) &&
          !explicitly_allowed_custom_model_ids.include?(T.unsafe(model).id)
      end
    end
  end

  # Private: Returns the IDs of model publishers who have been explicitly blocked by the org. Does not include the
  # publishers of models when the model itself was blocked.
  sig { returns T::Set[Integer] }
  def blocked_publisher_ids
    blocking_rules.select(&:publisher_specific?).map(&:models_publisher_id).to_set
  end

  sig { returns T::Set[Integer] }
  def blocked_custom_key_ids
    blocking_rules.select(&:custom_key_specific?).map(&:custom_key_id).to_set
  end

  sig { returns T::Array[String] }
  def explicitly_allowed_default_model_slugs
    allowing_rules.select(&:default_model_specific?).map(&:model_slug).compact.uniq.sort
  end

  sig { returns T::Array[Integer] }
  def explicitly_allowed_custom_model_ids
    allowing_rules.select(&:custom_model_specific?).map(&:custom_model_id).sort
  end

  sig { returns T::Array[String] }
  def blocked_default_model_slugs
    blocking_rules.select(&:default_model_specific?).map(&:model_slug).compact.uniq.sort
  end

  sig { returns T::Array[Integer] }
  def blocked_custom_model_ids
    blocking_rules.select(&:custom_model_specific?).map(&:custom_model_id).sort
  end

  sig { returns T::Set[String] }
  def all_allowed_default_model_slugs
    @all_allowed_default_model_slugs ||= allowed_models.map(&:slug).to_set
  end

  sig { returns T.nilable(GitHubModels::OrganizationAccessRule) }
  def global_block_rule
    blocking_rules.detect(&:global?)
  end

  sig { params(rule: GitHubModels::OrganizationAccessRule, actor: User).returns(T::Boolean) }
  def save_rule(rule, actor:)
    rule.actor = actor
    success = rule.save
    if success
      @rules_by_id[rule.id] = rule if @rules_by_id
      clear_memoization
    end
    success
  end

  sig { params(rule: GitHubModels::OrganizationAccessRule, actor: User).returns(T::Boolean) }
  def delete_rule(rule, actor:)
    rule.actor = actor
    rule.destroy
    success = rule.destroyed?
    if success
      @rules_by_id&.delete(rule.id)
      clear_memoization
    end
    success
  end

  sig { void }
  def clear_memoization
    remove_instance_variable(:@allowed_models) if defined?(@allowed_models)
    remove_instance_variable(:@all_allowed_default_model_slugs) if defined?(@all_allowed_default_model_slugs)
  end

  # Private: Returns a count of how many updates were successful.
  sig { params(apply_bulk_updates: T.proc.returns(T::Array[T::Boolean])).returns(Integer) }
  def bulk_update_rules(apply_bulk_updates)
    results = apply_bulk_updates.call
    results.count { |success| success }
  end

  sig { returns T::Array[GitHubModels::OrganizationAccessRule] }
  def rules
    unless @rules_by_id
      list = @org.github_models_access_rules.order(:id).to_a
      if @all_default_models
        GitHub::PrefillAssociations.prefill_associations(list, :model, available_records: @all_default_models)
      end
      if @all_custom_models
        GitHub::PrefillAssociations.prefill_associations(list, :custom_model, available_records: @all_custom_models)
      end
      @rules_by_id = T.let(
        list.map { |rule| [rule.id, rule] }.to_h,
        T.nilable(T::Hash[Integer, GitHubModels::OrganizationAccessRule]),
      )
    end
    T.must(@rules_by_id).values
  end

  sig { returns T::Array[GitHubModels::OrganizationAccessRule] }
  def blocking_rules
    rules.select(&:block?)
  end

  sig { returns T::Array[GitHubModels::OrganizationAccessRule] }
  def allowing_rules
    rules.select(&:allow?)
  end

  sig { params(model: DefaultAndCustomModels::IModel).returns(T.nilable(GitHubModels::OrganizationAccessRule)) }
  def rule_for_model(model)
    rules.detect { |rule| rule.for_model?(model) }
  end

  sig { params(publisher_id: T.nilable(Integer)).returns(T.nilable(GitHubModels::OrganizationAccessRule)) }
  def rule_for_publisher(publisher_id)
    return unless publisher_id
    rules.detect { |rule| rule.publisher_specific? && rule.models_publisher_id == publisher_id }
  end

  sig { params(custom_key_id: T.nilable(Integer)).returns(T.nilable(GitHubModels::OrganizationAccessRule)) }
  def rule_for_custom_key(custom_key_id)
    return unless custom_key_id
    rules.detect { |rule| rule.custom_key_specific? && rule.custom_key_id == custom_key_id }
  end

  sig { params(rule: T.nilable(GitHubModels::OrganizationAccessRule), actor: User).returns(T::Boolean) }
  def already_blocked?(rule, actor:)
    return true if rule&.block?

    # Model, publisher, or custom key will be blocked upon deleting its allow rule:
    return delete_rule(rule, actor: actor) if rule&.allow? && global_block_rule.present?

    false
  end

  sig { params(rule: T.nilable(GitHubModels::OrganizationAccessRule), actor: User).returns(T::Boolean) }
  def already_allowed?(rule, actor:)
    return true if rule&.allow? # the model, publisher, or custom key is already explicitly allowed

    # Model, publisher, or custom key will be allowed upon deleting its block rule:
    return delete_rule(rule, actor: actor) if rule&.block? && global_block_rule.nil?

    false
  end
end
