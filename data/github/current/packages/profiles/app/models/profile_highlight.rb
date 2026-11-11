# typed: false
# frozen_string_literal: true

# Tracks the profile highlights (also referred to as badges) for a user
class ProfileHighlight < ApplicationRecord::Collab
  include GitHub::Memoizer
  include ::Users::BelongsToUser
  belongs_to_user_via_domain
  destroy_in_background_with :user
  has_many :profile_highlight_contributions

  enum :highlight_type, {
    nasa_2020: 0,
  }

  validates :highlight_type, uniqueness: {
    scope: :user,
  }

  scope :displayable, -> { where(eligible: true, hidden: false) }

  def displayable?
    return false if user.ghost?
    eligible? && !hidden?
  end

  # Public: The number of repositories for this profile highlight that
  # the user contributed to.
  #
  # Returns an Integer
  memoize def contribution_count
    repositories_scope.count
  end

  # Public: the most starred repositories for this profile highlight that
  # the user contributed to.
  #
  # Returns an Array
  def top_repositories(limit: 3)
    return @top_repositories if defined?(@top_repositories)

    @top_repositories =
      repositories_scope
        .order("#{Repository.stargazer_count_column} DESC")
        .first(limit)
  end

  # Private: queries for repositories for this profile highlight that
  # the user contributed to.
  #
  # Returns an ActiveRecord scope.
  memoize def repositories_scope
    repository_ids = profile_highlight_contributions.group_by_repository.pluck(:repository_id)

    Repository.where(id: repository_ids)
  end
end
