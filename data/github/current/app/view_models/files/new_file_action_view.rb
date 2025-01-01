# typed: true
# frozen_string_literal: true

module Files
  class NewFileActionView < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels
    include GitHub::ResilienceMixin
    attr_reader :repo, :tree_name

    def new_file_action_enabled?
      return false if repo.archived? || repo.locked_on_migration?
      return false unless logged_in? && on_a_branch?
      return false if current_user.must_verify_email?
      can_push? || can_fork? || has_fork?
    end

    def tooltip
      if new_file_action_enabled?
        if can_push?
          "Create a new file here"
        elsif has_fork?
          "Create a new file in your fork of this project"
        else
          "Fork this project and create a new file"
        end
      elsif !on_a_branch?
        "Select a branch to create a new file"
      elsif !logged_in?
        "You must be signed in to make or propose changes"
      elsif current_user.must_verify_email?
        "You need to verify your email address to make or propose changes"
      else
        "You must be able to fork a repository to propose changes"
      end
    end

    def on_a_branch?
      with_database_error_fallback(fallback: false) do
        repo.heads.exist?(tree_name)
      end
    end

    def can_push?
      logged_in? && repo.pushable_by?(current_user)
    end

    def has_fork?
      return false unless logged_in?
      return false if repo.archived? && current_user == repo.owner
      repo.network_has_fork_for?(current_user)
    end

    def can_fork?
      logged_in? && current_user.can_fork?(repo)
    end
  end
end
