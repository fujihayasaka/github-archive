# typed: true
# frozen_string_literal: true

class SponsorsListingFeaturedItem < ApplicationRecord::Domain::Sponsors
  extend GitHub::Encoding
  force_utf8_encoding :description

  include GitHub::Relay::GlobalIdentification

  # NOTE: we want to move away from GraphQL for internal work and only use it to
  #       enhance our public API when needed. Adding this override simplifies
  #       the code when accessing this model.
  #
  #       See: https://github.com/github/future/blob/2b92a8a945eb38771b78d416bd8036578456128f/briefs/refocusing-graphql.md
  MAX_DESCRIPTION_LENGTH = 125
  MAX_DISPLAYED_FEATURED_USERS = 8
  FEATURED_USERS_LIMIT_PER_LISTING = 12
  FEATURED_REPOS_LIMIT_PER_LISTING = 6
  FEATURED_SPONSORSHIPS_LIMIT_PER_LISTING = 10

  enum :featureable_type, {
    User: 0,
    Repository: 1,
    Sponsorship: 2
  }, prefix: true


  belongs_to :sponsors_listing, required: true
  has_one :sponsorable, through: :sponsors_listing, disable_joins: true
  belongs_to :featureable, polymorphic: true, required: true

  validates :featureable_id, uniqueness: { scope: %i(featureable_type sponsors_listing_id) }
  validates :position, presence: true, numericality: { only_integer: true, greater_than: 0 }
  validates :description, length: { maximum: MAX_DESCRIPTION_LENGTH }, allow_blank: true

  # NOTE: every time I look at these two validations I get confused so let's add a comment. 🤓
  #       There can be featured users and repos up to whatever the limit constants say.
  #       So why are these `less_than`? The validation is performed against every individual item,
  #       there must be at least one empty slot available in order so the item can be added.
  #       That's why this is `less_than`. 😊
  validates :featured_users_count, numericality: { less_than: FEATURED_USERS_LIMIT_PER_LISTING }, if: :featureable_type_User?
  validates :featured_repos_count, numericality: { less_than: FEATURED_REPOS_LIMIT_PER_LISTING }, if: :featureable_type_Repository?
  validates :featured_sponsorships_count, numericality: { less_than: FEATURED_SPONSORSHIPS_LIMIT_PER_LISTING }, if: :featureable_type_Sponsorship?

  validate :sponsorable_is_org, if: :featureable_type_User?
  validate :featured_user_is_org_member, if: :featureable_type_User?
  validate :featured_repo_is_public, if: :featureable_type_Repository?
  validate :featured_repo_owned_or_contributed_by_sponsorable, if: :featureable_type_Repository?
  validate :featured_sponsors_is_paid_or_patreon, if: :featureable_type_Sponsorship?

  scope :for_users, -> { where(featureable_type: featureable_types[:User]) }
  scope :for_repos, -> { where(featureable_type: featureable_types[:Repository]) }
  scope :for_sponsorships, -> { where(featureable_type: featureable_types[:Sponsorship]) }
  scope :ordered_by_position, -> { order(:position) }

  # Public: Get a description of this featured item, either one that was explicitly set for it or falling back to
  # a description of the featured user or repository.
  #
  # Returns a String or nil.
  def async_description
    return Promise.resolve(description) if description.present?

    async_featureable.then do |featureable|
      if featureable_type_User?
        featureable.async_profile.then do |profile|
          profile&.bio
        end
      else
        featureable&.description
      end
    end
  end

  # Public: Get the featured user or repository, if it is still public.
  #
  # Returns a Promise<User|Repository|nil>.
  def async_featureable
    if featureable_type_User?
      super
    else
      super.then do |repo|
        repo if repo&.public?
      end
    end
  end

  private

  def featured_users_count
    return unless sponsors_listing

    query = T.must(sponsors_listing).featured_items.for_users
    query = query.where.not(id: self.id) if persisted?
    query.count
  end

  def featured_repos_count
    return unless sponsors_listing

    query = T.must(sponsors_listing).featured_items.for_repos
    query = query.where.not(id: self.id) if persisted?
    query.count
  end

  def featured_sponsorships_count
    return unless sponsors_listing

    query = T.must(sponsors_listing).featured_items.for_sponsorships
    query = query.where.not(id: self.id) if persisted?
    query.count
  end

  def sponsorable_is_org
    return unless sponsors_listing
    return if T.must(sponsors_listing).for_organization?

    errors.add(:sponsorable, "must be an organization")
  end

  def featured_user_is_org_member
    return unless sponsorable&.organization?

    org = T.cast(T.must(sponsorable), Organization)
    return if org.member?(featureable)

    errors.add(:featureable, "must be a member of this organization")
  end

  def featured_repo_owned_or_contributed_by_sponsorable
    return unless sponsors_listing
    return unless featureable && sponsorable

    return if featureable.owner == sponsorable
    return if T.must(sponsorable).user? && featureable.contributor?(sponsorable)

    user_type = T.must(sponsorable).type.downcase
    errors.add(:featureable, "must be owned by this #{user_type}")
  end

  def featured_repo_is_public
    return if featureable&.public?
    errors.add(:featureable, "must be public")
  end

  def featured_sponsors_is_paid_or_patreon
    return unless featureable

    return if featureable.paid || featureable.patreon?
    errors.add(:featureable, "must be a paid or patreon sponsorship")
  end
end
