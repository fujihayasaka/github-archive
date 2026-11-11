# typed: true
# frozen_string_literal: true

class Sponsors::Dashboard::Profile::MeetTheTeamFormComponent < ApplicationComponent
  FORM_ID = "sponsors-featured-users-search-form"
  RESULTS_CONTAINER_ID = "sponsors-featured-users-search-container"

  def initialize(sponsors_listing:)
    @sponsors_listing = sponsors_listing
  end

  private

  attr_reader :sponsors_listing

  delegate :sponsorable_login, to: :sponsors_listing

  def render?
    sponsors_listing&.for_organization?
  end

  def form_id
    FORM_ID
  end

  def results_container_id
    RESULTS_CONTAINER_ID
  end
end
