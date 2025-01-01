# typed: true
# frozen_string_literal: true

module RulesetInsightsControllerMethods
  extend T::Helpers
  extend ActiveSupport::Concern

  include ReactHelper
  include Repos::RulesHelper

  requires_ancestor { ApplicationController }
  requires_ancestor { RulesetViewControllerMethods }

  CONTROLLER_METHODS = [:rule_insights, :rule_insights_actors]

  included do
    T.bind(self, T.class_of(ApplicationController))

    depends_on_clusters ApplicationRecord::Mysql1,
      ApplicationRecord::Repositories,
      ApplicationRecord::Mysql5,
      ApplicationRecord::NotificationsEntries,
      ApplicationRecord::Mysql2,
      ApplicationRecord::Collab,
      ApplicationRecord::IamAbilities,
      ApplicationRecord::Billing,
      ApplicationRecord::Configurations,
      ApplicationRecord::Copilot,
      ApplicationRecord::Spokes,
      ApplicationRecord::RepositoriesPushes,
      only: CONTROLLER_METHODS
  end

  abstract!

  sig { abstract.returns(Symbol) }
  protected def selected_insights_link; end

  def rule_insights # rubocop:todo GitHub/UseRestfulActions
    ref = current_source.is_a?(Repository) ? params[:ref] : nil
    repository = current_source.is_a?(Organization) ? params[:repository] : nil
    organization = current_source.is_a?(Business) ? params[:organization] : nil
    render_react_app(
      payload: rule_insights_payload(
        viewing_source: current_source,
        filter: {
          actor: params[:actor],
          time_period: params[:time_period],
          ruleset_name: params[:ruleset],
          rule_status: params[:rule_status],
          evaluate_status: params[:evaluate_status],
          ref:,
          repository:,
          organization:,
        },
        page: params[:page].to_i,
        ref_list_cache_key: try(:ref_list_cache_key),
        read_only: read_only?,
      ),
      app_payload_generator: -> { RulesEngine::ReactPayload.app_payload(current_source, current_user, supported_features, page_strings, is_stafftools: stafftools?) },
      title: "#{title_prefix}Insights · #{source_name}",
      page_data: {
        selected_link: selected_insights_link
      },
      layout: layout,
      ssr: true
    )
  end

  def rule_insights_actors # rubocop:todo GitHub/UseRestfulActions
    render json: filter_suggestions(RulesEngine::Suggestions.insights_users_for(current_source))
  end

end
