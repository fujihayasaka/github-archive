# typed: true
# frozen_string_literal: true

module Commits
  class AvatarStackComponent < ApplicationComponent
    # Needed for CommitHelper::MAX_DISPLAYED_COMMIT_AVATARS
    include CommitHelper

    # Needed for avatar_class_names
    include AvatarHelper

    LARGE_AVATAR_SIZE = 32

    attr_reader :size

    def initialize(commit:, size: GitHub::AvatarComponent::DEFAULT_SIZE)
      @commit = commit
      @size = size
    end

    # Returns a de-duped, filtered list of authors
    #
    # * Filters out users who should not be visible to the viewer (spammy/blocked)
    # * Includes the committer if different from the commit author and the
    #   commit was not made via the web interface
    #
    # Returns Array of Users
    def authors
      return @authors if defined?(@authors)

      @authors, @committer, @is_authored_by_committer = \
        Promise.all([
          Promise.all(commit.author_actors.map { |actor| actor.async_visible_actor(current_user) }),
          commit.committer_actor.async_visible_actor(current_user),
          commit.async_authored_by_committer?
        ]).sync

      @authors.uniq!
      @authors.compact!

      return @authors unless non_author_committer?

      @authors << committer
    end

    # Total number of authors for this commit
    #
    # Returns Integer
    memoize def author_count
      authors.size
    end

    # Is the committer not one of the commit authors?
    #
    # Returns Boolean
    memoize def non_author_committer?
      committer.present? && !is_authored_by_committer? && !commit.committed_via_web?
    end

    # Copy for the AvatarStack-body aria-label text which lists commit author
    # logins as a comma-separated list. Includes explanatory parenthetical when
    # committer is not one of the commit authors.
    #
    # Returns HTML safe String of comma-separated logins (ex. "bart, homer, lisa")
    def attribution_copy
      author_names = authors.map(&:display_login_legacy)
      title = html_safe_to_sentence(author_names)
      title += " (non-author committer)" if non_author_committer?

      title
    end

    # Classes for AvatarStack parent element, which control display and sizing modifiers
    # See https://primer.style/css/components/avatars#avatar-stack
    #
    # Returns String
    def avatar_stack_classes
      "AvatarStack flex-self-start #{avatar_stack_count_class(stack_count)} #{'AvatarStack--large' if size == LARGE_AVATAR_SIZE}"
    end

    # Count used to determine AvatarStack count modifier, ex. "AvatarStack--two"
    # See https://primer.style/css/components/avatars#avatar-stack
    #
    # Returns Integer
    def stack_count
      return author_count unless on_behalf_of
      author_count + 1
    end

    # Attributes for the avatar profile link tag
    #
    # author - A User, Organization, Business, or Bot
    #
    # Returns Hash
    def profile_link_options(author)
      options = {
        class: avatar_class_names(author),
        style: "width:#{size}px;height:#{size}px;",
        data: {
          "test-selector": "commits-avatar-stack-avatar-link"
        }
      }
      return options if GitHub.enterprise?
      return options unless author.is_a?(Bot)

      options.merge!({ url: author.marketplace_listing_or_app_path })
    end

    # Does the total author count for this commit exceed the maximum allowed?
    #
    # Returns Boolean
    def exceeds_max_displayed_commit_avatars?(index)
      stack_count > CommitHelper::MAX_DISPLAYED_COMMIT_AVATARS &&
        index == CommitHelper::MAX_DISPLAYED_COMMIT_AVATARS - 1
    end

    # Organization this commit was made on behalf of
    #
    # Returns Organization or nil if domain verification is disabled
    memoize def on_behalf_of
      commit.async_on_behalf_of.sync
    end

    # Copy for the tooltip message if the commit is made on behalf of an organization
    #
    # Returns String
    def on_behalf_of_tooltip_message
      "#{author_count > 1 ? "This commit was added" : "@#{authors.first.display_login} committed"} on behalf of #{on_behalf_of.name} (beta)"
    end

    private

    attr_reader :commit, :committer

    def is_authored_by_committer?
      @is_authored_by_committer
    end
  end
end
