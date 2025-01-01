# typed: strict
# frozen_string_literal: true

class Stafftools::Copilot::QuotaResetComponent < ApplicationComponent
  sig { returns(Copilot::User) }
  attr_reader :copilot_user

  sig { returns(T.nilable(Copilot::LimitedUser)) }
  attr_reader :limited_user

  sig { returns(Copilot::Public::User) }
  attr_reader :public_user

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
    @public_user = T.let(Copilot::Public::User.new(copilot_user.user_object), Copilot::Public::User)
  end

  sig { returns(T::Boolean) }
  def render?
    @limited_user.present? || @copilot_user.consumptive_user?
  end

  sig { returns(T::Array[String]) }
  def allowed_free_features
    Copilot::Users::PremiumInteractions::ALLOWED_FREE_FEATURES
  end

  sig { returns(T::Array[String]) }
  def allowed_premium_features
    Copilot::Users::PremiumInteractions::ALLOWED_PREMIUM_FEATURES
  end

  private

  sig { params(feature: String).returns(T::Boolean) }
  def can_access_free_feature?(feature)
    limited_user&.present? && allowed_free_features.include?(feature) || false
  end

  sig { params(feature: String).returns(T::Boolean) }
  def can_access_premium_feature?(feature)
    copilot_user.consumptive_user? && allowed_premium_features.include?(feature)
  end

  sig { returns(String) }
  def data_dot_over_quota_events_link
    load_data_dot_over_quota_events_link(@copilot_user.user_object)
  end

  sig { returns(String) }
  def data_dot_chat_quota_events_link
    load_data_dot_quota_events_link(@copilot_user.user_object, "chat")
  end

  sig { returns(String) }
  def data_dot_completions_quota_events_link
    load_data_dot_quota_events_link(@copilot_user.user_object, "completions")
  end

  sig { returns(String) }
  def data_dot_premium_events_link
    load_data_dot_premium_events_link(@copilot_user.user_object)
  end

  sig { returns(String) }
  def data_dot_quota_processed_events_link
    load_data_dot_quota_processed_events_link(@copilot_user.user_object)
  end

  sig { returns(String) }
  def data_dot_billing_usage_link
    load_data_dot_billing_usage_link(@copilot_user.user_object)
  end

  sig { params(user: User, event_type: String).returns(String) }
  def load_data_dot_quota_events_link(user, event_type)
    case event_type
    when "chat"
      "https://data.githubapp.com/sql?query=select timestamp, is_premium, model_multiplier, github_copilot_units as quota_used, model, integration_id  from delta.hydro.copilot_v0_quota_event where copilot_tracking_id = '#{copilot_user.user_object.analytics_tracking_id}' and day >= '#{(Date.today - 7.days).to_date}' and feature = 'chat' order by timestamp desc limit 10"
    when "completions"
      "https://data.githubapp.com/sql?query=select timestamp, github_copilot_units as quota_used from delta.hydro.copilot_v0_quota_event where copilot_tracking_id = '#{copilot_user.user_object.analytics_tracking_id}' and day >= '#{(Date.today - 7.days).to_date}' and feature = 'completions' order by timestamp desc limit 10"
    else
      "https://data.githubapp.com/sql?query=select timestamp, is_premium, model_multiplier, github_copilot_units as quota_used, model, integration_id  from delta.hydro.copilot_v0_quota_event where copilot_tracking_id = '#{copilot_user.user_object.analytics_tracking_id}' and day >= '#{(Date.today - 7.days).to_date}' order by timestamp desc limit 10"
    end
  end

  sig { params(user: User).returns(String) }
  def load_data_dot_premium_events_link(user)
    "https://data.githubapp.com/sql?query=SELECT timestamp, user_tracking_id, premium_interactions_used, business_id, organization_id, owner_id as customer_id, model, overage, quota_request_type, integration_id, model_multiplier FROM delta.hydro.github_copilot_v3_copilot_premium_interaction WHERE user_tracking_id = '#{copilot_user.user_object.analytics_tracking_id}' AND DAY >= '#{(Date.today - 7.days).to_date}' ORDER BY timestamp DESC LIMIT 10"
  end

  sig { params(user: User).returns(String) }
  def load_data_dot_quota_processed_events_link(user)
    "https://data.githubapp.com/sql?query=select timestamp, feature, github_copilot_units, previous_quota_remaining, new_quota_remaining, monthly_quota_limit, quota_source from delta.hydro.github_copilot_v3_copilot_quota_processed where copilot_tracking_id = '#{copilot_user.user_object.analytics_tracking_id}' and day >= '#{(Date.today - 7.days).to_date}' order by timestamp desc limit 10"
  end

  sig { params(user: User).returns(String) }
  def load_data_dot_over_quota_events_link(user)
    "https://data.githubapp.com/sql?query=select timestamp, user.id, user.login, quota_source, quota_value, quota_details, quota_event_id from delta.hydro.github_copilot_v3_copilot_over_quota_event where user.login = '#{user.display_login}' and day >= '#{(Date.today - 7.days).to_date}' order by timestamp desc limit 10"
  end

  sig { params(user: User).returns(String) }
  def load_data_dot_billing_usage_link(user)
    "https://data.githubapp.com/sql?query=SELECT usage_uuid, timestamp, sku, quantity, usage_at, entity.customer_id AS customer_id, entity.organization_id as organization_id, entity.metadata as metadata FROM delta.hydro.billingplatform_v1_usage WHERE sku = 'copilot_premium_request' AND entity.actor_id = #{user.id} AND day >= '#{(Date.today - 7.days).to_date}' order by timestamp desc limit 10"
  end
end
