# typed: strict
# frozen_string_literal: true

module Businesses
  module SecurityCenter
    class OptionsController < AbstractSecurityCenterController
      extend T::Sig

      # Access
      before_action :security_center_required

      depends_on_clusters ApplicationRecord::Billing,
        ApplicationRecord::Collab,
        ApplicationRecord::Configurations,
        ApplicationRecord::Iam,
        ApplicationRecord::IamAbilities,
        ApplicationRecord::Mysql1,
        ApplicationRecord::Mysql2,
        ApplicationRecord::Mysql5,
        ApplicationRecord::NotificationsEntries,
        ApplicationRecord::Repositories,
        ApplicationRecord::Notify,
        only: [:index]

      depends_on_clusters ApplicationRecord::Copilot,
        only: [:index],
        optional: true

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
            options = suggestions.map do |sug|
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

            render ::SecurityCenter::SelectMenu::ListComponent.new(
              ::SecurityCenter::SelectMenu::ListComponent::Data.new(menu_id: menu_id, options: options)
            ), layout: false
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
          "orgs" => :org_suggestions,
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
        send(T.must(options_type_to_suggestions_method[options_type]))
      end

      sig { returns(T::Array[::SecurityCenter::Suggestions::Suggestion]) }
      memoize def org_suggestions
        Suggestions::Org.new(
          authorized_orgs:,
          limit:,
          selected_values:,
          value: params.fetch(:value, "")
        ).suggestions
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
          skip_limit: multiselect?,
          user: current_user,
          value: params.fetch(:value, "")
        ).suggestions
      end

      sig { returns(T::Array[::SecurityCenter::Suggestions::Suggestion]) }
      memoize def tool_suggestions
        security_features_parser = ::SecurityOverviewAnalytics::Dashboards::Overview::SecurityFeaturesParser.new(
          query: ::Search::Queries::SecurityCenter::QueryParser.new(""),
          scope: this_business,
          authorized_orgs:,
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

      instrument_method \
        :index,
        :allowed_repo_ids,
        :suggestions
    end
  end
end
