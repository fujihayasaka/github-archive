# typed: false
# frozen_string_literal: true

# Shared ViewModel methods for previewing diffs and commiting a change
# from the web interface.
#
# Depends on `#blob`, `#branch`, `#current_user`, `#forked_repo`,
# `#last_commit`, `#parent_repo`, `#path`, `#quick_pull`, `#target_branch`
module WebCommit
  module PreviewViewMethods
    include GitHub::Memoizer

    # Public: Had the current user forked the current repo?
    #
    # Returns Boolean
    def forked_repo?
      forked_repo.present?
    end

    # Public: Current oid of the pull request head branch
    #
    # Returns String oid (SHA1)
    def current_oid
      return @current_oid if defined?(@current_oid)

      @current_oid =
        if forked_repo?
          forked_repo.refs[branch]&.target_oid
        elsif parent_repo
          parent_repo.refs[branch]&.target_oid
        end
    end

    # Public: Should a quick-pull choice be offered in the web commit form?
    #
    # Renders two radio options if yes: one for direct edit and one for quick pull.
    # Otherwise renders single radio option for direct edit only.
    #
    # Returns Boolean
    def quick_pull_choice?
      return false unless logged_in?
      return false if forked_repo?
      !parent_repo.heads.empty?
    end

    # Public: Should the web commit form copy default to the quick pull message?
    #
    # Note: controls intial render values for the form heading and submit button
    # label. Button copy is then updated via Javascript when the user toggles
    # between direct edit and quick pull radio options.
    #
    # Returns Boolean
    def quick_pull?
      return @quick_pull_workflow if defined?(@quick_pull_workflow)
      @quick_pull_workflow = forked_repo? && logged_in? && forked_repo.pushable_by?(current_user)
    end

    # Public: Provide the correct copy for the web commit form - depends upon
    # if we are defaulting to direct edit or quick pull.
    #
    # Returns String
    def commit_button_copy
      if quick_pull? || !can_commit_to_branch?
        quick_pull_submit_message
      else
        direct_edit_submit_message
      end
    end

    def direct_edit_submit_message
      message = "Commit #{new_file? ? 'new file' : 'changes'}"
      message = "Sign off and #{message.downcase}" if parent_repo.dco_signoff_enabled?
      message
    end

    def quick_pull_submit_message
      message = "Propose #{new_file? ? 'new file' : 'changes'}"
      message = "Sign off and #{message.downcase}" if parent_repo.dco_signoff_enabled?
      message
    end

    # Public: Are these changes being made to a new file?
    #
    # Returns Boolean
    def new_file?
      blob.nil?
    end

    # Public: Indicate the active branch for the changes
    #
    # Returns String branch name
    def active_branch
      direct_edit_default? ? quick_pull_base : temp_branch
    end

    # Public: Build suggested branch for the changes
    #
    # Returns String branch name
    def temp_branch
      parent_repo.heads.temp_name(topic: "patch", prefix: current_user.display_login)
    end

    # Public: Determine correct branch name to prefill in new branch text input
    #
    # Returns String branch name
    def new_branch_field_value
      if target_branch.present?
        target_branch == active_branch ? temp_branch : target_branch
      else
        temp_branch
      end
    end

    # Public: Determine correct value to prefill for target branch hidden field
    #
    # Returns String
    def target_branch_field_value
      target_branch || active_branch
    end

    # Public: Determine correct value to prefill for quick pull hidden field
    #
    # Returns String
    def quick_pull_field_value
      quick_pull || quick_pull_default
    end

    # Public: Determine base for quick pull branch
    #
    # Returns String
    def quick_pull_base
      return @quick_pull_base if defined?(@quick_pull_base)

      parts = [branch]
      if forked_repo?
        parts.unshift parent_repo.owner.display_login
      end
      @quick_pull_base = parts.join(":").force_encoding("UTF-8").scrub!
    end

    # Public: Determine if the current user can commit to branch
    #
    # Returns Boolean
    def can_commit_to_branch?
      can_commit_to_branch_status != :blocked
    end

    memoize def can_commit_to_branch_status
      parent_repo.can_commit_to_branch_status(current_user, @branch)
    end

    # Public: Determine if the current page loaded will create a new branch or not
    #
    # Returns Boolean
    def will_create_branch?
      return true unless can_commit_to_branch?
      target_branch && target_branch != active_branch
    end

    private

    # Private: Should this edit default to direct edit workflow?
    #
    # Returns Boolean
    def direct_edit_default?
      return @direct_edit_default if defined?(@direct_edit_default)
      @direct_edit_default = !forked_repo? && can_commit_to_branch?
    end

    # Private: Mark the default quick-pull behavior
    #
    # Has value if not directly editing branch (see quick_pull_base)
    #
    # Returns String quick-pull base or nil
    def quick_pull_default
      return if direct_edit_default?
      quick_pull_base
    end
  end
end
