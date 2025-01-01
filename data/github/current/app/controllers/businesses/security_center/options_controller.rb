# typed: strict
# frozen_string_literal: true

module Businesses
  module SecurityCenter
    class OptionsController < AbstractSecurityCenterController

      # Access
      before_action :security_center_required

      Suggestions = ::SecurityCenter::Suggestions::Businesses

      sig { void }
      def index
        return head 400 if menu_id.blank? && request.format.html?
        return render_404 if invalid_options_type?

        respond_to do |format|
          format.json do
            json_suggestions = suggestions.map do |sug|
              { value: sug.value, display_name: sug.label, description: sug.description }.to_camelback_keys
            end

            render json: json_suggestions, layout: false
          end

          format.html do
            render ::SecurityCenter::SelectMenu::ListComponent.new(
              ::SecurityCenter::SelectMenu::ListComponent::Data.new(menu_id:, options: format_suggestions(suggestions))
            ), layout: false
          end

          format.html_fragment do
            render partial: "businesses/security_center/select_panel_results", formats: :html, locals: {
              options: format_suggestions(suggestions),
              menu_id:,
              label: options_type.capitalize
            }
          end
        end
      end

      private

      sig { returns(String) }
      memoize def options_type
        (params[:"options_type"] || "").downcase
      end

      sig { returns(T::Hash[String, Symbol]) }
      memoize def options_type_to_suggestions_method
        {
          "owners" => :owner_suggestions,
          "repos" => :repo_suggestions,
          "teams" => :team_suggestions,
          "topics" => :topic_suggestions,
          "tools" => :tool_suggestions,
          "dependabot.ecosystems" => :dependabot_ecosystem_suggestions,
          "dependabot.packages" => :dependabot_package_suggestions,
          "codeql.rules" => :codeql_rule_suggestions,
          "third-party.rules" => :third_party_rule_suggestions,
          "secret-scanning.secret-types" => :secret_scanning_secret_type_suggestions,
          "secret-scanning.providers" => :secret_scanning_provider_suggestions,
        }
      end

      sig { override.returns(T.nilable(Symbol)) }
      def authorized_orgs_actions
        fgps = Hash.new { raise ArgumentError.new("Unknown options type") }.merge(
          "orgs" => nil, # org membership
          "owners" => nil, # org membership
          "repos" => :read_repo,
          "teams" => nil, # org membership
          "topics" => :read_repo,
          "tools" => :read_code_scanning,
          "dependabot.ecosystems" => :view_dependabot_alerts,
          "dependabot.packages" => :view_dependabot_alerts,
          "codeql.rules" => :read_code_scanning,
          "third-party.rules" => :read_code_scanning,
          "secret-scanning.secret-types" => :view_secret_scanning_alerts,
          "secret-scanning.providers" => :view_secret_scanning_alerts,
        )[options_type]
      end

      sig { returns(T::Boolean) }
      memoize def invalid_options_type?
        !options_type_to_suggestions_method.key?(options_type)
      end

      sig { returns(T.nilable(Integer)) }
      memoize def limit
        params.fetch(:limit).to_i if params.key?(:limit)
      end

      sig { returns(String) }
      memoize def query
        params[:query] || ""
      end

      sig { returns(String) }
      memoize def qualifier
        params[:qualifier] || ""
      end

      sig { returns(T.nilable(String)) }
      memoize def menu_id
        params[:"menu_id"]
      end

      sig { returns(T::Boolean) }
      memoize def multiselect?
        params[:multiselect] == "true"
      end

      sig { returns(String) }
      memoize def query_key
        params[:query_parameter_key] || "query"
      end

      sig { returns(T::Array[String]) }
      memoize def selected_values
        params[:selected_values].try(:split, ",") || []
      end

      sig { returns(T::Array[::SecurityCenter::Suggestions::Suggestion]) }
      memoize def suggestions
        return [] if invalid_options_type?

        log_timing(
          step: "Get suggestions",
          "gh.security_center.authorized_org_count": authorized_orgs.size,
          "gh.security_center.authorized_org_ids": authorized_orgs.map(&:id)
        ) do
          send(T.must(options_type_to_suggestions_method[options_type]))
        end
      end

      sig { returns(T::Array[::SecurityCenter::Suggestions::Suggestion]) }
      memoize def owner_suggestions
        Suggestions::Owner.new(
          authorized_orgs:,
          limit:,
          selected_values:,
          value: params.fetch(:value, ""),
          business: this_business,
          user: current_user,
        ).suggestions
      end

      sig { returns(T::Array[::SecurityCenter::Suggestions::Suggestion]) }
      memoize def repo_suggestions
        Suggestions::Repo.new(
          authorized_orgs:,
          limit:,
          selected_values:,
          value: params.fetch(:value, ""),
          business: this_business,
          user: current_user,
        ).suggestions
      end

      sig { returns(T::Array[::SecurityCenter::Suggestions::Suggestion]) }
      memoize def team_suggestions
        Suggestions::Team.new(
          authorized_orgs:,
          limit:,
          selected_values:,
          skip_limit: limit.nil? && multiselect?,
          user: current_user,
          value: params[:value] || params[:q] || "" # We normally use `value`, but SelectPanel dropdowns use `q`, so check both
        ).suggestions
      end

      sig { returns(T::Array[::SecurityCenter::Suggestions::Suggestion]) }
      memoize def tool_suggestions
        security_features_parser = ::SecurityOverviewAnalytics::Dashboards::Overview::SecurityFeaturesParser.new(
          query: ::Search::Queries::SecurityCenter::QueryParser.new(""),
          scope: this_business,
          authorized_code_scanning_orgs: authorized_orgs,
        )

        Suggestions::Tool.new(
          limit:,
          security_features_parser:,
          selected_values:,
          skip_limit: multiselect?,
          value: params.fetch(:value, "")
        ).suggestions
      end

      sig { returns(T::Array[::SecurityCenter::Suggestions::Suggestion]) }
      memoize def topic_suggestions
        Suggestions::Topic.new(
          authorized_orgs:,
          limit:,
          selected_values:,
          value: params.fetch(:value, "")
        ).suggestions
      end

      sig { returns(T::Array[::SecurityCenter::Suggestions::Suggestion]) }
      memoize def dependabot_ecosystem_suggestions
        Suggestions::Dependabot.new(
          business: this_business,
          user: current_user,
          user_session:,
          type: Suggestions::Dependabot::FilterType::Ecosystem,
          authorized_orgs:,
          limit:,
          selected_values:,
          value: params.fetch(:value, "")
        ).suggestions
      end

      sig { returns(T::Array[::SecurityCenter::Suggestions::Suggestion]) }
      memoize def dependabot_package_suggestions
        Suggestions::Dependabot.new(
          business: this_business,
          user: current_user,
          user_session:,
          type: Suggestions::Dependabot::FilterType::Package,
          authorized_orgs:,
          limit:,
          selected_values:,
          value: params.fetch(:value, "")
        ).suggestions
      end

      sig { returns(T::Array[::SecurityCenter::Suggestions::Suggestion]) }
      memoize def codeql_rule_suggestions
        Suggestions::CodeScanning.new(
          business: this_business,
          user: current_user,
          user_session:,
          type: Suggestions::CodeScanning::FilterType::CodeQLRule,
          authorized_orgs:,
          limit:,
          selected_values:,
          value: params.fetch(:value, "")
        ).suggestions
      end

      sig { returns(T::Array[::SecurityCenter::Suggestions::Suggestion]) }
      memoize def third_party_rule_suggestions
        Suggestions::CodeScanning.new(
          business: this_business,
          user: current_user,
          user_session:,
          type: Suggestions::CodeScanning::FilterType::ThirdPartyRule,
          authorized_orgs:,
          limit:,
          selected_values:,
          value: params.fetch(:value, "")
        ).suggestions
      end

      sig { returns(T::Array[::SecurityCenter::Suggestions::Suggestion]) }
      memoize def secret_scanning_secret_type_suggestions
        Suggestions::SecretScanning.new(
          business: this_business,
          user: current_user,
          user_session:,
          type: Suggestions::SecretScanning::FilterType::SecretType,
          authorized_orgs:,
          limit:,
          selected_values:,
          value: params.fetch(:value, "")
        ).suggestions
      end

      sig { returns(T::Array[::SecurityCenter::Suggestions::Suggestion]) }
      memoize def secret_scanning_provider_suggestions
        Suggestions::SecretScanning.new(
          business: this_business,
          user: current_user,
          user_session:,
          type: Suggestions::SecretScanning::FilterType::Provider,
          authorized_orgs:,
          limit:,
          selected_values:,
          value: params.fetch(:value, "")
        ).suggestions
      end

      sig do
        params(
          suggestions: T::Array[::SecurityCenter::Suggestions::Suggestion]
        ).returns(T::Array[::SecurityCenter::SelectMenu::ListComponent::OptionData])
      end
      def format_suggestions(suggestions)
        log_timing(step: "Format suggestions") do
          suggestions.map do |sug|
            parser = Search::Queries::SecurityCenter::Base.new_parser([qualifier])

            href =
              if multiselect?
                "?#{query_key}=#{parser.add_or_remove(query, qualifier, sug.value)}"
              else
                "?#{query_key}=#{parser.add_or_replace(query, qualifier, sug.value)}"
              end

            ::SecurityCenter::SelectMenu::ListComponent::OptionData.new(
              text: sug.label || sug.value,
              href: href,
              description: sug.description,
              selected: parser.pair_exists?(query, qualifier, sug.value)
            )
          end
        end
      end

      depends_on_clusters \
        ApplicationRecord::Billing,
        ApplicationRecord::Collab,
        ApplicationRecord::Configurations,
        ApplicationRecord::Iam,
        ApplicationRecord::IamAbilities,
        ApplicationRecord::Mysql1,
        ApplicationRecord::Mysql2,
        ApplicationRecord::Mysql5,
        ApplicationRecord::NotificationsEntries,
        ApplicationRecord::Notify,
        ApplicationRecord::Repositories,
        ApplicationRecord::SecurityOverviewAnalytics,
        only: [:index]

      depends_on_clusters \
        ApplicationRecord::Copilot,
        only: [:index],
        optional: true

      instrument_method \
        :index,
        :authorized_orgs_for_action,
        :authorized_orgs_where_user_has_membership,
        :suggestions
    end
  end
end
