# typed: true
# frozen_string_literal: true

module Api::Internal::Twirp::Actions
  module Core
    module V1
      class CheckWorkflowsPolicy
        include GitHub::Memoizer

        attr_reader :repo, :allowed_workflows, :disallowed_workflows

        MAX_DISALLOWED_WORKFLOWS_TO_DISPLAY = 5

        def self.call(request)
          new(request).call
        rescue ActiveRecord::RecordNotFound => err
          Twirp::Error.not_found(err.message)
        end

        def initialize(request)
          database_id = Platform::Helpers::NodeIdentification.from_global_id(request.repository_id.global_id).last

          @repo = Repositories::Public.find_active!(database_id)
          @allowed_workflows = []
          @disallowed_workflows = request.workflows.uniq.map { |workflow| Workflow.new(workflow, repo.nwo) }

          # policy_checkable_entity is the entity where the policy check
          # should be performed. It can either be an org or a repo.
          # We want to ignore repo level policies and always depend on org
          # policies in case of required workflows.
          @policy_checkable_entity = if request.should_ignore_repo_policies
            repo.owner
          else
            repo
          end
        end

        # actions and workflows share the same configuration
        # for the historical reason, workflow permission is introduced later than action permission and that made method names follow actions
        def call
          return success_response if allows_all_workflows?

          allow_local_workflows!
          allow_local_to_enterprise_workflows! if allows_local_to_enterprise_workflows?

          unless allows_local_workflows_only? || owner_allows_local_workflows_only?
            allow_pattern_matching_workflows! if allows_specific_workflows_patterns?

            # must happen last as it may negate any of the previous policies
            block_pattern_matching_workflows! if allows_specific_workflows_patterns?
          end

          return error_response if disallowed_workflows.any?
          success_response
        end

        private

        def allows_specific_workflows_patterns?
          can_use_workflows_allowlist? && @policy_checkable_entity.allows_specific_actions_patterns?
        end

        def allows_all_workflows?
          @policy_checkable_entity.allows_all_actions?
        end

        def can_use_workflows_allowlist?
          @policy_checkable_entity.can_use_actions_allowlist?
        end

        def allows_local_workflows_only?
          @policy_checkable_entity.allows_local_actions_only?
        end

        def owner_allows_local_workflows_only?
          @policy_checkable_entity.owner_allows_local_actions_only?
        end

        # Local to the repo via directory path. Or has the same owner as this repo.
        def allow_local_workflows!
          return unless disallowed_workflows.any?

          local_workflows = disallowed_workflows.select do |workflow|
            workflow.local_to_repo? || workflow.owner_login == repo.owner.display_login.downcase
          end

          @disallowed_workflows = disallowed_workflows - local_workflows
          @allowed_workflows = allowed_workflows + local_workflows

          local_workflows
        end

        # Workflows that belong to any org within an Enterprise are allowed
        def allow_local_to_enterprise_workflows!
          return unless disallowed_workflows.any?

          org_logins = repo.owner.business.organizations.pluck(:display_login).map(&:downcase)

          local_to_enterprise = disallowed_workflows.select do |workflow|
            org_logins.include? workflow.owner_login
          end

          @disallowed_workflows = disallowed_workflows - local_to_enterprise
          @allowed_workflows = allowed_workflows + local_to_enterprise

          local_to_enterprise
        end

        def allow_pattern_matching_workflows!
          return unless disallowed_workflows.any?

          # for now, we are using the same pattern for actions and workflows
          allowed_patterns = @policy_checkable_entity.highest_level_allowlist.allowed_action_patterns.allowed
          allowed_regex = Regexp.union(allowed_patterns.map(&:regex))

          allowed_by_pattern = disallowed_workflows.select do |workflow|
            workflow.uses_string.match? allowed_regex
          end

          @disallowed_workflows = disallowed_workflows - allowed_by_pattern
          @allowed_workflows = allowed_workflows + allowed_by_pattern
        end

        def block_pattern_matching_workflows!
          return unless allowed_workflows.any?

          # for now, we are using the same pattern for actions and workflows
          blocked_patterns = @policy_checkable_entity.highest_level_allowlist.allowed_action_patterns.blocked
          blocked_regex = Regexp.union(blocked_patterns.map { |p| p.regex(trim_blocked_prefix: true) })

          blocked_by_pattern = allowed_workflows.select do |action|
            action.uses_string.match? blocked_regex
          end

          @disallowed_workflows = disallowed_workflows + blocked_by_pattern
          @allowed_workflows = allowed_workflows - blocked_by_pattern
        end

        def allows_local_to_enterprise_workflows?
          repo.owner.business.present?
        end

        def error_response
          or_rules = T::Array[String].new
          and_rules = T::Array[String].new

          allows_all_via_pattern = allows_specific_workflows_patterns? &&
            @policy_checkable_entity.highest_level_allowlist.allowed_action_patterns.allowed.any? { |p| p.value == "*" }

          # Build OR rules (satisfying any one of these will allow the workflow)
          if !allows_all_workflows? && !allows_all_via_pattern
            if allows_local_to_enterprise_workflows?
              or_rules << "from a repository owned by your enterprise"
            else
              or_rules << "from a repository owned by #{repo.owner.display_login}"
            end

            if allows_specific_workflows_patterns?
              allowed_patterns = @policy_checkable_entity.highest_level_allowlist.allowed_action_patterns.allowed.pluck(:value).sort

              if allowed_patterns.count == 1
                or_rules << "match the pattern: #{allowed_patterns.join(', ')}"
              elsif allowed_patterns.count > 1
                or_rules << "match one of the patterns: #{allowed_patterns.join(', ')}"
              end
            end
          end

          # Build AND rules (all workflows must also satisfy all of these)
          if allows_specific_workflows_patterns?
            # Remove ! prefix from blocked patterns for display
            blocked_patterns = @policy_checkable_entity.highest_level_allowlist.allowed_action_patterns.blocked.pluck(:value)
              .map { |pattern| pattern.delete_prefix(ActionsPolicy::AllowedActionPattern::BLOCKED_PREFIX) }.sort

            if blocked_patterns.count == 1
              and_rules << "not match the pattern: #{blocked_patterns.join(', ')}"
            elsif blocked_patterns.count > 1
              and_rules << "not match any of the patterns: #{blocked_patterns.join(', ')}"
            end
          end

          # Construct the error message
          workflow_word = "reusable workflow".pluralize(disallowed_workflows.count)
          error_message = "The #{workflow_word} #{disallowed_workflows_to_sentence} #{"is".pluralize(disallowed_workflows.count)} not allowed in #{repo.name_with_display_owner}"

          # Add the main "because" clause
          if or_rules.any? || and_rules.any?
            error_message += " because all reusable workflows must"

            if or_rules.any?
              error_message += " be #{or_rules.to_sentence(two_words_connector: ' or ', last_word_connector: ', or ')}"
            end

            if and_rules.any?
              be = and_rules.first&.start_with?("not match") ? "" : "be "
              if or_rules.count == 1 && and_rules.count == 1
                # If there's exactly 1 OR rule and 1 AND rule, combine the clauses with "and"
                error_message += " and #{and_rules.first}"
              elsif or_rules.count > 1
                # If there are multiple OR rules, use separate sentences for OR vs AND rules
                error_message += ". All reusable workflows must also #{be}#{and_rules.to_sentence}"
              else
                # If there are only AND rules, just show them
                error_message += " #{be}#{and_rules.to_sentence}"
              end
            end
          end

          error_message += "."

          emit_policy_enforced_metric(is_execution_allowed: false)

          {
            is_execution_allowed: false,
            error_message: error_message.truncate(1_000),
          }
        end

        def disallowed_workflows_to_sentence
          return disallowed_workflows.to_sentence if disallowed_workflows.count <= MAX_DISALLOWED_WORKFLOWS_TO_DISPLAY

          not_displayed_workflows_count = disallowed_workflows.count - MAX_DISALLOWED_WORKFLOWS_TO_DISPLAY
          disallowed_workflows.first(MAX_DISALLOWED_WORKFLOWS_TO_DISPLAY).to_sentence(last_word_connector: ", ") + ", and #{not_displayed_workflows_count} #{"other".pluralize(not_displayed_workflows_count)}"
        end

        def success_response
          emit_policy_enforced_metric(is_execution_allowed: true)

          {
            is_execution_allowed: true,
            error_message: nil,
          }
        end

        def emit_policy_enforced_metric(is_execution_allowed:)
          GitHub.dogstats.increment(
            "actions.allowed_actions_policy.enforced",
            tags: [
              "is_execution_allowed:#{is_execution_allowed}",
              "type:workflows",
              "policy:#{determine_policy_type}",
              "entity:#{@policy_checkable_entity.class.name}"
            ]
          )
        end

        def determine_policy_type
          return "all" if allows_all_workflows?
          return "local_only" if allows_local_workflows_only? || owner_allows_local_workflows_only?
          "specified"
        end

        class Workflow
          attr_reader :uses_string, :caller_nwo

          def initialize(uses_string, caller_nwo)
            @uses_string = uses_string.downcase
            @caller_nwo = caller_nwo.downcase
          end

          def owner_login
            return @owner_login if defined?(@owner_login)

            parts = uses_string.split("/")
            owner = parts[0]

            @owner_login = owner.downcase if owner.match? User::LOGIN_REGEX
          end

          def local_to_repo?
            # A local workflow in the repo will look like this: sameorg/samerepo/path/to/dir
            # We do not allow ./path/to/dir (omitted nwo) as the nwo should be resolved,
            # in order to handle callable workflows with nested calling
            uses_string.starts_with? caller_nwo
          end

          def to_s
            uses_string
          end
        end
      end
    end
  end
end
