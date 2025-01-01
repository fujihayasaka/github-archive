# typed: true
# frozen_string_literal: true

module Comments
  class CommentHeaderComponent < ApplicationComponent
    include CommentsHelper
    include DiffHelper
    include AvatarHelper
    include KeyboardShortcutsHelper
    include ResilienceHelper

    renders_one :avatar, ->(display: nil, size: 24, &block) do
      T.bind(self, CommentHeaderComponent)
      block&.call || GitHub::AvatarComponent.new(actor: author || User.ghost, display: display, size: size, mr: 2)
    end

    renders_one :badge

    attr_reader :comment, :repository, :classes, :action_text, :show_datestamp, :action_menu_path, :permalink_url

    def initialize(comment:, repository:, action_menu_path:, action_text: "commented", show_datestamp: false, classes: "", permalink_url: nil, dom_id: nil)
      @comment = comment
      @repository = repository
      @classes = classes
      @action_text = action_text
      @show_datestamp = show_datestamp
      @action_menu_path = action_menu_path
      @permalink_url = permalink_url
      @dom_id = dom_id
    end

    def menu_path
      return nil unless logged_in?

      action_menu_path
    end

    def permalink_id
      "#{dom_id}-permalink"
    end

    memoize def dom_id
      @dom_id || diff_comment_id(comment, "discussion")
    end

    # Is this comment minimized?
    #
    # Returns Boolean
    memoize def minimized?
      comment.minimized?
    end

    # Can the viewer react to this comment?
    # Includes as well the check for reactions_position feature flag as the method can be removed
    # once the FF is removed and there are no other dependencies on it.
    # Returns Boolean
    def can_react_on_top?
      return false if GitHub.flipper[:reactions_position].enabled?(current_user)
      return false unless logged_in?
      return false if minimized?
      comment.prelude_viewer_can_react(current_user)
    end

    # Should comments reported as abuse be identified as such in the comment header?
    #
    # Returns Boolean
    def show_abuse_reports?
      return false unless current_user&.site_admin?
      return false if comment.report_count.nil?
      comment.report_count > 0
    end

    # Should comments from spammy users be identified as such in the comment header?
    #
    # Returns Boolean
    def show_spam_reports?
      return false unless current_user&.site_admin?

      if comment.is_a?(Issue::Adapter::Base)
        comment.spammy?
      else
        comment.user_is_spammy(current_user)
      end
    end

    memoize def author
      comment.async_user.then do |user|
        next User.ghost if user.nil? || user.hide_from_user?(current_user)

        user
      end.sync
    end

    memoize def viewer_did_author?
      comment.user_id == current_user&.id
    end

    def display_commenter_full_name
      return if self.comment.class == GistComment # Since display_commenter_full_name is scoped to PR/Issue comments.
      !viewer_did_author? && can_see_commenter_full_name? && (display_commenter_full_name_enabled_for_org? || display_commenter_full_name_enabled_for_enterprise_instance?)
    end

    memoize def display_commenter_full_name_enabled_for_org?
      repository.organization&.display_commenter_full_name_setting_enabled?
    end

    memoize def display_commenter_full_name_enabled_for_enterprise_instance?
      if is_valid_enterprise_instance_to_show_commenter_full_name_setting? && repository.organization&.business.present?
        @display_commenter_full_name_enabled_for_enterprise_instance = repository.organization&.business&.display_commenter_full_name_setting_enabled?
      else
        @display_commenter_full_name_enabled_for_enterprise_instance = false
      end
    end

    def is_valid_enterprise_instance_to_show_commenter_full_name_setting?
      GitHub.single_business_environment?
    end

    memoize def can_see_commenter_full_name?
      repository.async_viewer_can_see_commenter_full_name?(current_user).sync
    end

    def datestamp
      comment.try(:created_at) || comment.submitted_at
    end

    # Retrieve first active sponsorship for the given comment's repo and author, if any
    #
    # Returns Sponsorship object or nil
    memoize def sponsorship
      return nil if comment.is_a?(CommitComment) || comment.is_a?(PlatformTypes::CommitComment)

      # If Issue or IssueComment. Comments in PullRequests are IssueComments
      if comment.is_a?(Issue::Adapter::Base) && comment.respond_to?(:author_to_repo_owner_sponsorship)
        return with_database_error_fallback(fallback: nil) { comment.author_to_repo_owner_sponsorship }
      end

      # If PullRequest or PullRequestReviewComment
      sponsorable = comment.try(:repository)&.owner
      return nil unless sponsorable

      sponsor = comment.user
      return nil unless sponsor

      with_database_error_fallback(fallback: nil) do
        # TODO: N+1 query if at least one PullRequestReviewComment is present
        # https://github.com/github/sponsors/issues/3944
        #
        # TODO: Must consider indirect sponsorships
        # For PullRequests: https://github.com/github/sponsors/issues/4211
        # For PullRequestReviewComments: https://github.com/github/sponsors/issues/3921
        Sponsorship.active.with_user_or_org_sponsorable(sponsorable).from_sponsor(sponsor).first
      end
    end

    # Was this comment authored by the dependabot bot?
    #
    # Returns Boolean
    def author_is_dependabot?
      return false unless author.is_a?(PlatformTypes::Bot) || author.is_a?(Bot)
      author.is_dependabot?
    end

    def author_is_copilot?
      comment.try(:copilot?)
    end

    def cpu_timer
      if helpers.respond_to?(:cpu_timer)
        helpers.cpu_timer
      end
    end

    def cpu_timer_track
      return cpu_timer.track { yield } if cpu_timer
      yield
    end
  end
end
