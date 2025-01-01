# typed: true
# frozen_string_literal: true

class Sponsors::Businesses::SponsorshipsAllowedOrgRowComponent < ApplicationComponent
  extend T::Sig

  sig { params(org: Organization, business: Business).void }
  def initialize(org:, business:)
    @org = org
    @business = business
  end

  private

  attr_reader :org, :business
end
