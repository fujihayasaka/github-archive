# typed: true
# frozen_string_literal: true

class Stafftools::Sponsors::Members::Activities::IndexComponent < ApplicationComponent
  # activities - an ordered and paginated ActiveRecord::Relation or Array of SponsorsActivity
  def initialize(sponsors_activities:, sponsorable_login:)
    @activities = sponsors_activities || []
    @sponsorable_login = sponsorable_login
  end

  private

  attr_reader :activities, :sponsorable_login

  def render?
    @sponsorable_login.present?
  end

  def total_entries
    activities.any? ? activities.total_entries : 0
  end

  def total_pages
    activities.any? ? activities.total_pages : 0
  end
end
