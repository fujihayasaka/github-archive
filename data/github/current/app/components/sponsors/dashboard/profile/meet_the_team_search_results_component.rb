# typed: strict
# frozen_string_literal: true

class Sponsors::Dashboard::Profile::MeetTheTeamSearchResultsComponent < ApplicationComponent
  extend T::Sig

  RESULTS_DESCRIPTION_ID = "sponsors-meet-the-team-results-summary"
  RESULTS_ID = "sponsors-meet-the-team-results"

  sig do
    params(
      sponsorable: GitHubSponsors::Types::Sponsorable,
      other_members: T::Array[User],
      current_featured_users: T::Array[User],
      query: T.nilable(String),
    ).void
  end
  def initialize(sponsorable:, other_members: [], current_featured_users: [], query: nil)
    @sponsorable = sponsorable
    @other_members = other_members
    @current_featured_users = current_featured_users
    @query = query
  end

  private

  sig { returns GitHubSponsors::Types::Sponsorable }
  attr_reader :sponsorable

  sig { returns T.nilable(String) }
  attr_reader :query

  sig { returns T::Boolean }
  def render?
    GitHub.sponsors_enabled? && sponsorable.organization?
  end

  sig { returns T::Array[User] }
  memoize def other_members
    prefill_profiles
    @other_members
  end

  sig { returns T::Array[User] }
  memoize def current_featured_users
    prefill_profiles
    @current_featured_users
  end

  sig { void }
  def prefill_profiles
    GitHub::PrefillAssociations.prefill_associations(@other_members + @current_featured_users, :profile)
  end

  sig { returns T::Array[User] }
  memoize def first_members_list
    query.present? ? other_members : current_featured_users
  end

  sig { returns T::Array[User] }
  memoize def second_members_list
    query.present? ? current_featured_users : other_members
  end

  sig { returns String }
  def list_heading_id
    RESULTS_DESCRIPTION_ID
  end
end
