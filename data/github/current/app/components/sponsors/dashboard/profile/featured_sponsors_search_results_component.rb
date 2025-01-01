# typed: strict
# frozen_string_literal: true

class Sponsors::Dashboard::Profile::FeaturedSponsorsSearchResultsComponent < ApplicationComponent
  extend T::Sig

  RESULTS_DESCRIPTION_ID = "sponsors-featured-sponsors-summary"
  RESULTS_ID = "sponsors-featured-sponsors-results"

  sig do
    params(
      sponsorable: GitHubSponsors::Types::Sponsorable,
      other_sponsorships: T::Array[Sponsorship],
      current_featured_sponsorships: T::Array[Sponsorship],
      query: T.nilable(String),
    ).void
  end
  def initialize(sponsorable:, other_sponsorships: [], current_featured_sponsorships: [], query: nil)
    @sponsorable = sponsorable
    @other_sponsorships = other_sponsorships
    @current_featured_sponsorships = current_featured_sponsorships
    @query = query
  end

  private

  sig { returns GitHubSponsors::Types::Sponsorable }
  attr_reader :sponsorable

  sig { returns T.nilable(String) }
  attr_reader :query

  sig { returns T::Boolean }
  def render?
    GitHub.sponsors_enabled?
  end

  sig { returns T::Array[Sponsorship] }
  memoize def other_sponsorships
    prefill_profiles
    @other_sponsorships
  end

  sig { returns T::Array[Sponsorship] }
  memoize def current_featured_sponsorships
    prefill_profiles
    @current_featured_sponsorships
  end

  sig { void }
  def prefill_profiles
    GitHub::PrefillAssociations.prefill_associations(@other_sponsorships + @current_featured_sponsorships, [sponsor: :profile])
  end

  sig { returns T::Array[Sponsorship] }
  memoize def first_sponsorships_list
    query.present? ? other_sponsorships : current_featured_sponsorships
  end

  sig { returns T::Array[Sponsorship] }
  memoize def second_sponsorships_list
    query.present? ? current_featured_sponsorships : other_sponsorships
  end

  sig { returns String }
  def list_heading_id
    RESULTS_DESCRIPTION_ID
  end
end
