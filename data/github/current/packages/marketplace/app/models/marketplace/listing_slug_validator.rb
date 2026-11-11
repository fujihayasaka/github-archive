# typed: true
# frozen_string_literal: true

class Marketplace::ListingSlugValidator < ActiveModel::Validator
  RESERVED_SLUGS = %w(action actions api admin category ci edit launch manage new pack preview purchases task tasks).freeze
  RESERVED_SLUG_PREFIXES = %w(agreements bundle free gist github marketing pipeline project pull-reminder sponsors).freeze

  def validate(listing)
    return unless listing.slug

    unless valid_slug?(listing)
      listing.errors.add(:name, "is unavailable. The listing name cannot be the same as an existing GitHub account unless it is your own user or organization name.")
    end
  end

  private

  def valid_slug?(listing)
    unless listing.owned_by_github?
      return false if RESERVED_SLUGS.include?(listing.slug)
      return false if listing.slug.start_with?(*RESERVED_SLUG_PREFIXES)
      return false if slug_belongs_to_other_user_or_org?(listing)
    end

    !Marketplace::Category.where(slug: listing.slug).exists?
  end

  def slug_belongs_to_other_user_or_org?(listing)
    return false if listing.owner && (listing.owner.login.downcase == listing.slug)

    User.where(login: listing.slug, type: "user").exists? || Organization.where(login: listing.slug).exists?
  end
end
