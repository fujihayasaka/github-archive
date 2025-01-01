# typed: true
# frozen_string_literal: true

class Sponsors::Activities::SelectPeriodComponent < ApplicationComponent
  VIEWER_ROLES = %i(sponsor sponsorable).freeze

  # period - the currently selected time period; choose from :day, :week, :month, :year, or :alltime
  # viewer_role - whose side the viewer represents, the sponsor's or the sponsorable's, either because they are
  #               the user themselves or because they belong to an org that is the sponsor or sponsorable; choose
  #               between :sponsor or :sponsorable
  # sponsorable_login - the String login of the User or Organization who was sponsored in the activities shown in the
  #                     time period this component represents; only necessary when viewer_role is :sponsorable
  # sponsor - the User or Organization who gets credit as the sponsor in the activities shown in the time period this
  #           component represents; only necessary when viewer_role is :sponsor
  def initialize(period:, viewer_role:, sponsorable_login: nil, sponsor: nil)
    @period = period
    @sponsorable_login = sponsorable_login
    @sponsor = sponsor
    @viewer_role = fetch_or_fallback(VIEWER_ROLES, viewer_role, nil)
  end

  private

  def render?
    return false if @viewer_role == :sponsorable && @sponsorable_login.nil?
    return false if @viewer_role == :sponsor && @sponsor.nil?
    @viewer_role.present?
  end

  def selected?(period_option)
    period_option == @period
  end

  def title(period_option)
    if period_option == :alltime
      "All-time"
    else
      "Past #{period_option}"
    end
  end

  def period_selection_url(period_option)
    if @viewer_role == :sponsorable
      sponsorable_dashboard_activities_path(@sponsorable_login, period: period_option)
    elsif @sponsor.organization?
      settings_org_sponsors_log_path(@sponsor, period: period_option)
    else
      settings_user_sponsors_log_path(period: period_option)
    end
  end
end
