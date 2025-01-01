# typed: strict
# frozen_string_literal: true

module Businesses
  module SecurityCenter
    class RiskController < Businesses::SecurityCenter::AbstractSecurityCenterController

      javascript_bundle "security-center-filter-support"

      # Page cap
      skip_before_action :cap_pagination, unless: :robot?

      # Access
      before_action :security_center_required

      # Background process
      after_action :ensure_security_overview_analytics_reconciliation, only: [:index]
      after_action :ensure_security_center_reconciliation, only: [:index]
      after_action :trigger_security_overview_analytics_backfill, only: [:index]

      track_latency_slo "p99-ui-request", 2500, only: [:index]
      track_latency_slo "p50-ui-request", 750, only: [:index]
      track_availability_slo "ui-request", only: [:index]

      DEFAULT_QUERY = "archived:false"
      RiskQueryParser = ::Search::Queries::SecurityCenter::RiskQueryParser

      sig { void }
      def index
        show_blankslate = visible_features.empty? ||
          (authorized_orgs.empty? && !can_see_personal_repos?) ||
          (query.empty? && repository_list_data.list_data.empty?)

        data = log_timing(step: "build locals") do
          {
            current_user: current_user,
            business: this_business,
            visible_features: visible_features,
            query: query,
            default_query: DEFAULT_QUERY,
            show_blankslate: show_blankslate,
            filter_input_suggestions: show_blankslate ? nil : filter_input_suggestions,
            filter_menus: show_blankslate ? [] : filter_menus,
            allow_owner_type_filtering: can_see_personal_repos?,
            list_menus: show_blankslate ? [] : list_menus,
            repository_list_data: repository_list_data,
            no_authorized_orgs: authorized_orgs.empty?,
            sso_payload: sso_payload,
            async_stats_src: security_center_risk_stats_enterprise_path(query: query),
            render_export_button: GitHub.dotcom_request?,
            export_button_props: export_button_props,
          }
        end

        log_timing(step: "render") do
          render "businesses/security_center/risk/index", locals: { data: }
        end
      end

      sig { void }
      def stats # rubocop:todo GitHub/UseRestfulActions
        data = log_timing(step: "build locals") do
          { stats_summaries_data: }
        end

        log_timing(step: "render") do
          render "businesses/security_center/risk/stats_summaries", layout: false, locals: { data: }
        end
      end

      sig { void }
      def counts # rubocop:todo GitHub/UseRestfulActions
        data = log_timing(step: "build locals") do
          repository_list_counts.serialize
        rescue ActiveRecord::ActiveRecordError
          # Graceful fallback in case of database error
          # Returning nil data means we won't show any counts
          nil
        end

        log_timing(step: "render") do
          render_camelback_json(json: { data: })
        end
      end

      private

      sig { override.returns(T::Array[Symbol]) }
      def authorized_orgs_actions
        [:read_code_scanning, :view_dependabot_alerts, :view_secret_scanning_alerts]
      end

      sig { returns(T::Hash[T.untyped, T.untyped]) }
      memoize def export_button_props
        {
          createExportUrl: security_center_risk_create_export_enterprise_path(query: query),
          errorBannerId: "security-center-export-error-banner",
          successBannerId: "security-center-export-success-banner",
          startedBannerId: "security-center-export-started-banner",
          startedDescription: "Your report is being generated. You will receive an email when it's ready. Stay on this page to automatically download the report.",
          successDescription: "Your report is ready and the download has started. An email with the report has also been sent to you.",
        }
      end

      sig { returns(String) }
      def query
        params[:query] || DEFAULT_QUERY
      end

      sig { returns(::Orgs::SecurityCenter::RiskController::RiskQueryParser) }
      memoize def parser
        ::Orgs::SecurityCenter::RiskController::RiskQueryParser.new(query)
      end

      sig { params(new_query: String).returns(String) }
      def query_string(new_query)
        qs = if new_query.blank?
          request&.query_parameters.except(:query, :page).to_query
        else
          request&.query_parameters.except(:page).merge(query: new_query).to_query
        end

        "?#{qs}"
      end

      sig { returns(T::Hash[Symbol, T::Hash[Symbol, T.untyped]]) }
      def filter_input_suggestions
        {
          RiskQueryParser::ARCHIVED => {
            description: "true, false",
            suggestions: [
              { value: "true" },
              { value: "false" },
            ],
            negatable: true,
          },
          RiskQueryParser::CODE_SCANNING => {
            description: "N, >N, >=N, <N, <=N, enabled, not-enabled",
            suggestions: [
              { description: "The feature is enabled", value: "enabled" },
              { description: "The feature is not enabled", value: "not-enabled" },
              { description: "Specific number of alerts", value: "N" },
              { description: "Number of alerts greater than N", value: ">N" },
              { description: "Number of alerts greater than or equal to N", value: ">=N" },
              { description: "Number of alerts less than N", value: "<N" },
              { description: "Number of alerts less or equal to N", value: "<=N" }
            ],
            negatable: true,
          },
          RiskQueryParser::DEPENDABOT_ALERTS => {
            description: "N, >N, >=N, <N, <=N, enabled, not-enabled",
            suggestions: [
              { description: "The feature is enabled", value: "enabled" },
              { description: "The feature is not enabled", value: "not-enabled" },
              { description: "Specific number of alerts", value: "N" },
              { description: "Number of alerts greater than N", value: ">N" },
              { description: "Number of alerts greater than or equal to N", value: ">=N" },
              { description: "Number of alerts less than N", value: "<N" },
              { description: "Number of alerts less or equal to N", value: "<=N" }
            ],
            negatable: true,
          },
          RiskQueryParser::VISIBILITY => {
            description: "public, internal, private",
            suggestions: %w[public internal private].map { |v| { description: v.humanize, value: v } },
            negatable: true,
          },
          RiskQueryParser::OWNER => {
            description: "owner-name",
            path: security_center_options_enterprise_path("options-type": "owners"),
            negatable: true,
          },
          RiskQueryParser::REPOSITORY => {
            description: "repo-name",
            path: security_center_options_enterprise_path("options-type": "repos"),
            negatable: true
          },
          RiskQueryParser::SECRET_SCANNING => {
            description: "N, >N, >=N, <N, <=N, enabled, not-enabled",
            suggestions: [
              { description: "The feature is enabled", value: "enabled" },
              { description: "The feature is not enabled", value: "not-enabled" },
              { description: "Specific number of alerts", value: "N" },
              { description: "Number of alerts greater than N", value: ">N" },
              { description: "Number of alerts greater than or equal to N", value: ">=N" },
              { description: "Number of alerts less than N", value: "<N" },
              { description: "Number of alerts less or equal to N", value: "<=N" }
            ],
            negatable: true,
          },
          RiskQueryParser::HAS_SEVERITY => {
            description: "critical, high, medium, moderate, low, informational",
            suggestions: [
              { description: "Critical", value: "critical" },
              { description: "High", value: "high" },
              { description: "Medium", value: "medium" },
              { description: "Moderate", value: "moderate" },
              { description: "Low", value: "low" },
              { description: "Informational", value: "informational" },
            ],
            negatable: true,
          },
          RiskQueryParser::SORT => {
            description: "last-updated, repos, feature-name",
            suggestions: [
              { description: "Last updated", value: "last-updated" },
              { description: "Repository name", value: "repos" },
              { description: "Dependabot", value: "dependabot" },
              { description: "Code Scanning", value: "code-scanning" },
              { description: "Secret Scanning", value: "secret-scanning" },
            ],
          },
          RiskQueryParser::TEAM => {
            description: "team-name",
            path: security_center_options_enterprise_path("options-type": "teams"),
            negatable: true,
          },
          RiskQueryParser::TOPIC => {
            description: "topic-name",
            path: security_center_options_enterprise_path("options-type": "topics"),
            negatable: true,
          },
        }
      end

      sig { returns(T::Array[T.any(::SecurityCenter::Coverage::SelectMenuComponent::Data, ::SecurityCenter::SelectPanelComponent::Data)]) }
      def filter_menus
        unless ::SecurityCenter::FeatureFlagHelper.use_new_team_dropdown?(current_user, this_business)
          return [] if Team.owned_by(authorized_orgs).size > TEAM_DROPDOWN_THRESHOLD
        end

        if ::SecurityCenter::FeatureFlagHelper.use_new_team_dropdown?(current_user, this_business)
          [
            ::SecurityCenter::SelectPanelComponent::Data.new(
              title: "Teams",
              header: "Filter by team",
              options_src: security_center_options_enterprise_path({
                "options-type": "teams",
                qualifier: RiskQueryParser::TEAM,
                query:,
                multiselect: true
              }),
            )
          ]
        else
          [
            ::SecurityCenter::Coverage::SelectMenuComponent::Data.new(
              name: "Teams",
              header: "Filter by team",
              filter: ::SecurityCenter::Coverage::SelectMenuComponent::Filter.new(placeholder: "Filter teams"),
              options_src: security_center_options_enterprise_path({
                "options-type": "teams",
                qualifier: RiskQueryParser::TEAM,
                query:,
                multiselect: true
              }),
              clear_option: (::SecurityCenter::Coverage::SelectMenuComponent::ClearOption.new(
                text: "Clear teams",
                href: query_string(parser.remove_qualifiers([RiskQueryParser::TEAM]))
              ) if parser.qualifier_exists?(RiskQueryParser::TEAM))
            )
          ]
        end
      end

      sig { returns(T::Array[::SecurityCenter::Risk::StatsSummaryComponent::Data]) }
      def stats_summaries_data
        ::SecurityOverviewAnalytics::Risk::StatsQuery
          .for_business(
            business: this_business,
            organizations: authorized_orgs_by_action,
            user: current_user,
            parser:,
          )
          .perform
          .items
      end

      sig { returns(::SecurityCenter::Risk::RepositoryListComponent::Data) }
      memoize def repository_list_data
        result = ::SecurityOverviewAnalytics::Risk::ListQuery
          .for_business(
            business: this_business,
            organizations: authorized_orgs_by_action,
            user: current_user,
            parser:,
          )
          .perform(page: current_page, page_size: DEFAULT_PER_PAGE)

        ::SecurityCenter::Risk::RepositoryListComponent::Data.new(
          active_href: query_string(parser.add_or_replace(RiskQueryParser::ARCHIVED, "false")),
          archived_href: query_string(parser.add_or_replace(RiskQueryParser::ARCHIVED, "true")),
          is_archived_selected: parser.pair_exists?(RiskQueryParser::ARCHIVED, "true"),
          is_nonarchived_selected: parser.pair_exists?(RiskQueryParser::ARCHIVED, "false"),
          list_data: result.items,
          current_page:,
          async_counts_href: security_center_risk_counts_enterprise_path(this_business, { query: }),
        )
      end

      sig { returns(::SecurityOverviewAnalytics::Risk::CountsQuery::Result) }
      memoize def repository_list_counts
        ::SecurityOverviewAnalytics::Risk::CountsQuery
          .for_business(
            business: this_business,
            organizations: authorized_orgs_by_action,
            user: current_user,
            parser:,
          )
          .perform(page_size: DEFAULT_PER_PAGE)
      end

      sig do
        returns(T::Array[T.any(
          ::SecurityCenter::Coverage::SelectMenuComponent::Data,
          ::SecurityCenter::ActionMenuComponent::Data,
        )])
      end
      def list_menus
        sort_option = parser.sort_by.then do |sort_option, _|
          ::SecurityOverviewAnalytics::Filters::FeatureStatusSummary::SortBy.sort_option_or_default(
            sort_option,
            valid_options: ::SecurityOverviewAnalytics::Filters::FeatureStatusSummary::SortBy::RISK_SORT_OPTIONS,
          )
        end

        sort_menu = ::SecurityCenter::ActionMenuComponent::Data.new(
          options: [
            ::SecurityCenter::ActionMenuComponent::Option.new(
              label: "Recently updated",
              href: query_string(parser.add_or_replace(RiskQueryParser::SORT, "last-updated")),
              selected: sort_option == :"last-updated",
            ),
            ::SecurityCenter::ActionMenuComponent::Option.new(
              label: "Repository name",
              href: query_string(parser.add_or_replace(RiskQueryParser::SORT, "repos")),
              selected: sort_option == :repos,
            ),
            ::SecurityCenter::ActionMenuComponent::Option.new(
              label: "Dependabot alerts",
              href: query_string(parser.add_or_replace(RiskQueryParser::SORT, "dependabot")),
              selected: sort_option == :dependabot,
            ),
            ::SecurityCenter::ActionMenuComponent::Option.new(
              label: "Code scanning alerts",
              href: query_string(parser.add_or_replace(RiskQueryParser::SORT, "code-scanning")),
              selected: sort_option == :"code-scanning",
            ),
            ::SecurityCenter::ActionMenuComponent::Option.new(
              label: "Secret scanning alerts",
              href: query_string(parser.add_or_replace(RiskQueryParser::SORT, "secret-scanning")),
              selected: sort_option == :"secret-scanning",
            ),
          ],
          button_prefix: "Sort by"
        )

        [sort_menu]
      end

      depends_on_clusters \
        ApplicationRecord::Collab,
        ApplicationRecord::Configurations,
        ApplicationRecord::IamAbilities,
        ApplicationRecord::Mysql1,
        ApplicationRecord::SecurityOverviewAnalytics,
        only: [:index, :stats, :counts]

      depends_on_clusters \
        ApplicationRecord::Billing,
        ApplicationRecord::Copilot,
        ApplicationRecord::Iam,
        ApplicationRecord::Mysql2,
        ApplicationRecord::NotificationsEntries,
        ApplicationRecord::Notify,
        ApplicationRecord::Repositories,
        only: [:index, :stats]

      depends_on_clusters \
        ApplicationRecord::Billing,
        ApplicationRecord::Copilot,
        ApplicationRecord::Iam,
        ApplicationRecord::Mysql2,
        ApplicationRecord::NotificationsEntries,
        ApplicationRecord::Notify,
        only: [:counts],
        optional: true

      depends_on_clusters \
        ApplicationRecord::Mysql5,
        ApplicationRecord::SecurityOverviewAnalytics,
        only: [:index, :stats, :counts],
        optional: true

      instrument_method \
        :index,
        :stats,
        :counts,
        :stats_summaries_data,
        :repository_list_data,
        :repository_list_counts,
        :filter_input_suggestions,
        :filter_menus,
        :list_menus
    end
  end
end
