# typed: false
# frozen_string_literal: true

module Branches
  class BranchView < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels
    include ActionView::Helpers::DateHelper
    include ActionView::Helpers::TextHelper
    include CompareHelper

    def initialize(*args)
      super(*args)

      unless @ref.is_a?(Git::Ref)
        raise TypeError, "expected BranchView#ref to be Ref, but was #{@ref.class}"
      end
    end

    # Public: Required Ref model.
    #
    # Returns Ref.
    attr_reader :ref

    attr_reader :commit, :user, :repository, :pull_request,
      :can_push, :current_user, :page_section, :is_being_renamed, :base_commit,
      :recent_errored_rename, :is_branch_protected

    delegate :name, :name_for_display, to: :ref

    def pull_request # rubocop:disable Lint/DuplicateMethods
      unless is_default?
        @pull_request unless @pull_request.try(:hide_from_user?, current_user)
      end
    end

    def pull_state
      @pull_state ||= if pull_request
        return :open if pull_request.open?
        return :merged if pull_request.merged?
        :closed
      else
        :none
      end
    end

    def pull_number
      pull_request.try(:number)
    end

    def is_default?
      ref.default_branch?
    end

    def delete_path
      urls.destroy_branch_path(repository.owner, repository, name)
    end

    def restore_path
      urls.create_branch_path(repository.owner, repository, name: name, branch: commit.oid)
    end

    # The ref is deleteable if it is not protected, is not the default branch, and is not currently being renamed.
    # This explicitly does not check whether the branch has open PRs, as that query is too expensive to run on
    # page load and caused performance issues. That check is now performed dynamically when the user attempts to
    # delete the branch.
    def can_delete?
      can_push && ref.deleteable?(deleter: current_user)
    end

    def can_rename?
      return false if is_being_renamed

      repository.ref_renameable_by?(current_user, ref: ref)
    end

    def would_be_deletable?
      return false unless can_push
      !is_default?
    end

    def not_deletable_reason
      if ref.protected? && ref.policy_evaluator&.blocks_deletes_for?(current_user)
        "You can't delete this protected branch."
      elsif is_being_renamed
        "You can't delete this branch because it is being renamed."
      else
        "You can't delete this branch."
      end
    end

    def compare_path
      if FeatureFlag.vexi.enabled?(:pull_request_templates, current_user, user, repository, default: false)
        urls.compare_path(repository, name)
      else
        urls.compare_path(repository, name, expand: can_push)
      end
    end

    def author_link
      if user
        data_attributes = helpers.hovercard_data_attributes_for_user(user)
        helpers.link_to user.display_login, urls.user_path(user), class: "Link--muted", data: data_attributes
      else
        commit.author_name
      end
    end
  end
end
