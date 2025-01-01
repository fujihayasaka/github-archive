# typed: strict
# frozen_string_literal: true

module Sponsors::Dashboard::Overview::Statuses::ViewComponentMethods
  extend T::Sig
  extend T::Helpers

  requires_ancestor { ApplicationComponent }

  abstract!

  sig { overridable.params(sponsors_listing: SponsorsListing).void }
  def initialize(sponsors_listing:)
    @sponsors_listing = sponsors_listing
  end

  sig { returns(SponsorsListing) }
  attr_reader :sponsors_listing

  sig { abstract.returns(T::Boolean) }
  def render?; end

  sig { abstract.returns(T::Boolean) }
  def step_complete?; end

  protected

  sig { returns(GitHubSponsors::Types::Sponsorable) }
  def sponsorable
    T.must_because(sponsors_listing.sponsorable) { "sponsorable is required to render any of these components" }
  end
end
