# typed: true
# frozen_string_literal: true

class GitHubModels::OrganizationAccessPolicy
  sig { params(org: Organization).void }
  def initialize(org:)
    @org = org
  end

  sig { returns GitHubModels::Types::OrganizationAccessPolicy }
  def to_h
    {
      isAllowlist: global_block_rule.present?,
      isModelsEnabled: !!(GitHub.models_enabled? && models_enabled_for_org?),
      allowedModelKeys: allowed_models.map(&:key).sort,
    }
  end

  sig { returns T::Array[GitHubModels::CatalogItem] }
  def allowed_models
    return [] unless GitHub.models_enabled? && models_enabled_for_org?
    return @allowed_models if defined?(@allowed_models)

    result = all_catalog_items

    explicitly_allowed_catalog_item_keys = self.explicitly_allowed_catalog_item_keys.to_set
    blocked_catalog_item_keys = blocking_rules.select(&:model_specific?).map(&:catalog_item_key).to_set
    result = result.reject { |catalog_item| blocked_catalog_item_keys.include?(catalog_item.key) }

    blocked_publisher_ids = blocking_rules.select(&:publisher_specific?).map(&:models_publisher_id).to_set
    result = result.reject do |catalog_item|
      blocked_publisher_ids.include?(catalog_item.github_models_publisher_id) &&
        !explicitly_allowed_catalog_item_keys.include?(catalog_item.key)
    end

    if global_block_rule
      explicitly_allowed_publisher_ids = allowing_rules.select(&:publisher_specific?)
        .map(&:models_publisher_id).to_set
      result = result.select do |catalog_item|
        explicitly_allowed_catalog_item_keys.include?(catalog_item.key) ||
          explicitly_allowed_publisher_ids.include?(catalog_item.github_models_publisher_id)
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
  sig { params(catalog_item: GitHubModels::CatalogItem).returns(T::Boolean) }
  def model_allowed?(catalog_item)
    return false unless GitHub.models_enabled? && models_enabled_for_org?
    return true if rules.empty?

    relevant_rule = rule_for_model(catalog_item) ||
      # Assuming here that each catalog item will have a non-nil publisher ID.
      # TODO: https://github.com/github/models/issues/817
      rule_for_publisher(catalog_item.github_models_publisher_id)
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

  # Public: Block many models at once. Returns a count of how many were successfully blocked.
  sig { params(catalog_items: T::Array[GitHubModels::CatalogItem], actor: User).returns(Integer) }
  def block_models(catalog_items, actor:)
    return 0 if catalog_items.empty?
    bulk_update_rules(-> { catalog_items.map { |catalog_item| block_model(catalog_item, actor: actor) } })
  end

  # Public: Block a particular model for the organization such that its members cannot use that model through the org.
  sig { params(catalog_item: GitHubModels::CatalogItem, actor: User).returns(T::Boolean) }
  def block_model(catalog_item, actor:)
    model_rule = rule_for_model(catalog_item)
    return true if already_blocked?(model_rule, actor: actor)

    # If there's no rule targeting the particular model, see if any rule targets the model's publisher:
    unless model_rule
      publisher_rule = rule_for_publisher(catalog_item.github_models_publisher_id)
      return true if publisher_rule&.block?
    end

    model_rule ||= @org.github_models_access_rules.new(catalog_item: catalog_item)
    model_rule.allow = false
    save_rule(model_rule, actor: actor)
  end

  # Public: Block many publishers at once. Returns a count of how many were successfully blocked.
  sig { params(publishers: T::Array[GitHubModels::Publisher], actor: User).returns(Integer) }
  def block_publishers(publishers, actor:)
    return 0 if publishers.empty?
    bulk_update_rules(-> { publishers.map { |publisher| block_publisher(publisher, actor: actor) } })
  end

  # Public: Block a particular publisher for the organization such that its members cannot use any of that publisher's
  # models through the org, unless a more specific rule overrides that.
  sig { params(publisher: GitHubModels::Publisher, actor: User).returns(T::Boolean) }
  def block_publisher(publisher, actor:)
    rule = rule_for_publisher(publisher.id)
    return true if already_blocked?(rule, actor: actor)

    rule ||= @org.github_models_access_rules.new(publisher: publisher)
    rule.allow = false
    save_rule(rule, actor: actor)
  end

  # Public: Allow many models at once. Returns a count of how many were successfully allowed.
  sig { params(catalog_items: T::Array[GitHubModels::CatalogItem], actor: User).returns(Integer) }
  def allow_models(catalog_items, actor:)
    return 0 if catalog_items.empty?
    bulk_update_rules(-> { catalog_items.map { |catalog_item| allow_model(catalog_item, actor: actor) } })
  end

  # Public: Allow a particular model for the organization such that its members can use that model through the org.
  sig { params(catalog_item: GitHubModels::CatalogItem, actor: User).returns(T::Boolean) }
  def allow_model(catalog_item, actor:)
    model_rule = rule_for_model(catalog_item)
    return true if already_allowed?(model_rule, actor: actor)

    if model_rule.nil?
      # If the model has no specific rule, then any rule for its publisher takes precedence:
      publisher_rule = rule_for_publisher(catalog_item.github_models_publisher_id)
      return true if publisher_rule&.allow?

      # Otherwise if no rules target the model or its publisher, so long as the org hasn't turned off Models entirely,
      # the model is allowed:
      return true if global_block_rule.nil? && publisher_rule.nil?
    end

    model_rule ||= @org.github_models_access_rules.new(catalog_item: catalog_item)
    model_rule.allow = true
    save_rule(model_rule, actor: actor)
  end

  # Public: Allow many publishers at once. Returns a count of how many were successfully allowed.
  sig { params(publishers: T::Array[GitHubModels::Publisher], actor: User).returns(Integer) }
  def allow_publishers(publishers, actor:)
    return 0 if publishers.empty?
    bulk_update_rules(-> { publishers.map { |publisher| allow_publisher(publisher, actor: actor) } })
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

  sig { returns T::Array[GitHubModels::CatalogItem] }
  def all_catalog_items
    return @all_catalog_items if @all_catalog_items
    result = GitHubModels::CatalogItem.order(:id).to_a
    if @rules_by_id
      GitHub::PrefillAssociations.prefill_associations(@rules_by_id.values, :catalog_item, available_records: result)
    end
    @all_catalog_items = result
  end

  private

  # Private: Are members of the organization allowed to use Models at all?
  sig { returns T::Boolean }
  def models_enabled_for_org?
    return @models_enabled_for_org if defined?(@models_enabled_for_org)
    @models_enabled_for_org = @org.models_access_enabled?
  end

  # Private: Returns the IDs of model publishers who have been explicitly allowed by the org. Does not include the
  # publishers of models when the model itself was allowed.
  sig { returns T::Array[Integer] }
  def allowed_publisher_ids
    allowing_rules.select(&:publisher_specific?).map(&:models_publisher_id).uniq.sort
  end

  # Private: Returns the IDs of model publishers who have been explicitly blocked by the org. Does not include the
  # publishers of models when the model itself was blocked.
  sig { returns T::Array[Integer] }
  def blocked_publisher_ids
    blocking_rules.select(&:publisher_specific?).map(&:models_publisher_id).uniq.sort
  end

  sig { returns T::Array[String] }
  def explicitly_allowed_catalog_item_keys
    allowing_rules.select(&:model_specific?).map(&:catalog_item_key).uniq.sort
  end

  sig { returns T::Array[String] }
  def blocked_model_keys
    blocking_rules.select(&:model_specific?).map(&:catalog_item_key).uniq.sort
  end

  sig { returns T::Set[String] }
  def all_allowed_catalog_item_keys
    @all_allowed_catalog_item_keys ||= allowed_models.map(&:key).to_set
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
    remove_instance_variable(:@all_allowed_catalog_item_keys) if defined?(@all_allowed_catalog_item_keys)
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
      if @all_catalog_items
        GitHub::PrefillAssociations.prefill_associations(list, :catalog_item, available_records: @all_catalog_items)
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

  sig { params(catalog_item: GitHubModels::CatalogItem).returns(T.nilable(GitHubModels::OrganizationAccessRule)) }
  def rule_for_model(catalog_item)
    rules.detect { |rule| rule.catalog_item_key == catalog_item.key }
  end

  sig { params(publisher_id: T.nilable(Integer)).returns(T.nilable(GitHubModels::OrganizationAccessRule)) }
  def rule_for_publisher(publisher_id)
    return unless publisher_id
    rules.detect { |rule| rule.publisher_specific? && rule.models_publisher_id == publisher_id }
  end

  sig { params(rule: T.nilable(GitHubModels::OrganizationAccessRule), actor: User).returns(T::Boolean) }
  def already_blocked?(rule, actor:)
    return true if rule&.block?
    return false if global_block_rule.nil?
    return true if rule.nil? # model or publisher already blocked via global block rule
    delete_rule(rule, actor: actor) # model or publisher will be blocked upon deleting its allow rule
  end

  sig { params(rule: T.nilable(GitHubModels::OrganizationAccessRule), actor: User).returns(T::Boolean) }
  def already_allowed?(rule, actor:)
    return true if rule&.allow? # the model or publisher is already explicitly allowed

    # Model or publisher will be allowed upon deleting its block rule:
    return delete_rule(rule, actor: actor) if rule&.block? && global_block_rule.nil?

    false
  end
end
