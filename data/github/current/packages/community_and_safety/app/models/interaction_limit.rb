# typed: true
# frozen_string_literal: true

# InteractionLimit is used to limit user interactions in repositories, such as creating
# or editing issues and pull requests, or creating and editing comments on issues and
# pull requests.
#
# Limits can be applied in several ways, possibly in combination:
# - an admin can target a user to disallow that user from interacting with public repos
# - a user can target an individual repo or all repos owned by a specified user or org

class InteractionLimit < ApplicationRecord::Collab
  belongs_to :user
  include ::Repositories::BelongsToRepository
  belongs_to_repository_via_domain optional: true

  # Limits can be applied to a user or to a set of repositories.
  enum :target, { user: 0, repository: 1 }, prefix: "on"

  # Based on RepositoryInteractionAbility::INTERACTION_LIMITS
  enum :restriction, {
    sockpuppet_disallowed: 0,
    contributors_only: 1,
    collaborators_only: 2,
    user_disallowed: 3,
  }

  validates_presence_of :user_id, :expires_at
  validates_presence_of :restriction, if: -> { T.bind(self, InteractionLimit); on_repository? }

  scope :not_expired, -> { where("expires_at > ?", Time.zone.now) }
  scope :expired, -> { where("expires_at <= ?", Time.zone.now) }

  # Public: the symbol representing the restriction applied by this limit.
  #
  # Returns a Symbol.
  def restriction
    read_attribute(:restriction)&.to_sym
  end

  # Public: whether this limit is an overall limit that applies to all repositories owned by
  # the associated user, or a limit that applies to a specific repository.
  #
  # Returns a Boolean.
  def overall?
    on_repository? && repository_id.nil?
  end

  # Public: whether this limit applies to a specific repository, or to all repositories owned by
  # the associated user.
  #
  # Returns a Boolean.
  def local?
    on_repository? && repository_id.present?
  end

  # Public: the origin of the currently active limit.
  #
  # Returns a Symbol, one of :user, :organization, or :repository.
  def origin
    if overall?
      user&.organization? ? :organization : :user
    else
      :repository
    end
  end

  # Public: the expiry timestamp truncated to the nearest microsecond.
  #
  # Returns a DateTime.
  def expiry
    expires_at.to_datetime.change(nsec: 0)
  end
end
