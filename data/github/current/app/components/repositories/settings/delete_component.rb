# typed: true
# frozen_string_literal: true

module Repositories
  module Settings
    class DeleteComponent < ApplicationComponent
      def initialize(repository:)
        @repository = repository
      end

      private

      attr_reader :repository

      def disable_button?
        cannot_delete_error.present? && !can_request_bypass?
      end

      def prevented_by_ruleset?
        cannot_delete_error == :prevented_by_ruleset
      end

      def name_of_ruleset_source_blocking_delete
        RulesEngine::RepositoryActionEvaluator.name_of_ruleset_source_blocking_delete(repository, current_user, persist_results: false)
      end

      def initial_stage
        1
      end

      sig { returns(T::Boolean) }
      def repo_policy_bypass_enabled?
        repository.repo_policy_bypass_enabled?
      end

      sig { returns(T::Boolean) }
      def can_request_bypass?
        repo_policy_bypass_enabled? && prevented_by_ruleset?
      end

      sig { returns(T.nilable(String)) }
      def existing_bypass_request_link
        return unless can_request_bypass?

        # See if there's an existing bypass request and redirect to it if found
        existing_rule_event = RuleEngine::EventActionRepositoryOperation.find_by(
          repository:,
          operation: :delete,
        )
        return unless existing_rule_event && existing_rule_event.rule_suite
        existing_request = RuleEngine::BypassDelegation.existing_ruleset_request(
          T.must(existing_rule_event.rule_suite),
          T.must(current_user),
          Exemptions::Evaluators::RepositoryPolicyRulesetBypass.request_type,
        )
        existing_request&.permalink
      end

      def form_path
        if can_request_bypass?
          repository_request_bypass_path(
            repository: repository.name,
            user_id: repository.owner_display_login,
            action_type: "delete",
          )
        else
          settings_delete_path(repository: repository.name, user_id: repository.owner_display_login)
        end
      end

      def form_method
        can_request_bypass? ? :post : :delete
      end

      sig { returns(String) }
      def dialog_title
        can_request_bypass? ? "Submit a request to delete #{repository.name_with_display_owner}" : "Delete #{repository.name_with_display_owner}"
      end

      sig { returns(T.nilable(String)) }
      def dialog_subtitle
        can_request_bypass? ? "Repository deletion is managed by #{name_of_ruleset_source_blocking_delete}. Submit a request to delete this repository." : nil
      end

      sig { returns(Symbol) }
      def show_button_theme
        can_request_bypass? ? :default : :danger
      end

      sig { returns(String) }
      def show_button_text
        can_request_bypass? ? "Submit request" : "Delete this repository"
      end

      memoize def cannot_delete_error
        repository.cannot_delete_repository_reason(current_user, persist_results: false)
      end

      def description
        case cannot_delete_error
        when :cant_delete_repos_on_this_appliance
          "Users cannot delete repositories on this appliance."
        when :members_cant_delete_repositories
          "Organization members cannot delete repositories."
        when :prevented_by_ruleset
          "Ruleset(s) are preventing this repository from being deleted."
        else
          default_description
        end
      end

      def default_description
        safe_join([
          "Once you delete a repository, there is no going back. Please be certain.",
          forks_warning,
        ].compact)
      end

      memoize def forks_warning
        return unless repository.private? && dependent_fork_count > 0

        [
          tag.br,
          "We will also ",
          content_tag(
            :strong,
            "delete #{'all ' if dependent_fork_count > 1}#{pluralize(number_with_delimiter(dependent_fork_count), 'fork')}",
            class: "yell",
          ),
          " since this is a private repository.",
        ]
      end

      memoize def dependent_fork_count
        repository.repository_and_dependents.size - 1
      end
    end
  end
end
