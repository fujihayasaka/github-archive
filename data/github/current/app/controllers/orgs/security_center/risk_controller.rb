# typed: true
# frozen_string_literal: true

module Orgs
  module SecurityCenter
    class RiskController < AbstractSecurityCenterController
      include ApplicationHelper
      include CustomPropertiesHelper

      javascript_bundle "security-center-filter-support"

      # Access
      before_action :organization_read_required
      before_action :security_center_required

      # Page cap
      skip_before_action :cap_pagination, unless: :robot?

      # Background process
      after_action :ensure_security_overview_analytics_reconciliation, only: [:index]
      after_action :trigger_security_overview_analytics_backfill, only: [:index]

      # Telemetry
      track_latency_slo "p99-ui-request", 2500, only: [:index]
      track_latency_slo "p50-ui-request", 750, only: [:index]
      track_availability_slo "ui-request", only: [:index]

      DEFAULT_QUERY = "archived:false"
      PER_PAGE = DEFAULT_PER_PAGE
      RiskQueryParser = ::Search::Queries::SecurityCenter::RiskQueryParser

      def index
        # For non-admins and non-security managers with partial org access, we need to show a warning if they can access more than the max number of repos we show.
        _, repo_limit_exceeded = allowed_repository_ids_for_organization_members

        data = log_timing(step: "build locals") do
          {
            current_user: current_user,
            organization: this_organization,
            backfill_in_progress: this_organization.trigger_security_center_reconciliation,
            visible_features: visible_features,
            query: query,
            default_query: DEFAULT_QUERY,
            hide_search_and_stats: hide_search_and_stats?,
            filter_input_suggestions: hide_search_and_stats? ? nil : filter_input_suggestions,
            filter_menus: hide_search_and_stats? ? [] : filter_menus,
            async_stats_src: security_center_risk_stats_path(query: query),
            list_menus: hide_search_and_stats? ? [] : list_menus,
            repository_list_data: repository_list_data,
            show_incomplete_data_warning: repo_limit_exceeded,
            render_export_button: GitHub.dotcom_request?,
            export_button_props: export_button_props,
            custom_properties: get_custom_properties_for_frontend(this_organization),
          }
        end

        log_timing(step: "render") do
          render "orgs/security_center/risk/index", locals: { data: }
        end
      end

      def stats # rubocop:todo GitHub/UseRestfulActions
        data = log_timing(step: "build locals") do
          { stats_summaries_data: }
        end

        log_timing(step: "render") do
          render "orgs/security_center/risk/stats_summaries", layout: false, locals: { data: }
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

      memoize def hide_search_and_stats?
        visible_features.empty? ||
          (!(can_view_all_alerts?) && allowed_repository_ids_for_organization_members.first.empty?) ||
          (query.empty? && repository_list_data.list_data.empty?)
      end

      memoize def query
        params[:query] || DEFAULT_QUERY
      end

      memoize def parser
        RiskQueryParser.new(query)
      end

      def query_string(new_query)
        qs = if new_query.blank?
          request&.query_parameters.except(:query, :page).to_query
        else
          request&.query_parameters.except(:page).merge(query: new_query).to_query
        end

        "?#{qs}"
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

      def filter_menus
        [
          ::SecurityCenter::SelectPanelComponent::Data.new(
            title: "Teams",
            header: "Filter by team",
            options_src: security_center_options_path({
              "options-type": "teams",
              qualifier: RiskQueryParser::TEAM,
              query:,
              multiselect: true
            }),
          )
        ]
      end

      def filter_input_suggestions
        visibilities = %w[public private]
        visibilities.insert(1, "internal") if this_organization.supports_internal_repositories?

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
            description: visibilities.join(", "),
            suggestions: visibilities.map { |v| { description: v.humanize, value: v } },
            negatable: true,
          },
          RiskQueryParser::REPOSITORY => {
            description: "repo-name",
            path: security_center_options_path("options-type": "repos"),
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
            path: security_center_options_path("options-type": "teams"),
            negatable: true,
          },
          RiskQueryParser::TOPIC => {
            description: "topic-name",
            path: security_center_options_path("options-type": "topics"),
            negatable: true,
          },
        }
      end

      sig { returns(T::Array[::SecurityCenter::Risk::StatsSummaryComponent::Data]) }
      def stats_summaries_data
        ::SecurityOverviewAnalytics::Risk::StatsQuery
          .for_organization(
            organization: this_organization,
            repo_ids_by_feature: allowed_repository_ids_by_feature,
            user: T.must(current_user),
            user_session: user_session,
            parser:,
          )
          .perform
          .items
      end

      sig { returns(::SecurityCenter::Risk::RepositoryListComponent::Data) }
      memoize def repository_list_data
        result = ::SecurityOverviewAnalytics::Risk::ListQuery
          .for_organization(
            organization: this_organization,
            repo_ids_by_feature: allowed_repository_ids_by_feature,
            user: T.must(current_user),
            user_session: user_session,
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
          async_counts_href: security_center_risk_counts_path(this_organization, { query: }),
        )
      end

      sig { returns(::SecurityOverviewAnalytics::Risk::CountsQuery::Result) }
      memoize def repository_list_counts
        ::SecurityOverviewAnalytics::Risk::CountsQuery
          .for_organization(
            organization: this_organization,
            repo_ids_by_feature: allowed_repository_ids_by_feature,
            user: T.must(current_user),
            user_session: user_session,
            parser:,
          )
          .perform(page_size: DEFAULT_PER_PAGE)
      end

      memoize def allowed_repository_ids_for_organization_members
        # if the user can manage security products for the org, they can manage for all repos
        return [nil, false] if can_view_all_alerts?


        repo_ids_from_features, repo_limit_exceeded_from_features = allowed_repository_ids_by_feature_for_organization_members
          .reduce(T.let([[], false], [T::Array[Integer], T::Boolean])) do |memo, (_, (repo_ids, repo_limit_exceeded))|
            memo[0] |= repo_ids
            memo[1] |= repo_limit_exceeded
            memo
          end

        GitHub.dogstats.distribution(
          "security_center.get_repos_for_user.repo_count",
          repo_ids_from_features.length,
          tags: datadog_tags + ["repo_limit_exceeded:#{repo_limit_exceeded_from_features}"]
        )

        [repo_ids_from_features, repo_limit_exceeded_from_features]
      end

      memoize def allowed_repository_ids_by_feature
        # if the user can manage security products for the org, they can manage for all repos
        return nil if can_view_all_alerts?

        limited_repo_ids, _ = allowed_repository_ids_for_organization_members
        allowed_repository_ids_by_feature_for_organization_members
          .reduce({}) do |memo, (feature_type, (repo_ids, _))|
            memo[feature_type] = (repo_ids & limited_repo_ids)
            memo
          end
          .with_indifferent_access
      end

      memoize def export_button_props
        {
          createExportUrl: security_center_risk_create_export_path(query: query),
          errorBannerId: "security-center-export-error-banner",
          successBannerId: "security-center-export-success-banner",
          startedBannerId: "security-center-export-started-banner",
          successDescription: "Your report is ready and the download has started. An email with the report has also been sent to you.",
          startedDescription: "Your report is being generated. You will receive an email when it's ready. Stay on this page to automatically download the report.",
        }
      end

      instrument_method \
        :allowed_repository_ids_by_feature,
        :allowed_repository_ids_for_organization_members,
        :index,
        :stats,
        :counts,
        :repository_list_data,
        :repository_list_counts,
        :stats_summaries_data

      depends_on_clusters \
        ApplicationRecord::Billing,
        ApplicationRecord::Collab,
        ApplicationRecord::Configurations,
        ApplicationRecord::Iam,
        ApplicationRecord::IamAbilities,
        ApplicationRecord::Mysql1,
        ApplicationRecord::Mysql2,
        ApplicationRecord::NotificationsEntries,
        ApplicationRecord::Notify,
        ApplicationRecord::Repositories,
        ApplicationRecord::SecurityOverviewAnalytics,
        only: [:index, :stats]

      depends_on_clusters \
        ApplicationRecord::Collab,
        ApplicationRecord::Configurations,
        ApplicationRecord::IamAbilities,
        ApplicationRecord::Mysql1,
        only: [:counts]

      depends_on_clusters \
        ApplicationRecord::Billing,
        ApplicationRecord::Iam,
        ApplicationRecord::Mysql2,
        ApplicationRecord::NotificationsEntries,
        ApplicationRecord::Notify,
        ApplicationRecord::Repositories,
        ApplicationRecord::SecurityOverviewAnalytics,
        only: [:counts],
        optional: true

      depends_on_clusters \
        ApplicationRecord::Copilot,
        ApplicationRecord::Mysql5,
        ApplicationRecord::SecurityOverviewAnalytics,
        only: [:index, :stats, :counts],
        optional: true
    end
  end
end
