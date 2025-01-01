# typed: strict
# frozen_string_literal: true

require "#{Rails.root}/config/environment"

# To learn more about transitions, checkout the documentation on The Hub:
# https://thehub.github.com/epd/engineering/products-and-services/dotcom/transitions/

module GitHub
  module Transitions
    class ConvertEnterpriseTagProtections < Base
      iterate_over :database_table, params: {
        model_class: Repository
      }

      sig { override.params(items: Iterators::Items).void }
      def process_batch(items)
        repo_ids = T.cast(items.keys, T::Array[Integer])

        all_tag_protections = RepositoryTagProtectionState.where(repository_id: repo_ids)
        return if all_tag_protections.empty?

        all_repos = Repository.where(id: repo_ids)

        log("Converting #{all_tag_protections.count} tag protections to rules #{"(dry run) " if dry_run?} repo IDs: #{all_repos.pluck(:id).join(", ")}")

        all_repos.each do |repo|
          tag_protections = all_tag_protections.filter { _1.repository_id == repo.id && _1.enabled }
          next if tag_protections.empty?

          # Find some appropriate owner to "own" the newly-created rulesets. Pick a non-disabled repo admin.
          ruleset_owner = T.cast(User.find(repo.admin_ids), T::Array[User]).find { |u| !u.disabled } || User.ghost

          unless dry_run?
            import_tag_protections_to_rulesets(repo, tag_protections, ruleset_owner)
          end
        rescue StandardError => ex
          log("Exception importing tag protections: #{ex.detailed_message(highlight: false)}")

          Failbot.report(ex,
            "gh.repo_id": repo.id,
            "gh.ruleset_owner": ruleset_owner.try(:display_login),
            "gh.dry_run": dry_run?,
          )
        end
      end

      # Public: Import all enabled tag protections to the ruleset infrastructure
      #
      # On success, returns an array of created persisted rulesets.
      sig do params(
        repo: Repository,
        tag_protections: T::Array[RepositoryTagProtectionState],
        ruleset_owner: T.untyped)
        .void
      end
      def import_tag_protections_to_rulesets(repo, tag_protections, ruleset_owner)
        include_patterns = Set.new
        tag_protections.map { _1.pattern }.sort_by(&:downcase).each do |pattern|
          if pattern == "*"
            include_patterns << "~ALL"
          else
            include_patterns << "refs/tags/#{pattern}"
          end
        end

        tag_protections.each { _1.enabled = false }

        creation_rule_name, deletion_rule_name = find_unique_auto_import_names(repo)
        create_ruleset = generate_ruleset(repo, include_patterns, creation_rule_name, ruleset_owner, creation_rule: true)
        delete_ruleset = generate_ruleset(repo, include_patterns, deletion_rule_name, ruleset_owner, deletion_rule: true)

        write_to(model_class: RepositoryTagProtectionState) do
          tag_protections.each { _1.save! }
        end

        # The instrumentation on ruleset models try to publish a bunch of Aqueduct things during creation. This all
        # fails during enterprise DB upgrade, because services required to publish are not running.
        Instrumentation.suppressing do
          write_to(model_class: RepositoryRuleset) do
            create_ruleset.save!
            delete_ruleset.save!
          end
        end

        log("Migrated #{tag_protections.count} tag protections in repo ID=#{repo.id}")
      end

      # Create a new ruleset
      sig do params(
        repo: Repository,
        include_patterns: T::Set[String],
        name: String,
        creator: T.untyped,
        creation_rule: T::Boolean,
        deletion_rule: T::Boolean)
        .returns(RepositoryRuleset)
      end
      def generate_ruleset(repo, include_patterns, name, creator, creation_rule: false, deletion_rule: false)
        ruleset = RepositoryRuleset.new(
          name: name,
          target: :tag,
          enforcement: :enabled,
          source: repo,
        )

        if repo.owner&.organization?
          ruleset.bypass_actors << OrganizationAdminBypassActor.new(bypass_mode: "any")
        end

        # Set conditions (protected tag patterns)
        ruleset.conditions << RepositoryRuleCondition.new(
          target: :ref_name,
          parameters: {
            include: include_patterns,
            exclude: [],
          },
        )

        # Restrict create / update / delete as appropriate
        ruleset.rule_configurations << RepositoryRuleConfiguration.new(rule_type: :creation, created_by_id: creator.id) if creation_rule
        ruleset.rule_configurations << RepositoryRuleConfiguration.new(rule_type: :update, created_by_id: creator.id,
          parameters: { "update_allows_fetch_and_merge": false })
        ruleset.rule_configurations << RepositoryRuleConfiguration.new(rule_type: :deletion, created_by_id: creator.id) if deletion_rule

        # "Admin" system role can bypass create or delete
        ruleset.bypass_actors << RepositoryRoleBypassActor.new(actor: Role.admin_role, bypass_mode: "any")

        # "Maintain" system role can bypass create but not delete
        if !deletion_rule && repo.owner&.organization? && Role.maintain_role
          ruleset.bypass_actors << RepositoryRoleBypassActor.new(actor: Role.maintain_role, bypass_mode: "any")
        end

        # Add custom roles as bypassers if appropriate
        if repo.owner&.organization? && repo.owner&.custom_roles_supported?
          custom_roles = RepositoryRole.custom_roles_for_org(repo.owner)

          custom_roles.each do |role|
            next if creation_rule && !role.permissions.any? { |perm| perm.action == "create_tag" }
            next if deletion_rule && !role.permissions.any? { |perm| perm.action == "delete_tag" }

            ruleset.bypass_actors << RepositoryRoleBypassActor.new(actor: role, bypass_mode: "any")
          end
        end

        # Find any bot installations with repo admin.write permission
        if repo.owner
          admin_bot_installations = T.must(repo.owner).integration_installations.user_installable
            .select { |installation| repo.resources.administration.writable_by?(installation) }

          admin_bot_installations.each do |installation|
            ruleset.bypass_actors << IntegrationBypassActor.new(actor: installation.integration, bypass_mode: "any")
          end
        end

        ruleset
      end

      AUTO_IMPORT_CREATE_RULESET_NAME = "Auto-imported tag create protections"
      AUTO_IMPORT_DELETE_RULESET_NAME = "Auto-imported tag delete protections"
      AUTO_IMPORT_RULESET_NAME_PATTERN = "Auto-imported tag % protections%"

      # Auto-migration of tag protections to rulesets will happen without human intervention. For this reason, we need to
      # generate unique names for the rulesets which are created.
      sig { params(repo: Repository).returns([String, String]) }
      def find_unique_auto_import_names(repo)
        # name_prefixes = [AUTO_IMPORT_CREATE_RULESET_NAME, AUTO_IMPORT_DELETE_RULESET_NAME]

        # The likelihood someone will have a ruleset with a conflicting name seems very low. But we should work in all cases.
        # Try names in this order:
        #   "Auto-imported tag create protections"
        #   "Auto-imported tag create protections (2)"
        #   "Auto-imported tag create protections (3)"
        #   ...etc...
        names_already_in_use = repo.rulesets.where("name LIKE ?", AUTO_IMPORT_RULESET_NAME_PATTERN).pluck(:name).to_set

        names = [AUTO_IMPORT_CREATE_RULESET_NAME, AUTO_IMPORT_DELETE_RULESET_NAME]
        index = 1

        while names_already_in_use.intersect?(names)
          index += 1
          names = [AUTO_IMPORT_CREATE_RULESET_NAME + " (#{index})", AUTO_IMPORT_DELETE_RULESET_NAME + " (#{index})"]
        end

        names
      end
    end
  end
end

# Run as a single process if this script is run directly
if $0 == __FILE__
  # See the transition arguments class for information about standard
  # arguments and their default values. If you require additional arguments,
  # pass them via `additional_arguments: %w(foo)` to the `parse` method.
  args = GitHub::Transitions::Arguments.parse(ARGV)

  GitHub::Transitions::ConvertEnterpriseTagProtections.new(args).run
end
