# typed: true
# frozen_string_literal: true

require "set"

module Repository::TagProtectionStatesDependency
  extend T::Sig

  # Public: Create a new tag protection rule for the given repository
  #
  # pattern - a glob pattern to match against the tag name
  # enabled - the desired state of the tag protection for the give repository
  #
  # Returns the created RepositoryTagProtectionState record.
  def create_tag_protection_state(pattern:, enabled: true)
    T.bind(self, Repository)

    RepositoryTagProtectionState.create({ repository_id: self.id, pattern: pattern, enabled: enabled })
  end

  # Public: Determine if tag protection feature is available for the given repository.
  # Returns one of:
  #   :enabled - Tag protections are enabled and available on this repository
  #   :not_in_plan - Tag protections are enabled, but not available on this subscription plan
  #   :disabled - Tag protections are disabled and can't be enabled by switching plans
  def tag_protections_availability
    T.bind(self, Repository)

    begin
      promises = [
        async_plan_supports?(:protected_tags),
        async_scoped_feature_flag_enabled?(:repos_remove_tag_protections),
        async_scoped_feature_flag_enabled?(:repos_remove_tag_protections_opt_out),
      ]

      plan_supports, remove_ff, opt_out_ff = Promise.all(promises).sync

      if remove_ff && !opt_out_ff && !RepositoryTagProtectionState.find_by(repository_id: self.id, enabled: true)
        # If remove FF is enabled, and customer not opted out from remove, and no enabled rules, then feature is fully disabled
        :disabled
      elsif !plan_supports
        # Tag protections are enabled, but not available on this subscription plan
        :not_in_plan
      else
        :enabled
      end
    end
  end

  def tag_protection_states
    T.bind(self, Repository)

    @tag_protection_states ||= RepositoryTagProtectionState.where(repository_id: self.id)
  end

  # Public: Returns a boolean indicating whether the given tag name matches
  # a tag protection rule for this repository.
  #
  # tag_name - An unqualified tag name, eg: v1.1.0
  #
  # Returns a Boolean
  def tag_protected?(tag_name)
    RepositoryTagProtectionState.tag_is_protected?(tag_protection_states, tag_name)
  end

  SINGLE_RULESET_NAME = "Imported tag protections"
  CREATE_RULESET_NAME = "Imported tag create protections"
  DELETE_RULESET_NAME = "Imported tag delete protections"

  def existing_imported_ruleset_names
    T.bind(self, Repository)

    if plan_supports?(:protected_tags) && plan_supports?(:protected_branches)
      rulesets.where(name: [SINGLE_RULESET_NAME, CREATE_RULESET_NAME, DELETE_RULESET_NAME,])
        .pluck(:name).to_a
    end
  end

  # Public: Import all enabled tag protections to the ruleset infrastructure
  #
  # On success, returns an array of created persisted rulesets.
  sig do params(
    actor: T.untyped, # not going to work out the nuanced typing for code which is being removed in a few months
    single_ruleset: T::Boolean,
    is_auto_import: T::Boolean)
    .returns(T::Array[RepositoryRuleset])
  end
  def import_tag_protections_to_rulesets(actor, single_ruleset:, is_auto_import: false)
    T.bind(self, Repository)

    enabled_tag_protections = tag_protection_states.where({ enabled: true }).to_a
    return [] if enabled_tag_protections.empty?

    include_patterns = Set.new
    enabled_tag_protections.pluck(:pattern).sort_by(&:downcase).each do |pattern|
      if pattern == "*"
        include_patterns << "~ALL"
      else
        include_patterns << "refs/tags/#{pattern}"
      end
    end

    RepositoryRuleset.transaction do
      names = T.let([], T::Array[String])

      if is_auto_import
        single_ruleset = false
        names = find_unique_auto_import_names

        # Disable all imported tag protections within the transaction
        enabled_tag_protections.each do |tag_prot|
          tag_prot.enabled = false
          tag_prot.save!
        end
      else
        # Delete rulesets from previous manual import
        destroyed_count = rulesets.where(name: [SINGLE_RULESET_NAME, CREATE_RULESET_NAME, DELETE_RULESET_NAME])
          .destroy_all.count

        names = T.let(single_ruleset ? [SINGLE_RULESET_NAME] : [CREATE_RULESET_NAME, DELETE_RULESET_NAME], T::Array[String])
      end

      if single_ruleset
        ruleset = generate_ruleset(include_patterns, T.must(names[0]), actor, creation_rule: true, deletion_rule: true)
        ruleset.save!

        GitHub.dogstats.histogram("TagProtection.import.destroyed", destroyed_count, tags: ["single_ruleset:true"])
        GitHub.dogstats.histogram("TagProtection.import.pattern_count", include_patterns.count, tags: ["single_ruleset:true"])
        GitHub.dogstats.histogram("TagProtection.import.admin_roles_count", ruleset.bypass_actors.count, tags: ["single_ruleset:true"])

        [ruleset]
      else
        create_ruleset = generate_ruleset(include_patterns, T.must(names[0]), actor, creation_rule: true)
        create_ruleset.save!

        delete_ruleset = generate_ruleset(include_patterns, T.must(names[1]), actor, deletion_rule: true)
        delete_ruleset.save!

        if is_auto_import
          GitHub.dogstats.histogram("TagProtection.import.disabled", enabled_tag_protections.count, tags: ["single_ruleset:false", "is_auto_import:true"])
        else
          GitHub.dogstats.histogram("TagProtection.import.destroyed", destroyed_count, tags: ["single_ruleset:false", "is_auto_import:false"])
        end

        GitHub.dogstats.histogram("TagProtection.import.pattern_count", include_patterns.count, tags: ["single_ruleset:false", "is_auto_import:#{is_auto_import}"])
        GitHub.dogstats.histogram("TagProtection.import.delete_roles_count", delete_ruleset.bypass_actors.count, tags: ["single_ruleset:false", "is_auto_import:#{is_auto_import}"])
        GitHub.dogstats.histogram("TagProtection.import.create_roles_count", create_ruleset.bypass_actors.count, tags: ["single_ruleset:false", "is_auto_import:#{is_auto_import}"])

        [create_ruleset, delete_ruleset]
      end
    end
  end

  private

  # Create a new ruleset
  sig do params(
    include_patterns: T::Set[String],
    name: String,
    creator: T.untyped,
    creation_rule: T::Boolean,
    deletion_rule: T::Boolean)
    .returns(RepositoryRuleset)
  end
  def generate_ruleset(include_patterns, name, creator, creation_rule: false, deletion_rule: false)
    T.bind(self, Repository)

    ruleset = RepositoryRuleset.new(
      name: name,
      target: :tag,
      enforcement: :enabled,
      source: self,
      bypass_mode: owner&.organization? ? :org_bypass_any : :no_org_bypass,
    )

    ruleset.conditions << RepositoryRuleCondition.new(
      target: :ref_name,
      parameters: {
        include: include_patterns,
        exclude: [],
      },
    )

    ruleset.rule_configurations << RepositoryRuleConfiguration.new(rule_type: :creation, created_by_id: creator.id) if creation_rule
    ruleset.rule_configurations << RepositoryRuleConfiguration.new(rule_type: :update, created_by_id: creator.id,
      parameters: { "update_allows_fetch_and_merge": false })
    ruleset.rule_configurations << RepositoryRuleConfiguration.new(rule_type: :deletion, created_by_id: creator.id) if deletion_rule

    # "Admin" system role has create_tag and delete_tag FGPs
    ruleset.bypass_actors << RepositoryRulesetBypassActor.new(actor: Role.admin_role, bypass_mode: "any")

    if !deletion_rule && owner&.organization? && Role.maintain_role
      # "Maintain" system role has create_tag FGP, but not delete_tag.
      ruleset.bypass_actors << RepositoryRulesetBypassActor.new(actor: Role.maintain_role, bypass_mode: "any")
    end

    # Add custom roles if appropriate
    if owner&.organization? && owner&.custom_roles_supported?
      custom_roles = RepositoryRole.custom_roles_for_org(owner)

      custom_roles.each do |role|
        next if creation_rule && !role.permissions.any? { |perm| perm.action == "create_tag" }
        next if deletion_rule && !role.permissions.any? { |perm| perm.action == "delete_tag" }

        ruleset.bypass_actors << RepositoryRulesetBypassActor.new(actor: role, bypass_mode: "any")
      end
    end

    ruleset
  end

  AUTO_IMPORT_CREATE_RULESET_NAME = "Auto-imported tag create protections"
  AUTO_IMPORT_DELETE_RULESET_NAME = "Auto-imported tag delete protections"
  AUTO_IMPORT_RULESET_NAME_PATTERN = "Auto-imported tag % protections%"

  # Auto-migration of tag protections to rulesets will happen without human intervention. For this reason, we need to
  # generate unique names for the rulesets which are created.
  sig { returns(T::Array[String]) }
  def find_unique_auto_import_names
    T.bind(self, Repository)

    name_prefixes = T.let([AUTO_IMPORT_CREATE_RULESET_NAME, AUTO_IMPORT_DELETE_RULESET_NAME], T::Array[String])

    # The likelihood someone will have a ruleset with a conflicting name seems very low. But we should work in all cases.
    # Try names in this order:
    #   "Auto-imported tag create protections"
    #   "Auto-imported tag create protections (2)"
    #   "Auto-imported tag create protections (3)"
    #   ...etc...
    names_in_use = rulesets.where("name LIKE ?", AUTO_IMPORT_RULESET_NAME_PATTERN).pluck(:name).to_set

    names = name_prefixes
    index = 1

    while names_in_use.intersect?(names)
      index += 1
      names = name_prefixes.map { |prefix| "#{prefix} (#{index})" }
    end

    names
  end
end
