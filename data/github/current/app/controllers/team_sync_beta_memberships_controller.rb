# typed: true
# frozen_string_literal: true

class TeamSyncBetaMembershipsController < ApplicationController
  before_action :dotcom_required

  # allowed for CAP skip as it is a simple redirect to help docs
  # Team-Sync beta signup controller is being disabled and should ultimately be removed
  skip_before_action :perform_conditional_access_checks # rubocop:todo GitHub/DoNotSkipCapBeforeAction

  depends_on_clusters ApplicationRecord::Mysql1,
    only: [:signup]

  def signup # rubocop:todo GitHub/UseRestfulActions
    redirect_to "#{GitHub.help_url}/articles/synchronizing-teams-between-your-identity-provider-and-github"
  end
end
