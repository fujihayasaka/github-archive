# typed: strict
# frozen_string_literal: true

class Stafftools::Copilot::LimitedUserComponent < ApplicationComponent

  sig { returns(Copilot::User) }
  attr_reader :copilot_user

  sig { returns(T.nilable(Copilot::LimitedUser)) }
  attr_reader :limited_user

  # Adding these individually makes the function signature too long but we do whatever we can to appease the linter
  sig do
    params(
      copilot_user: Copilot::User,
      limited_user: T.nilable(Copilot::LimitedUser),
    ).void
  end
  def initialize(copilot_user, limited_user)
    @copilot_user = copilot_user
    @limited_user = limited_user
  end

  sig { returns(T::Boolean) }
  def render?
    limited_user.present?
  end


  sig { returns(String) }
  def data_dot_over_quota_events_link
    load_data_dot_over_quota_events_link(@copilot_user.user_object)
  end

  sig { returns(String) }
  def data_dot_quota_events_link
    load_data_dot_quota_events_link(@copilot_user.user_object)
  end

  sig { returns(String) }
  def data_dot_quota_processed_events_link
    load_data_dot_quota_processed_events_link(@copilot_user.user_object)
  end

  private

  sig { params(user: User).returns(String) }
  def load_data_dot_quota_events_link(user)
    "https://data.githubapp.com/sql?query=select timestamp, feature, github_copilot_units as quota_used, quota_source from delta.hydro.copilot_v0_quota_event where copilot_tracking_id = '#{copilot_user.user_object.analytics_tracking_id}' and day >= '#{(Date.today - 7.days).to_date}' order by timestamp desc limit 10"
  end

  sig { params(user: User).returns(String) }
  def load_data_dot_quota_processed_events_link(user)
    "https://data.githubapp.com/sql?query=select timestamp, feature, github_copilot_units, previous_quota_remaining, new_quota_remaining, monthly_quota_limit, quota_source from delta.hydro.github_copilot_v3_copilot_quota_processed where copilot_tracking_id = '#{copilot_user.user_object.analytics_tracking_id}' and day >= '#{(Date.today - 7.days).to_date}' order by timestamp desc limit 10"
  end

  sig { params(user: User).returns(String) }
  def load_data_dot_over_quota_events_link(user)
    "https://data.githubapp.com/sql?query=select timestamp, user.id, user.login, quota_source, quota_value, quota_details, quota_event_id from delta.hydro.github_copilot_v3_copilot_over_quota_event where user.login = '#{user.display_login}' and day >= '#{(Date.today - 7.days).to_date}' order by timestamp desc limit 10"
  end
end
