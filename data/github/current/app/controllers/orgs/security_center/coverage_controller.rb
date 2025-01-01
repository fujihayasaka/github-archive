# typed: true
# frozen_string_literal: true

module Orgs
  module SecurityCenter
    class CoverageController < AbstractSecurityCenterController
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
      CoverageQueryParser = ::Search::Queries::SecurityCenter::CoverageQueryParser

      def index
        # For regular org members with partial repo access, we need to show a warning if they've exceeded the max number of repos we show.
        repo_ids, repo_limit_exceeded = adminable_repo_ids

        data = log_timing(step: "build locals") do
          {
            current_user: current_user,
            organization: this_organization,
            backfill_in_progress: this_organization.trigger_security_center_reconciliation,
            enablement_changes_in_progress: ::ResilientBlockedSettings.new(this_organization).any?,
            visible_features: visible_features,
            query: query,
            default_query: DEFAULT_QUERY,
            hide_search_and_stats: hide_search_and_stats?,
            filter_menus: hide_search_and_stats? ? [] : filter_menus,
            filter_input_suggestions: hide_search_and_stats? ? nil : filter_input_suggestions,
            async_stats_src: security_center_coverage_stats_path(query: query),
            repository_list_data: repository_list_data,
            list_menus: hide_search_and_stats? ? [] : list_menus,
            show_incomplete_data_warning: repo_limit_exceeded,
            render_export_button: GitHub.dotcom_request?,
            export_button_props: export_button_props,
            custom_properties: get_custom_properties_for_frontend(this_organization),
          }
        end

        log_timing(step: "render") do
          render "orgs/security_center/coverage/index", locals: { data: }
        end
      end

      sig { void }
      def stats # rubocop:todo GitHub/UseRestfulActions
        data = log_timing(step: "build locals") do
          { stats_summaries_data: }
        end

        log_timing(step: "render") do
          render "orgs/security_center/coverage/stats_summaries", layout: false, locals: { data: }
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

      # rubocop:todo GitHub/UseRestfulActions
      def feature_status
        default_response = [params[:text_color]&.to_sym || :default, params[:coverages_text] || "Needs setup"]
        repo = ::Repositories::Public.find_active(params[:repo_id]) if params[:repo_id].present?

        text_color, text = begin
          if repo && CodeScanning::AutoCodeql.new(repo).enabling?
            [params[:text_color]&.to_sym || :default, "Updating..."]
          else
            # Return defaults in case a param is missing so the user doesn't see a forever spinner
            default_response
          end
        rescue => e # rubocop:disable Lint/GenericRescue
          Failbot.report(e)
          default_response
        end

        render(
          partial: "orgs/security_center/coverage/security_settings/repository_coverages_component_text",
          locals: { coverages_text: text, text_color: text_color },
          layout: false
        )
      end

      private

      memoize def hide_search_and_stats?
        visible_features.empty? ||
          (!can_view_all_alerts? && adminable_repo_ids.first.blank?) ||
          (query.empty? && repository_list_data.list_data.empty?)
      end

      memoize def query
        params[:query] || DEFAULT_QUERY
      end

      memoize def parser
        CoverageQueryParser.new(query)
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
            valid_options: ::SecurityOverviewAnalytics::Filters::FeatureStatusSummary::SortBy::COVERAGE_SORT_OPTIONS,
          )
        end

        sort_menu = ::SecurityCenter::ActionMenuComponent::Data.new(
          options: [
            ::SecurityCenter::ActionMenuComponent::Option.new(
              label: "Recently updated",
              href: query_string(parser.add_or_replace(CoverageQueryParser::SORT, "last-updated")),
              selected: sort_option == :"last-updated",
            ),
            ::SecurityCenter::ActionMenuComponent::Option.new(
              label: "Repository name",
              href: query_string(parser.add_or_replace(CoverageQueryParser::SORT, "repos")),
              selected: sort_option == :repos,
            ),
          ],
          button_prefix: "Sort by"
        )

        [sort_menu]
      end

      def filter_menus
        return [] if this_organization.teams.size > TEAM_DROPDOWN_THRESHOLD

        [
          ::SecurityCenter::Coverage::SelectMenuComponent::Data.new(
            name: "Teams",
            header: "Filter by team",
            filter: ::SecurityCenter::Coverage::SelectMenuComponent::Filter.new(placeholder: "Filter teams"),
            options_src: security_center_options_path(
              "options-type": "teams",
              qualifier: CoverageQueryParser::TEAM,
              query: query,
              multiselect: true,
            ),
            clear_option: (::SecurityCenter::Coverage::SelectMenuComponent::ClearOption.new(
              text: "Clear teams",
              href: query_string(parser.remove_qualifiers([CoverageQueryParser::TEAM])),
            ) if parser.qualifier_exists?(CoverageQueryParser::TEAM)),
          ),
        ]
      end

      def filter_input_suggestions
        visibilities = %w[public private]
        visibilities.insert(1, "internal") if this_organization.supports_internal_repositories?

        filter_input_suggestions = {
          CoverageQueryParser::ARCHIVED => {
            description: "true, false",
            suggestions: [
              { value: "true" },
              { value: "false" },
            ],
            negatable: true,
          },
          CoverageQueryParser::CODE_SCANNING => {
            description: "enabled, not-enabled",
            suggestions: [
              { description: "The feature is enabled", value: "enabled" },
              { description: "The feature is not enabled", value: "not-enabled" }
            ],
            negatable: true,
          },
          CoverageQueryParser::CODE_SCANNING_DEFAULT_SETUP => {
            description: "enabled, eligible, not-eligible",
            suggestions: [
              { description: "The feature is enabled", value: "enabled" },
              { description: "The feature is eligible to be enabled", value: "eligible" },
              { description: "The feature is not eligible to be enabled", value: "not-eligible" },
            ],
            negatable: true,
          },
          CoverageQueryParser::CODE_SCANNING_PR_ALERTS => {
            description: "enabled, not-enabled",
            suggestions: [
              { description: "The feature is enabled", value: "enabled" },
              { description: "The feature is not enabled", value: "not-enabled" }
            ],
            negatable: true,
          },
          CoverageQueryParser::DEPENDABOT_ALERTS => {
            description: "enabled, not-enabled",
            suggestions: [
              { description: "The feature is enabled", value: "enabled" },
              { description: "The feature is not enabled", value: "not-enabled" }
            ],
            negatable: true,
          },
          CoverageQueryParser::DEPENDABOT_SECURITY_UPDATES => {
            description: "enabled, not-enabled",
            suggestions: [
              { description: "The feature is enabled", value: "enabled" },
              { description: "The feature is not enabled", value: "not-enabled" }
            ],
            negatable: true,
          },
          CoverageQueryParser::VISIBILITY => {
            description: visibilities.join(", "),
            suggestions: visibilities.map { |v| { description: v.humanize, value: v } },
            negatable: true,
          },
          CoverageQueryParser::REPOSITORY => {
            description: "repo-name",
            path: security_center_options_path("options-type": "repos"),
            negatable: true
          },
          CoverageQueryParser::SECRET_SCANNING => {
            description: "enabled, not-enabled",
            suggestions: [
              { description: "The feature is enabled", value: "enabled" },
              { description: "The feature is not enabled", value: "not-enabled" }
            ],
            negatable: true,
          },
          CoverageQueryParser::SECRET_SCANNING_PUSH_PROTECTION => {
            description: "enabled, not-enabled",
            suggestions: [
              { description: "The feature is enabled", value: "enabled" },
              { description: "The feature is not enabled", value: "not-enabled" }
            ],
            negatable: true,
          },
          CoverageQueryParser::SORT => {
            description: "last-updated, repos",
            suggestions: [
              { description: "Last updated", value: "last-updated" },
              { description: "Repository name", value: "repos" },
            ]
          },
          CoverageQueryParser::TEAM => {
            description: "team-name",
            path: security_center_options_path("options-type": "teams"),
            negatable: true
          },
          CoverageQueryParser::TOPIC => {
            description: "topic-name",
            path: security_center_options_path("options-type": "topics"),
            negatable: true
          },
        }.compact

        if this_organization.advanced_security_products_bundled?
          filter_input_suggestions[CoverageQueryParser::ADVANCED_SECURITY] = {
            description: "enabled, not-enabled",
            suggestions: [
              { description: "The feature is enabled", value: "enabled" },
              { description: "The feature is not enabled", value: "not-enabled" }
            ],
            negatable: true,
          }
        end

        filter_input_suggestions.sort.to_h
      end

      memoize def stats_summaries_data
        ::SecurityOverviewAnalytics::Coverage::StatsQuery
          .for_organization(
            organization: this_organization,
            repo_ids: adminable_repo_ids.first,
            user: T.must(current_user),
            user_session:,
            parser:,
          )
          .perform
          .items
      end

      memoize def repository_list_data
        result = ::SecurityOverviewAnalytics::Coverage::ListQuery
          .for_organization(
            organization: this_organization,
            repo_ids: adminable_repo_ids.first,
            user: T.must(current_user),
            user_session:,
            parser:,
          )
          .perform(page: current_page, page_size: PER_PAGE)

        ::SecurityCenter::Coverage::RepositoryListComponent::Data.new(
          active_href: query_string(parser.add_or_replace(CoverageQueryParser::ARCHIVED, "false")),
          archived_href: query_string(parser.add_or_replace(CoverageQueryParser::ARCHIVED, "true")),
          is_archived_selected: parser.pair_exists?(CoverageQueryParser::ARCHIVED, "true"),
          is_nonarchived_selected: parser.pair_exists?(CoverageQueryParser::ARCHIVED, "false"),
          list_data: result.items,
          current_page:,
          async_counts_href: security_center_coverage_counts_path(this_organization, { query: }),
        )
      end

      sig { returns(::SecurityOverviewAnalytics::Coverage::CountsQuery::Result) }
      memoize def repository_list_counts
        ::SecurityOverviewAnalytics::Coverage::CountsQuery
          .for_organization(
            organization: this_organization,
            repo_ids: adminable_repo_ids.first,
            user: T.must(current_user),
            user_session:,
            parser:,
          )
          .perform(page_size: DEFAULT_PER_PAGE)
      end

      memoize def export_button_props
        {
          createExportUrl: security_center_coverage_create_export_path(query: query),
          errorBannerId: "security-center-export-error-banner",
          successBannerId: "security-center-export-success-banner",
          startedBannerId: "security-center-export-started-banner",
          successDescription: "Your report is ready and the download has started. An email with the report has also been sent to you.",
          startedDescription: "Your report is being generated. You will receive an email when it's ready. Stay on this page to automatically download the report.",
        }
      end

      instrument_method \
        :allowed_repo_ids,
        :index,
        :stats,
        :counts,
        :feature_status,
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
        only: [:index, :stats, :feature_status]

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
        only: [:index, :stats, :counts, :feature_status],
        optional: true
    end
  end
end
