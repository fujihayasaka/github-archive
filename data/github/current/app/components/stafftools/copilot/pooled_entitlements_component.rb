# typed: strict
# frozen_string_literal: true

class Stafftools::Copilot::PooledEntitlementsComponent < ApplicationComponent
  sig { returns(Copilot::User) }
  attr_reader :copilot_user

  sig { returns(Copilot::Public::User) }
  attr_reader :public_user

  sig do
    params(
      copilot_user: Copilot::User,
    ).void
  end
  def initialize(copilot_user)
    @copilot_user = copilot_user
    @public_user = T.let(Copilot::Public::User.for(copilot_user.user_object), Copilot::Public::User)
  end

  sig { returns(T::Boolean) }
  def render?
    @copilot_user.consumptive_user? && copilot_user.use_token_based_billing? && is_ce_cb_sku?
  end

  sig { returns(T::Boolean) }
  def is_ce_cb_sku?
    copilot_user.has_cb_access? || copilot_user.has_ce_access?
  end

  sig { returns(T::Boolean) }
  def has_budget?
    budget_info.present?
  end

  sig { returns(T::Boolean) }
  def is_budget_unlimited?
    T.must(budget_info)[:unlimited]
  end

  sig { returns(T.nilable(T::Hash[Symbol, T.untyped])) }
  def budget_info
    if copilot_user.use_token_based_billing?
      copilot_user.quota_snapshots["premium_interactions"]
    end
  end

  sig { returns([T::Boolean, T.nilable(String)]) }
  def display_pooled_entitlements_status
    tbb_result, err = copilot_user.calculate_use_token_based_billing
    [tbb_result, err]
  end

  sig { returns(String) }
  def stafftools_path
    copilot_provider = copilot_user.copilot_provider
    billable_entity =
    if copilot_provider.is_a?(Copilot::Organization)
      copilot_provider.organization_object.business.present? ? copilot_provider.organization_object.business : copilot_provider.organization_object
    elsif copilot_provider.is_a?(Copilot::Business)
      copilot_provider.business_object
    else
      copilot_provider
    end

    billable_entity.is_a?(Business) ? stafftools_enterprise_billing_path(billable_entity) : billing_stafftools_user_path(billable_entity)
  end

  private

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
  def load_data_dot_quota_processed_events_link(user)
    "https://data.githubapp.com/sql?query=select timestamp, feature, github_copilot_units, previous_quota_remaining, new_quota_remaining, monthly_quota_limit, quota_source from delta.hydro.github_copilot_v3_copilot_quota_processed where copilot_tracking_id = '#{copilot_user.user_object.analytics_tracking_id}' and day >= '#{(Date.today - 7.days).to_date}' order by timestamp desc limit 10"
  end

  sig { params(user: User).returns(String) }
  def load_data_dot_premium_events_link(user)
    "https://data.githubapp.com/sql?query=SELECT timestamp, user_tracking_id, premium_interactions_used, business_id, organization_id, owner_id as customer_id, model, overage, quota_request_type, integration_id, model_multiplier FROM delta.hydro.github_copilot_v3_copilot_premium_interaction WHERE user_tracking_id = '#{copilot_user.user_object.analytics_tracking_id}' AND DAY >= '#{(Date.today - 7.days).to_date}' ORDER BY timestamp DESC LIMIT 10"
  end

  sig { params(user: User).returns(String) }
  def load_data_dot_billing_usage_link(user)
    "https://data.githubapp.com/sql?query=SELECT usage_uuid, timestamp, sku, quantity, usage_at, entity.customer_id AS customer_id, entity.organization_id as organization_id, entity.metadata as metadata FROM delta.hydro.billingplatform_v1_usage WHERE sku = 'copilot_premium_request' AND entity.actor_id = #{user.id} AND day >= '#{(Date.today - 7.days).to_date}' order by timestamp desc limit 10"
  end

  sig { returns(String) }
  def data_dot_chat_quota_events_link
    load_data_dot_quota_events_link(@copilot_user.user_object, "chat")
  end

  sig { returns(String) }
  def data_dot_quota_processed_events_link
    load_data_dot_quota_processed_events_link(@copilot_user.user_object)
  end

  sig { returns(String) }
  def data_dot_premium_events_link
    load_data_dot_premium_events_link(@copilot_user.user_object)
  end

  sig { returns(String) }
  def data_dot_billing_usage_link
    load_data_dot_billing_usage_link(@copilot_user.user_object)
  end
end
