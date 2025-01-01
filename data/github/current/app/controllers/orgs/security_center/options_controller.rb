# typed: strict
# frozen_string_literal: true

module Orgs
  module SecurityCenter
    class OptionsController < AbstractSecurityCenterController

      before_action :organization_read_required
      before_action :security_center_required

      Suggestions = ::SecurityCenter::Suggestions::Orgs

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
          "repos" => :repo_suggestions,
          "teams" => :team_suggestions,
          "topics" => :topic_suggestions,
          "tools" => :tool_suggestions,
          "props" => :custom_property_suggestions,
          "dependabot.ecosystems" => :dependabot_ecosystem_suggestions,
          "dependabot.packages" => :dependabot_package_suggestions,
          "codeql.rules" => :codeql_rule_suggestions,
          "third-party.rules" => :third_party_rule_suggestions,
          "code-scanning.rules" => :code_scanning_rule_suggestions,
          "code-scanning.tools" => :code_scanning_tool_suggestions,
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

      sig { params(feature: T.nilable(String)).returns(T.nilable(T::Array[Integer])) }
      def allowed_repo_ids(feature: nil)
        # if the user can manage security products for the org, they can manage for all repos
        return nil if can_view_all_alerts?

        return allowed_repository_ids_by_feature_for_organization_members[feature]&.first if feature.present?

        allowed_repository_ids_by_feature_for_organization_members
          .map { |_feature, allowed_info| allowed_info }
          .flat_map { |allowed_repo_ids, _repo_limit_exceeded| allowed_repo_ids }
          .uniq
      end

      sig { returns(T::Array[::SecurityCenter::Suggestions::Suggestion]) }
      memoize def suggestions
        return [] if invalid_options_type?
        send(T.must(options_type_to_suggestions_method[options_type]))
      end

      sig { returns(T::Array[::SecurityCenter::Suggestions::Suggestion]) }
      memoize def custom_property_suggestions
        Suggestions::CustomProperty.new(
          allowed_repo_ids:,
          limit:,
          organization: this_organization,
          name: params.fetch(:name, ""),
          selected_values:,
          value: params.fetch(:value, "")
        ).suggestions
      end

      sig { returns(T::Array[::SecurityCenter::Suggestions::Suggestion]) }
      memoize def repo_suggestions
        Suggestions::Repo.new(
          organization: this_organization,
          user: current_user,
          user_session: user_session,
          allowed_repo_ids:,
          limit:,
          selected_values:,
          value: params.fetch(:value, "")
        ).suggestions
      end

      sig { returns(T::Array[::SecurityCenter::Suggestions::Suggestion]) }
      memoize def team_suggestions
        Suggestions::Team.new(
          limit:,
          organization: this_organization,
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
          scope: this_organization,
          allowed_code_scanning_repo_ids: allowed_repo_ids(feature: ::SecurityCenter::SecurityFeatures::CODE_SCANNING),
        )

        Suggestions::Tool.new(
          limit:,
          organization: this_organization,
          security_features_parser:,
          selected_values:,
          skip_limit: multiselect?,
          value: params.fetch(:value, "")
        ).suggestions
      end

      sig { returns(T::Array[::SecurityCenter::Suggestions::Suggestion]) }
      memoize def topic_suggestions
        Suggestions::Topic.new(
          allowed_repo_ids:,
          limit:,
          organization: this_organization,
          selected_values:,
          value: params.fetch(:value, "")
        ).suggestions
      end

      sig { returns(T::Array[::SecurityCenter::Suggestions::Suggestion]) }
      memoize def dependabot_ecosystem_suggestions
        Suggestions::Dependabot.new(
          organization: this_organization,
          user: current_user,
          user_session:,
          type: Suggestions::Dependabot::FilterType::Ecosystem,
          allowed_repo_ids: allowed_repo_ids(feature: ::SecurityCenter::SecurityFeatures::DEPENDABOT_ALERTS),
          limit:,
          selected_values:,
          value: params.fetch(:value, "")
        ).suggestions
      end

      sig { returns(T::Array[::SecurityCenter::Suggestions::Suggestion]) }
      memoize def dependabot_package_suggestions
        Suggestions::Dependabot.new(
          organization: this_organization,
          user: current_user,
          user_session:,
          type: Suggestions::Dependabot::FilterType::Package,
          allowed_repo_ids: allowed_repo_ids(feature: ::SecurityCenter::SecurityFeatures::DEPENDABOT_ALERTS),
          limit:,
          selected_values:,
          value: params.fetch(:value, "")
        ).suggestions
      end

      sig { returns(T::Array[::SecurityCenter::Suggestions::Suggestion]) }
      memoize def codeql_rule_suggestions
        Suggestions::CodeScanning.new(
          organization: this_organization,
          user: current_user,
          user_session:,
          type: Suggestions::CodeScanning::FilterType::CodeQLRule,
          allowed_repo_ids: allowed_repo_ids(feature: ::SecurityCenter::SecurityFeatures::CODE_SCANNING),
          limit:,
          selected_values:,
          value: params.fetch(:value, "")
        ).suggestions
      end

      sig { returns(T::Array[::SecurityCenter::Suggestions::Suggestion]) }
      memoize def third_party_rule_suggestions
        Suggestions::CodeScanning.new(
          organization: this_organization,
          user: current_user,
          user_session:,
          type: Suggestions::CodeScanning::FilterType::ThirdPartyRule,
          allowed_repo_ids: allowed_repo_ids(feature: ::SecurityCenter::SecurityFeatures::CODE_SCANNING),
          limit:,
          selected_values:,
          value: params.fetch(:value, "")
        ).suggestions
      end

      sig { returns(T::Array[::SecurityCenter::Suggestions::Suggestion]) }
      memoize def code_scanning_rule_suggestions
        Suggestions::CodeScanning.new(
          organization: this_organization,
          user: current_user,
          user_session:,
          type: Suggestions::CodeScanning::FilterType::AllRule,
          allowed_repo_ids: allowed_repo_ids(feature: ::SecurityCenter::SecurityFeatures::CODE_SCANNING),
          limit:,
          selected_values:,
          value: params.fetch(:value, "")
        ).suggestions
      end

      sig { returns(T::Array[::SecurityCenter::Suggestions::Suggestion]) }
      memoize def code_scanning_tool_suggestions
        Suggestions::CodeScanning.new(
          organization: this_organization,
          user: current_user,
          user_session:,
          type: Suggestions::CodeScanning::FilterType::Tool,
          allowed_repo_ids: allowed_repo_ids(feature: ::SecurityCenter::SecurityFeatures::CODE_SCANNING),
          limit:,
          selected_values:,
          value: params.fetch(:value, "")
        ).suggestions
      end

      sig { returns(T::Array[::SecurityCenter::Suggestions::Suggestion]) }
      memoize def secret_scanning_secret_type_suggestions
        Suggestions::SecretScanning.new(
          organization: this_organization,
          user: current_user,
          user_session:,
          type: Suggestions::SecretScanning::FilterType::SecretType,
          allowed_repo_ids: allowed_repo_ids(feature: ::SecurityCenter::SecurityFeatures::SECRET_SCANNING),
          limit:,
          selected_values:,
          value: params.fetch(:value, "")
        ).suggestions
      end

      sig { returns(T::Array[::SecurityCenter::Suggestions::Suggestion]) }
      memoize def secret_scanning_provider_suggestions
        Suggestions::SecretScanning.new(
          organization: this_organization,
          user: current_user,
          user_session:,
          type: Suggestions::SecretScanning::FilterType::Provider,
          allowed_repo_ids: allowed_repo_ids(feature: ::SecurityCenter::SecurityFeatures::SECRET_SCANNING),
          limit:,
          selected_values:,
          value: params.fetch(:value, "")
        ).suggestions
      end

      instrument_method \
        :index,
        :allowed_repo_ids,
        :suggestions

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
    end
  end
end
