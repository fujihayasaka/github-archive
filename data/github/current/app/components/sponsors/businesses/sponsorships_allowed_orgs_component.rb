# typed: true
# frozen_string_literal: true

class Sponsors::Businesses::SponsorshipsAllowedOrgsComponent < ApplicationComponent
  extend T::Sig
  include GitHub::Memoizer

  sig { params(business: Business).void }
  def initialize(business:)
    @business = business
  end

  private

  attr_reader :business

  sig { returns(ActiveRecord::Relation) }
  memoize def sponsorships_allowed_orgs
    allowed_ids = business.sponsorships_allowed_orgs

    orgs = Organization.where(id: allowed_ids).by_login
    GitHub::PrefillAssociations.prefill_associations(orgs, :profile)
    orgs
  end
end
