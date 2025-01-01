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
            block_pattern_matching_workflows! if allows_specific_workflows_patterns? && actions_blocklist_enabled?
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
          allowed_patterns = if actions_blocklist_enabled?
            @policy_checkable_entity.highest_level_allowlist.allowed_action_patterns.allowed
          else
            @policy_checkable_entity.highest_level_allowlist.allowed_action_patterns
          end
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
          rules = []

          if allows_local_to_enterprise_workflows?
            rules << "within a repository that belongs to your Enterprise account"
          else
            rules << "within a repository owned by #{repo.owner.display_login}"
          end

          if allows_specific_workflows_patterns?
            rules << "matching the following: " + @policy_checkable_entity.highest_level_allowlist.allowed_action_patterns.pluck(:value).sort.join(", ")
          end

          error_message = "#{disallowed_workflows_to_sentence} #{"is".pluralize(disallowed_workflows.count)} not allowed to be used in #{repo.name_with_display_owner}."
          error_message = error_message + " Reusable workflows in this workflow must be: #{rules.to_sentence(two_words_connector: " or ", last_word_connector: ", or ")}."

          {
            is_execution_allowed: false,
            error_message: error_message.truncate(1_000),
          }
        end

        def disallowed_workflows_to_sentence
          return disallowed_workflows.to_sentence if disallowed_workflows.count <= MAX_DISALLOWED_WORKFLOWS_TO_DISPLAY

          not_displayed_workflows_count = disallowed_workflows.count - MAX_DISALLOWED_WORKFLOWS_TO_DISPLAY
          disallowed_workflows.first(MAX_DISALLOWED_WORKFLOWS_TO_DISPLAY).to_sentence(last_word_connector: ", ") + ", and #{not_displayed_workflows_count} other #{"workflow".pluralize(not_displayed_workflows_count)}"
        end

        def success_response
          {
            is_execution_allowed: true,
            error_message: nil,
          }
        end

        memoize def actions_blocklist_enabled?
          @policy_checkable_entity.feature_enabled?(:actions_blocklist)
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
