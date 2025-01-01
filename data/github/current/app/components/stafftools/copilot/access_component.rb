# typed: strict
# frozen_string_literal: true

class Stafftools::Copilot::AccessComponent < ApplicationComponent

  sig { returns(Copilot::User) }
  attr_reader :copilot_user

  sig { returns(T::Boolean) }
  attr_reader :copilot_auth_allowed

  sig { returns(String) }
  attr_reader :copilot_auth_reason

  sig { returns(T::Boolean) }
  attr_reader :copilot_auth_no_snippy_allowed

  sig { returns(String) }
  attr_reader :copilot_auth_no_snippy_reason

  sig { returns(T.nilable(Copilot::AggregateUsageDetail)) }
  attr_reader :last_usage_detail

  sig { returns(T::Array[String]) }
  attr_reader :partner_orgs

  # Adding these individually makes the function signature too long but we do whatever we can to appease the linter
  sig do
    params(
      copilot_user: Copilot::User,
      copilot_auth_allowed: T::Boolean,
      copilot_auth_reason: String,
      copilot_auth_no_snippy_allowed: T::Boolean,
      copilot_auth_no_snippy_reason: String,
      last_usage_detail: T.nilable(Copilot::AggregateUsageDetail),
      partner_orgs: T::Array[String],
    ).void
  end
  def initialize(copilot_user, copilot_auth_allowed, copilot_auth_reason, copilot_auth_no_snippy_allowed, copilot_auth_no_snippy_reason, last_usage_detail, partner_orgs = [])
    @copilot_auth_allowed           = copilot_auth_allowed
    @copilot_auth_no_snippy_allowed = copilot_auth_no_snippy_allowed
    @copilot_auth_no_snippy_reason  = copilot_auth_no_snippy_reason
    @copilot_auth_reason            = copilot_auth_reason
    @copilot_user                   = copilot_user
    @last_usage_detail              = last_usage_detail
    @partner_orgs                   = partner_orgs
  end

  sig { returns(String) }
  def data_dot_token_generations_link
    load_data_dot_token_generations_link(@copilot_user.user_object)
  end


  sig { returns(String) }
  def kusto_details_link
    load_kusto_details_link(@copilot_user.user_object)
  end

  sig { returns(T.nilable(Copilot::AdministrativeBlock)) }
  def active_block
    Copilot::AdministrativeBlock.active.where(blockable: copilot_user).order("created_at DESC").first
  end

  sig { returns T.any(String, Integer) }
  memoize def copilot_settings_cache_date
    cache = JSON.parse(@copilot_user.user_object.settings.get(:copilot_policy_data)).deep_symbolize_keys
    if cache.empty?
      return "Not generated"
    end
    cache[:timestamp]
  end

  sig { returns String }
  memoize def copilot_settings_cache_json
    JSON.pretty_generate(JSON.parse(@copilot_user.user_object.settings.get(:copilot_policy_data)).deep_symbolize_keys)
  end


  private

  sig { params(user: User).returns(String) }
  def load_data_dot_token_generations_link(user)
    "https://data.githubapp.com/sql?query=select copilot_access_type, editor_plugin_version, editor_version, timestamp, request_context.country_name, request_context.user_agent, actor.spamurai_classification, actor.suspended, copilot_user_details.copilot_user_settings from hive_hydro.hydro.github_copilot_v0_copilot_token_generated where actor.display_login = '#{user.display_login}' and day >= '#{(Date.today - 7.days).to_date}' order by timestamp desc limit 10"
  end

  sig { params(user: User).returns(String) }
  def load_kusto_details_link(user)
    "https://dataexplorer.azure.com/dashboards/4d2b5936-cda4-4405-9621-2e061ec97ca9?p-_startTime=24hours&p-_endTime=now&p-tracking_id=v-#{user.analytics_tracking_id}"
  end
end
