# typed: true
# frozen_string_literal: true

class Businesses::People::BulkActionToolbarComponent < ApplicationComponent
  attr_reader :business
  attr_reader :selected_user_ids
  attr_reader :show_remove
  attr_reader :selected_users
  attr_reader :all_organizations_team_users
  attr_reader :current_user
  attr_reader :business_teams_enabled

  def initialize(business:, selected_user_ids:, current_user:, show_remove: true)
    @business = business
    @selected_user_ids = selected_user_ids
    @current_user = current_user
    @show_remove = show_remove

    # Dialog content is loaded lazily via IncludeFragment (controller#show),
    # so the toolbar only needs user_ids for the button label.
    @selected_users = User.none
    @all_organizations_team_users = User.none
    @business_teams_enabled = false
  end

  memoize def improved_ui?
    FeatureFlag.vexi.enabled?("orgs_bulk_action_dialog_improvements", business, default: false)
  end
end
