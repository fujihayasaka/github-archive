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
        cannot_delete_error.present?
      end

      def prevented_by_ruleset?
        cannot_delete_error == :prevented_by_ruleset
      end

      def name_of_ruleset_source_blocking_delete
        RulesEngine::RepositoryActionEvaluator.name_of_ruleset_source_blocking_delete(repository, current_user, dry_run: true)
      end

      memoize def cannot_delete_error
        repository.cannot_delete_repository_reason(current_user, dry_run: true)
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
