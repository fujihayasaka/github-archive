# typed: strict
# frozen_string_literal: true

class Stafftools::Sponsors::Members::ChildListings::FilterComponent < ApplicationComponent
  extend T::Sig

  sig do
    params(
      sponsorable_login: String,
      filter: T.any(
        T::Hash[Symbol, T.nilable(String)],
        ActionController::Parameters,
        { handle: T.nilable(String), state: T.nilable(String) }
      )
    ).void
  end
  def initialize(sponsorable_login:, filter: {})
    @sponsorable_login = sponsorable_login
    @filter = filter
  end

  private

  sig { returns String }
  attr_reader :sponsorable_login

  sig do
    returns T.any(
      T::Hash[Symbol, T.nilable(String)],
      ActionController::Parameters,
      { handle: T.nilable(String), state: T.nilable(String) }
    )
  end
  attr_reader :filter

  sig { returns T::Boolean }
  def render?
    @sponsorable_login.present? && GitHub.sponsors_enabled?
  end

  sig { returns T::Hash[Symbol, T.nilable(String)] }
  def listing_state_all_params
    all_params.except(:state)
  end

  sig { returns String }
  def search_by_handle_path
    stafftools_sponsors_member_child_listings_path(sponsorable_login, all_params.except(:handle))
  end

  sig { params(state: T.nilable(String)).returns(String) }
  def selected_listing_state(state)
    if listing_states.include?(state&.to_sym)
      T.must(state).humanize
    else
      "All"
    end
  end

  sig { returns T::Array[Symbol] }
  memoize def listing_states
    SponsorsListing.workflow_spec.state_names
  end

  sig { returns({ handle: T.nilable(String), state: T.nilable(String) }) }
  memoize def all_params
    { handle: filter[:handle], state: filter[:state] }.compact
  end
end
