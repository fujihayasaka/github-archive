# typed: true
# frozen_string_literal: true

# Public: Represents repositories and gists owned by the profile page owner, to be shown
# on the profile page. Will be either the pinned repositories and gists if the owner has
# any, or the "most popular" repositories otherwise.
#
# viewing_as_member - Defaults to false. Only applicable when viewing an organization profile;
# set to true when the viewer is viewing the members-only view of an organization, and
# returns the pinned items where internal_view = true
class ProfileItemShowcase
  def initialize(user:, viewer:, viewing_as_member: false)
    @user = user
    @viewer = viewer
    @viewing_as_member = viewing_as_member
  end

  # Public: Returns true if the profile owner has selected any repositories or gists to show on
  # their profile.
  def has_pinned_items?
    return @_has_pinned_items if defined?(@_has_pinned_items)

    @_has_pinned_items = pinned_items.any?
  end

  # Public: The items in the showcase, using the owner's pinned repositories and gists if
  # present, falling back to the most popular repositories based on stargazer count.
  #
  # Returns an Array of Repositories and/or Gists.
  def items
    if has_pinned_items?
      pinned_items
    else
      popular_repositories
    end
  end

  private

  def pinned_items
    @pinned_items ||= @user.pinned_items(viewer: @viewer, internal_view: @viewing_as_member)
  end

  def popular_repositories
    @user.public_repositories.active.
      filter_spam_and_disabled_for(@viewer).
      order("watcher_count DESC").
      order("created_at ASC")
  end
end
