# typed: strict
# frozen_string_literal: true

class Sponsors::Dashboard::Profile::FeaturedSponsorComponent < ApplicationComponent
  sig { params(sponsorship: Sponsorship).void }
  def initialize(sponsorship:)
    @sponsorship = sponsorship
  end
end
