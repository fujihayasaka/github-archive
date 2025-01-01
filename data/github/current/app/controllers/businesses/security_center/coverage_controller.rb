# typed: strict
# frozen_string_literal: true

module Businesses
  module SecurityCenter
    class CoverageController < Businesses::SecurityCenter::AbstractSecurityCenterController
      extend T::Sig
      include ReactHelper

      javascript_bundle "security-center-filter-support" # This can be removed when we move to the new QB component

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
      CoverageQueryParser = ::Search::Queries::SecurityCenter::CoverageQueryParser

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
            filter_input_suggestions: show_blankslate ? nil : filter_input_suggestions,
            query: query,
            default_query: DEFAULT_QUERY,
            show_blankslate: show_blankslate,
            repository_list_data: repository_list_data,
            list_menus: show_blankslate ? [] : list_menus,
            filter_menus: show_blankslate ? [] : filter_menus,
            sso_payload: sso_payload,
            no_authorized_orgs: authorized_orgs.empty?,
            async_stats_src: security_center_coverage_stats_enterprise_path(query: query),
          }
        end

        log_timing(step: "render") do
          render "businesses/security_center/coverage/index", locals: { data: }
        end
      end

      sig { void }
      def stats # rubocop:todo GitHub/UseRestfulActions
        data = log_timing(step: "build locals") do
          { stats_summaries_data: }
        end

        log_timing(step: "render") do
          render "businesses/security_center/coverage/stats_summaries", layout: false, locals: { data: }
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

      sig { returns(::SecurityCenter::Coverage::RepositoryListComponent::Data) }
      memoize def repository_list_data
        result = ::SecurityCenter::Coverage::ListDataQuery.for_organizations(
          user: T.must(current_user),
          user_session: user_session,
          business: this_business,
          organizations: authorized_orgs,
          page_size: DEFAULT_PER_PAGE,
          parser: parser,
        ).run(page: current_page)

        ::SecurityCenter::Coverage::RepositoryListComponent::Data.new(
          active_href: query_string(parser.add_or_replace(CoverageQueryParser::ARCHIVED, "false")),
          archived_href: query_string(parser.add_or_replace(CoverageQueryParser::ARCHIVED, "true")),
          is_archived_selected: parser.pair_exists?(CoverageQueryParser::ARCHIVED, "true"),
          is_nonarchived_selected: parser.pair_exists?(CoverageQueryParser::ARCHIVED, "false"),
          list_data: result.list_items,
          current_page: result.current_page,
          multi_repo_enablement_data: nil,
          show_enablement: false,
          async_counts_href: security_center_coverage_counts_enterprise_path(this_business, { query: }),
        )
      end

      sig { returns(::SecurityCenter::Coverage::ListDataQuery::CountsResult) }
      memoize def repository_list_counts
        query = ::SecurityCenter::Coverage::ListDataQuery.for_organizations(
          user: T.must(current_user),
          user_session: user_session,
          business: this_business,
          organizations: authorized_orgs,
          page_size: DEFAULT_PER_PAGE,
          parser: parser,
        )

        query.counts
      end

      sig { returns(T::Array[::SecurityCenter::Coverage::SelectMenuComponent::Data]) }
      def filter_menus
        return [] if Team.owned_by(authorized_orgs).size > TEAM_DROPDOWN_THRESHOLD

        [
          ::SecurityCenter::Coverage::SelectMenuComponent::Data.new(
            name: "Teams",
            header: "Filter by team",
            filter: ::SecurityCenter::Coverage::SelectMenuComponent::Filter.new(placeholder: "Filter teams"),
            options_src: security_center_options_enterprise_path(
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

      sig { returns(T::Array[::SecurityCenter::Coverage::StatsSummaryComponent::Data]) }
      memoize def stats_summaries_data
        stats = ::SecurityCenter::Coverage::StatsDataQuery.for_organizations(
          user: T.must(current_user),
          user_session: user_session,
          business: this_business,
          organizations: authorized_orgs,
          parser: parser,
        ).run

        ::SecurityCenter::Coverage::CreateViewModelsForStats.call(
          actor: T.must(current_user),
          scope: this_business,
          parser: parser,
          stats: stats,
        )
      end

      sig { returns(T::Hash[Symbol, T::Hash[Symbol, T.untyped]]) }
      def filter_input_suggestions
        visibilities = %w[public internal private]

        {
          CoverageQueryParser::ADVANCED_SECURITY => {
            description: "enabled, not-enabled",
            suggestions: [
              { description: "The feature is enabled", value: "enabled" },
              { description: "The feature is not enabled", value: "not-enabled" }
            ],
            negatable: true,
          },
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
          CoverageQueryParser::OWNER => {
            description: "owner-name",
            path: security_center_options_enterprise_path("options-type": "owners"),
            negatable: true,
          },
          CoverageQueryParser::REPOSITORY => {
            description: "repo-name",
            path: security_center_options_enterprise_path("options-type": "repos"),
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
            path: security_center_options_enterprise_path("options-type": "teams"),
            negatable: true
          },
          CoverageQueryParser::TOPIC => {
            description: "topic-name",
            path: security_center_options_enterprise_path("options-type": "topics"),
            negatable: true
          },
        }.compact
      end

      sig do
        returns(T::Array[T.any(
            ::SecurityCenter::Coverage::SelectMenuComponent::Data,
            ::SecurityCenter::ActionMenuComponent::Data,
          )]
        )
      end
      def list_menus
        sort_option = parser.sort_by.then { |sort_option, _| ::SecurityCenter::Coverage::SortBy.new(sort_option).sort_option }

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

      sig { returns(String) }
      memoize def query
        params[:query] || DEFAULT_QUERY
      end

      sig { returns(CoverageQueryParser) }
      memoize def parser
        CoverageQueryParser.new(query)
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

      depends_on_clusters \
        ApplicationRecord::Collab,
        ApplicationRecord::Configurations,
        ApplicationRecord::Copilot,
        ApplicationRecord::Iam,
        ApplicationRecord::IamAbilities,
        ApplicationRecord::Mysql1,
        ApplicationRecord::Notify,
        ApplicationRecord::Repositories,
        only: [:index]

      depends_on_clusters \
        ApplicationRecord::Billing,
        ApplicationRecord::Mysql2,
        ApplicationRecord::Mysql5,
        ApplicationRecord::NotificationsEntries,
        ApplicationRecord::SecurityOverviewAnalytics,
        optional: true,
        only: [:index]

      depends_on_clusters \
        ApplicationRecord::Collab,
        ApplicationRecord::Configurations,
        ApplicationRecord::Iam,
        ApplicationRecord::IamAbilities,
        ApplicationRecord::Mysql1,
        ApplicationRecord::Notify,
        only: [:stats]

      depends_on_clusters \
        ApplicationRecord::Copilot,
        ApplicationRecord::Mysql2,
        ApplicationRecord::NotificationsEntries,
        optional: true,
        only: [:stats]

      depends_on_clusters \
        ApplicationRecord::Collab,
        ApplicationRecord::Configurations,
        ApplicationRecord::IamAbilities,
        ApplicationRecord::Mysql1,
        only: [:counts]

      depends_on_clusters \
        ApplicationRecord::Copilot,
        ApplicationRecord::Iam,
        ApplicationRecord::Mysql2,
        ApplicationRecord::NotificationsEntries,
        ApplicationRecord::Notify,
        optional: true,
        only: [:counts]

      instrument_method \
        :index,
        :stats,
        :counts,
        :stats_summaries_data,
        :repository_list_data,
        :repository_list_counts,
        :filter_input_suggestions,
        :filter_menus,
        :list_menus,
        :authorized_and_unauthorized_orgs
    end
  end
end
