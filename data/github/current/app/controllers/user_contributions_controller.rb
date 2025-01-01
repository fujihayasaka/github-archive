# typed: true
# frozen_string_literal: true

class UserContributionsController < ApplicationController
  include UserContributionsHelper
  include Profiles::ContributionGraphDependency

  ACTIONS_EXCLUDED_FROM_SAML_CHECK = %w[show sample].freeze

  skip_before_action :perform_conditional_access_checks, unless: :cap_filter_user_contributions? # rubocop:disable GitHub/DoNotSkipCapBeforeAction

  before_action :ensure_user_exists

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Collab,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Repositories,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Ballast,
    ApplicationRecord::Configurations,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Copilot,
    ApplicationRecord::Iam,
    only: [:show]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Collab,
    only: [:sample]

  def show
    render(
      partial: "users/tabs/yearly_contributions",
      locals: {
        org: scoped_organization,
        calendar: graph_calendar,
        graph_collector: non_graphql_calendar_collector,
      },
    )
  end

  def sample # rubocop:todo GitHub/UseRestfulActions
    calendar = Contribution::CalendarSample.new
    respond_to do |format|
      format.html do
        render partial: "users/contributions",
               locals: { calendar: calendar, activity_overview_enabled: activity_overview_enabled? }
      end
    end
  end

  private

  def ensure_user_exists
    render_404 unless this_user && this_user.user?
  end

  def graph_calendar
    Contribution::Calendar.new(collector: non_graphql_calendar_collector)
  end

  def require_active_external_identity_session?
    if cap_filter_user_contributions?
      return false if ACTIONS_EXCLUDED_FROM_SAML_CHECK.include?(action_name)
      true
    end
  end

  def resource_for_conditional_access
    if cap_filter_user_contributions?
      return :no_target_for_conditional_access unless this_user.present?
      this_user
    end
  end

  memoize def cap_filter_user_contributions?
    this_user&.feature_flag_enabled?(:cap_filter_user_contributions, default: false)
  end
end
