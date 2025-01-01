# rubocop:disable GitHub/FeatureManagement/NoFlipperFeatureUsage
# typed: true
# frozen_string_literal: true

require "chatops-controller"

class Chatops::FeaturesController < ApplicationController
  include ::Chatops::Controller

  # Opt-out of all conditional access and secondary authn checks, since these chatops are run by Hubbers
  # from Slack and the routes for triggering them are only accessible through our internal network
  skip_before_action :perform_conditional_access_checks # rubocop:disable GitHub/DoNotSkipCapBeforeAction
  skip_before_action :verify_authenticity_token

  chatops_namespace :features
  chatops_help "View information about feature flags"
  chatops_error_response "More information is available [in Sentry](https://sentry.io/organizations/github/issues/)"

  chatop :log, /log\s*?/, "log - Show the global log of recent feature flag changes." do
    phrase = "(action:feature.enable OR action:feature.disable) AND -data.gate_name:actor"
    if GitHub.driftwood_ade_queries_enabled?
      phrase = <<~KQL
        webevents
        | where action == "feature.enable" or action == "feature.disable"
        | where data.gate_name != "actor"
      KQL
    end
    entries = Audit::Driftwood::Query.new_stafftools_query(
      phrase: phrase,
      current_user: current_user,
      per_page: 20,
    ).execute
    log_lines = entries.map do |entry|
      "#{entry["actor"]} #{entry["data"]["operation"]}d #{get_linked_feature_name(entry)} for #{get_subject_label(entry)} at #{get_timestamp(entry)}"
    end

    chatop_send log_lines.join("\n")
  end

  private

  def get_subject_label(entry)
    FlipperFeature.get_subject_label(gate_name: entry["data"]["gate_name"].to_sym, subject: entry["data"]["subject"])
  end

  def get_timestamp(entry)
    Time.at(entry["created_at"] / 1000).in_time_zone(Time.zone).strftime("%Y-%m-%d %H:%M:%S")
  end

  def get_linked_feature_name(entry)
    "[#{entry["data"]["feature_name"]}](#{devtools_feature_flag_url(entry["data"]["feature_name"], host: GitHub.url)})"
  end
end

# rubocop:enable GitHub/FeatureManagement/NoFlipperFeatureUsage
