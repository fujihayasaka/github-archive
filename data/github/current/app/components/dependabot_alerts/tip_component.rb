# typed: true
# frozen_string_literal: true

module DependabotAlerts
  class TipComponent < ApplicationComponent
    include ActionView::Helpers::UrlHelper
    include TipsHelper

    attr_reader :repo, :query_string, :selected_tip, :tips

    def initialize(repo:, tips: nil, query_string: nil)
      @repo = repo
      @query_string = query_string
      @tips = tips
    end

    def before_render
      # most tips need helpers, so we initialize them in before_render
      # but we also now allow the object to be created with tips
      # in which case we don't initialize any additional ones

      unless tips
        @tips = [
          "Add -has:patch to see alerts without an available fix.",
          "See auto-dismissed alerts with resolution:auto-dismissed.",
          "Use has:vulnerable-calls to see alerts with calls to vulnerable functions.",
          "Find alerts on your dev dependencies using scope:development.",
        ]
      end

      @selected_tip = select_tip
    end

    def select_tip
      render_link(tips.sample) do |components|
        tip_filter_pair = components.last
        qualifier = tip_filter_pair[0]
        value = tip_filter_pair[1]

        repository_alerts_path(
          user_id: @repo.owner,
          repository: @repo,
          q: update_query_string(qualifier: qualifier, value: value))
      end
    end

    def parsed_query_string
      Search::Queries::SecurityCenter::DependabotAlertsQuery.parse_and_normalize(query_string)
    end

    def update_query_string(qualifier:, value:)
      Search::Queries::SecurityCenter::DependabotAlertsQuery.add_or_replace(query_string, qualifier, value)
    end
  end
end
