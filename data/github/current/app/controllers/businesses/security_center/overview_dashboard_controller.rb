# typed: strict
# frozen_string_literal: true

module Businesses
  module SecurityCenter
    class OverviewDashboardController < AbstractSecurityCenterController
      include ReactHelper
      include ::SecurityCenter::DateSpanControllerHelper
      include GitHub::SecurityCenter::TenantFilteringHelper

      Queries = ::SecurityOverviewAnalytics::Dashboards::Overview::Queries

      before_action :security_center_required
      before_action :ensure_dates, except: [:index]

      after_action :ensure_security_overview_analytics_reconciliation, only: [:index]
      after_action :trigger_security_overview_analytics_backfill, only: [:index]
      after_action :ensure_security_center_reconciliation, only: [:index]

      sig { void }
      def index
        route_payload = log_timing(step: "build React payload") do
          if !show_blankslate
            feedback = ::SecurityCenter::FeedbackLink.new(
              actor: T.must(current_user),
              scope: this_business,
            )

            {
              initial_date_span: initial_date_span,
              initial_query: params.key?(:query) ? query.to_s : nil,
              initial_selected_impact_analysis_table: params.fetch(:impact_analysis_tab, "repositories"),
              feedback_link: {
                text: feedback.text,
                url: feedback.url,
              },
              alert_trends_chart: {
                grouping: params.dig(:alert_trends_chart, :grouping)
              },
              custom_properties: [], # TODO: Implement business version of `SecurityCenter::Helpers::CustomProperties` and use here
              scope: "enterprise",
              show_csv_export: !GitHub.enterprise? && ::SecurityCenter::FeatureFlagHelper.enterprise_overview_csv_export?(*feature_flag_actors),
              allow_owner_type_filtering: can_see_personal_repos?,
            }.to_camelback_keys
          end
        end

        app_payload_generator = log_timing(step: "build app payload") do
          if show_blankslate
            blankslate_app_payload_generator(
              heading: "Overview",
              subheading: "Alert trends and insights across your enterprise.",
              message: "No repositories to show.",
              description: blankslate_description,
              # TODO: Need a doc link
              # learn_more_link: {
              #   text: "Learn more about viewing the overview page.",
              #   url: "#",
              # },
            )
          else
            content_app_payload_generator(feature_flags: {
                security_center_dashboards_show_resolution_filter: ::SecurityCenter::FeatureFlagHelper.dashboards_show_resolution_filter?(*feature_flag_actors),
                security_center_dashboards_show_autofix_card: CodeScanning::Autofix.any_allowed_by_business?(this_business),
              }
            )
          end
        end

        log_timing(step: "render") do
          render_react_app(
            app_name: "security-center",
            ssr: false,
            payload: route_payload,
            title: "Security · Overview · #{this_business}",
            app_payload_generator:,
          )
        end
      end

      sig { void }
      def age_of_alerts # rubocop:disable GitHub/UseRestfulActions
        result = T.let(log_timing(step: "build payload") do
          get_data(klass: Queries::AgeOfAlerts)
        end, SecurityOverviewAnalytics::Dashboards::Overview::Queries::AgeOfAlerts::Result)

        log_timing(step: "render") do
          render_camelback_json(json: { value: result.value, alert_count: result.alert_count })
        end
      end

      sig { void }
      def alert_trends_by_age # rubocop:disable GitHub/UseRestfulActions
        alert_trends = log_timing(step: "build payload") do
          get_data(klass: Queries::AlertTrends::ByAge)
        end

        log_timing(step: "render") do
          render_camelback_json(json: { alert_trends: })
        end
      end

      sig { void }
      def alert_trends_by_severity # rubocop:disable GitHub/UseRestfulActions
        alert_trends = log_timing(step: "build payload") do
          get_data(klass: Queries::AlertTrends::BySeverity)
        end

        log_timing(step: "render") do
          render_camelback_json(json: { alert_trends: })
        end
      end

      sig { void }
      def alert_trends_by_tool_code_scanning # rubocop:disable GitHub/UseRestfulActions
        alert_trends = log_timing(step: "build payload") do
          get_data(klass: Queries::AlertTrends::ByTool::CodeScanning)
        end

        log_timing(step: "render") do
          render_camelback_json(json: { alert_trends: })
        end
      end

      sig { void }
      def alert_trends_by_tool_dependabot_alerts # rubocop:disable GitHub/UseRestfulActions
        alert_trends = log_timing(step: "build payload") do
          get_data(klass: Queries::AlertTrends::ByTool::DependabotAlerts)
        end

        log_timing(step: "render") do
          render_camelback_json(json: { alert_trends: })
        end
      end

      sig { void }
      def alert_trends_by_tool_secret_scanning # rubocop:disable GitHub/UseRestfulActions
        alert_trends = log_timing(step: "build payload") do
          get_data(klass: Queries::AlertTrends::ByTool::SecretScanning)
        end

        log_timing(step: "render") do
          render_camelback_json(json: { alert_trends: })
        end
      end

      sig { void }
      def mean_time_to_remediate # rubocop:disable GitHub/UseRestfulActions
        result = T.let(log_timing(step: "build payload") do
          get_data(klass: Queries::MeanTimeToRemediate)
        end, SecurityOverviewAnalytics::Dashboards::Overview::Queries::MeanTimeToRemediate::Result)

        log_timing(step: "render") do
          render_camelback_json(json: { value: result.value, alert_count: result.alert_count })
        end
      end

      sig { void }
      def net_resolve_rate # rubocop:disable GitHub/UseRestfulActions
        result = T.let(log_timing(step: "build payload") do
          get_data(klass: Queries::NetResolveRate)
        end, SecurityOverviewAnalytics::Dashboards::Overview::Queries::NetResolveRate::Result)

        log_timing(step: "render") do
          render_camelback_json(json: { open_count: result.open_count, closed_count: result.closed_count })
        end
      end

      sig { void }
      def reopened_alerts # rubocop:disable GitHub/UseRestfulActions
        count = log_timing(step: "build payload") do
          get_data(klass: Queries::ReopenedAlerts)
        end

        log_timing(step: "render") do
          render_camelback_json(json: { count: })
        end
      end

      sig { void }
      def repositories # rubocop:disable GitHub/UseRestfulActions
        repositories = log_timing(step: "build payload") do
          repository_data = get_data(klass: Queries::RepositoriesTable)
          apply_tenant_filter(repository_data)
        end

        url_info = {}
        log_timing(step: "resolve repo urls") do
          repository_info = Repository
            .where(id: repositories.map { |repo_info| repo_info[:id] })
            .preload(:parent_advisory) # for repo.advisory_workspace? below
            .map { |repo| [repo.id, repo] }
            .to_h

          repositories.each { |repo| repo[:repository] = (repository_info[repo[:id]]&.name_with_display_owner || repo[:repository]) }

          repository_info.each do |repo_id, repo|
            url_info[repo_id] = if repo.advisory_workspace?
              repository_path(repo)
            else
              repository_security_overview_path(repo.owner_display_login, repo)
            end
          end
        end

        repositories.each do |repo|
          url = if repo[:owner_type] == "ORGANIZATION"
            url_info[repo[:id]]
          else
            security_center_alerts_secret_scanning_enterprise_path(query: "repo:#{repo[:repository]}")
          end

          repo.merge!(url: url)
        end

        log_timing(step: "render") do
          render_camelback_json(json: { repositories: })
        end
      end

      sig { void }
      def advisories # rubocop:todo GitHub/UseRestfulActions
        advisories = log_timing(step: "build payload") do
          get_data(klass: Queries::AdvisoriesTable)
        end

        advisories = log_timing(step: "resolve advisory info") do
          advisories_by_id = advisories.map { |advisory| [advisory[:ghsa_id], advisory] }.to_h

          Vulnerability.where(ghsa_id: advisories_by_id.keys).each do |vuln|
            if vuln.summary.present?
              summary = vuln.summary
            else
              # if there is no summary, use the first line of the description
              summary = vuln.description.split("\n")[0]
              # if the first line is too long, truncate it
              if summary.length > 100
                summary = summary.first(100)
                summary << "..."
              end
            end

            advisories_by_id[vuln.ghsa_id]&.merge!(
              summary: summary,
              cve_id: vuln.cve_id,
              severity: vuln.severity,
              ecosystem: vuln.vulnerable_version_ranges.first.ecosystem,
            )
          end

          advisories_by_id.values.sort_by { |advisory| advisory[:open_alerts] }.reverse
        end

        log_timing(step: "render") do
          render_camelback_json(json: { advisories: })
        end
      end

      sig { void }
      def alert_activity # rubocop:disable GitHub/UseRestfulActions
        data = log_timing(step: "build payload") do
          get_data(klass: Queries::AlertActivityChart)
        end

        log_timing(step: "render") do
          render_camelback_json(json: { data: })
        end
      end

      sig { void }
      def introduced_prevented # rubocop:todo GitHub/UseRestfulActions
        payload = log_timing(step: "build payload") do
          Queries::IntroducedAndPreventedChart.for_business(
            business: this_business,
            organizations: T.must(authorized_orgs_by_feature[:code_scanning]),
            user: T.must(current_user),
            query:,
            start_date: T.must(start_date),
            end_date: T.must(end_date),
          ).perform
        end

        log_timing(step: "render") do
          render_camelback_json(json: payload.series.map(&:serialize))
        end
      end

      sig { void }
      def sast # rubocop:todo GitHub/UseRestfulActions
        data = log_timing(step: "build payload") do
          get_data(klass: Queries::SastTable)
        end

        log_timing(step: "render") do
          render_camelback_json(json: { data: data.map(&:to_h) })
        end
      end

      sig { void }
      def secrets_bypassed # rubocop:disable GitHub/UseRestfulActions
        response, err = log_timing(step: "build payload") do
          get_data(klass: Queries::BypassedSecrets)
        end

        log_timing(step: "render") do
          return render_camelback_json(json: {}, status: :internal_server_error) if err.present?
          render_camelback_json(json: response)
        end
      end

      sig { void }
      def pull_request_alerts_fixed # rubocop:todo GitHub/UseRestfulActions
        payload = log_timing(step: "build payload") do
          Queries::PullRequestAlertsFixedQuery.for_business(
            business: this_business,
            organizations: T.must(authorized_orgs_by_feature[:code_scanning]),
            user: T.must(current_user),
            query:,
            start_date: T.must(start_date),
            end_date: T.must(end_date),
          ).perform
        end

        log_timing(step: "render") do
          render_camelback_json(json: payload.serialize)
        end
      end

      sig { void }
      def alerts_fixed_with_autofix # rubocop:todo GitHub/UseRestfulActions
        payload = log_timing(step: "build payload") do
          Queries::AlertsFixedWithAutofixQuery.for_business(
            business: this_business,
            organizations: T.must(authorized_orgs_by_feature[:code_scanning]),
            user: T.must(current_user),
            query:,
            start_date: T.must(start_date),
            end_date: T.must(end_date),
          ).perform
        end

        log_timing(step: "render") do
          render_camelback_json(json: payload.serialize)
        end
      end

      private

      sig { override.returns(T::Array[Symbol]) }
      def authorized_orgs_actions
        [:read_code_scanning, :view_dependabot_alerts, :view_secret_scanning_alerts]
      end

      sig do
        params(
          klass: T.class_of(Queries::Base)
        ).returns(T.any(Queries::Base::RunQueryOutputAlias, Queries::AlertTrends::Base::RunQueryOutputAlias))
      end
      def get_data(klass:)
        klass.for_business(
          business: this_business,
          user: T.must(current_user),
          query:,
          start_date: T.must(start_date),
          end_date: T.must(end_date),
          authorized_orgs_by_feature:,
          user_session:,
          is_open_selected: alert_trends_chart_is_open_selected,
        ).perform
      end

      sig { returns(::Search::Queries::SecurityCenter::QueryParser) }
      memoize def query
        ::Search::Queries::SecurityCenter::QueryParser.new(params.fetch(:query, ""))
      end

      sig { returns([Business, User]) }
      memoize def feature_flag_actors
        [this_business, T.must(current_user)]
      end

      sig { params(repos: T::Array[T::Hash[T.untyped, T.untyped]]).returns(T::Array[T::Hash[T.untyped, T.untyped]]) }
      def apply_tenant_filter(repos)
        request_scope = :business
        filter_tenant_rows(
          RequestScope.new(request_scope, this_business, "soa-dashboard-repositories-table"),
          repos,
          -> (r) { r[:id] }
        ).first
      end

      sig { returns(T::Boolean) }
      memoize def alert_trends_chart_is_open_selected
        ActiveModel::Type::Boolean.new.cast(params.dig(:alert_trends_chart, :is_open_selected) || "true")
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
        only: [
          :advisories,
          :age_of_alerts,
          :alert_activity,
          :alert_trends_by_age,
          :alert_trends_by_severity,
          :alert_trends_by_tool_code_scanning,
          :alert_trends_by_tool_dependabot_alerts,
          :alert_trends_by_tool_secret_scanning,
          :alerts_fixed_with_autofix,
          :index,
          :introduced_prevented,
          :mean_time_to_remediate,
          :net_resolve_rate,
          :pull_request_alerts_fixed,
          :reopened_alerts,
          :repositories,
          :sast,
          :secrets_bypassed,
        ]

      depends_on_clusters \
        ApplicationRecord::SecurityOverviewAnalytics,
        only: [
          :advisories,
          :age_of_alerts,
          :alert_activity,
          :alert_trends_by_age,
          :alert_trends_by_severity,
          :alert_trends_by_tool_code_scanning,
          :alert_trends_by_tool_dependabot_alerts,
          :alert_trends_by_tool_secret_scanning,
          :alerts_fixed_with_autofix,
          :introduced_prevented,
          :mean_time_to_remediate,
          :net_resolve_rate,
          :pull_request_alerts_fixed,
          :reopened_alerts,
          :repositories,
          :sast,
          :secrets_bypassed,
        ]

      depends_on_clusters \
        ApplicationRecord::SecurityOverviewAnalytics,
        only: [:index],
        optional: true

      depends_on_clusters \
        ApplicationRecord::Copilot,
        only: [
          :advisories,
          :age_of_alerts,
          :alert_activity,
          :alert_trends_by_age,
          :alert_trends_by_severity,
          :alert_trends_by_tool_code_scanning,
          :alert_trends_by_tool_dependabot_alerts,
          :alert_trends_by_tool_secret_scanning,
          :alerts_fixed_with_autofix,
          :index,
          :introduced_prevented,
          :mean_time_to_remediate,
          :net_resolve_rate,
          :pull_request_alerts_fixed,
          :reopened_alerts,
          :repositories,
          :sast,
          :secrets_bypassed,
        ],
        optional: true

      instrument_method \
        :age_of_alerts,
        :alert_activity,
        :introduced_prevented,
        :alert_trends_by_age,
        :alert_trends_by_severity,
        :alert_trends_by_tool_code_scanning,
        :alert_trends_by_tool_dependabot_alerts,
        :alert_trends_by_tool_secret_scanning,
        :apply_tenant_filter,
        :index,
        :mean_time_to_remediate,
        :net_resolve_rate,
        :reopened_alerts,
        :repositories,
        :advisories,
        :secrets_bypassed,
        :sast,
        :pull_request_alerts_fixed,
        :alerts_fixed_with_autofix
    end
  end
end
