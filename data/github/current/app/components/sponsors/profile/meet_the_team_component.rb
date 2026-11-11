# typed: true
# frozen_string_literal: true

class Sponsors::Profile::MeetTheTeamComponent < ApplicationComponent
  MAX_DISPLAYED_FEATURED_USERS = SponsorsListingFeaturedItem::MAX_DISPLAYED_FEATURED_USERS

  # featured_users - an Array or ActiveRecord::Relation of SponsorsListingFeaturedItem
  def initialize(featured_users:)
    @featured_users = featured_users
  end

  private

  memoize def featured_users
    GitHub::PrefillAssociations.prefill_associations(@featured_users, { featureable: :profile })
    @featured_users
  end

  def render?
    featured_users.present? && GitHub.sponsors_enabled?
  end
end
