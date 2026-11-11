# typed: true
# frozen_string_literal: true

module Orgs::TeamSync::AnalyticsScrubberMethods
  extend ActiveSupport::Concern
  include AbstractController::Callbacks
  extend T::Helpers
  requires_ancestor { Orgs::Controller }

  included do
    before_action :mask_analytics_data
  end

  def mask_analytics_data
    url = if this_team
      "/orgs/<org-login>/teams/<team-name>/#{action_name}"
    else
      "/orgs/<org-login>/teams/#{action_name}"
    end
    override_analytics_location url
    strip_analytics_query_string
  end
end
