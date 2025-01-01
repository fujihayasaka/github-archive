# typed: strict
# frozen_string_literal: true

module Orgs
  module SecurityCenter
    class OverviewDashboardController < AbstractSecurityCenterController
      include ReactHelper
      include ApplicationHelper
      include GitHub::SecurityCenter::TenantFilteringHelper
      include ::SecurityCenter::DateSpanControllerHelper

      Queries = ::SecurityOverviewAnalytics::Dashboards::Overview::Queries

      before_action :organization_read_required
      before_action :security_center_required
      before_action :ensure_dates, except: [:index]

      # Ensure reconciliation
      after_action :ensure_security_overview_analytics_reconciliation, only: [:index]
      after_action :trigger_security_overview_analytics_backfill, only: [:index]

      # Telemetry
      track_latency_slo "p99-ui-request", 2500, only: [:index]
      track_latency_slo "p50-ui-request", 750, only: [:index]
      track_availability_slo "ui-request", only: [:index]

      sig { void }
      def index
        payload = log_timing(step: "build React payload") do
          feedback = ::SecurityCenter::FeedbackLink.new(
            actor: T.must(current_user),
            scope: this_organization,
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
            incomplete_data_warning: {
              show: allowed_repos_capped?,
              doc_href: ::SecurityCenter::LimitedRepoWarningComponent::PERMISSIONS_DOC_HREF
            },
            custom_properties: ::SecurityCenter::Helpers::CustomProperties.new(org: this_organization, user: T.must(current_user)).definitions_for_frontend,
            show_onboarding_banner: params[:tip] == "security_overview",
            export_error_message: flash[:export_error],
            scope: "organization",
            show_csv_export: !GitHub.enterprise?,
            is_alert_prioritization_experiment_in_progress: is_alert_prioritization_experiment_in_progress?,
          }.to_camelback_keys
        end

        data = log_timing(step: "build layout data") do
          {
            backfill_in_progress: this_organization.trigger_security_center_reconciliation,
            selected_tab: :overview_dashboard,
          }
        end

        log_timing(step: "render") do
          render_react_app(
            app_name: "security-center",
            ssr: false,
            payload:,
            title: "Security · Overview · #{this_organization.display_login}",
            layout: "layouts/security_center/with_sidebar",
            page_data: { data: },
            app_payload_generator: -> do
              {
                enabled_features: {
                  alert_prioritization_owner_csv_job_ui: ::SecurityCenter::FeatureFlagHelper.alert_prioritization_owner_csv_job_ui_enabled?(*feature_flag_actors),
                  security_center_dashboards_show_resolution_filter: ::SecurityCenter::FeatureFlagHelper.dashboards_show_resolution_filter?(*feature_flag_actors),
                  security_center_dashboards_show_autofix_card: CodeScanning::Autofix.any_enabled_for_org?(this_organization),
                },
              }
            end,
          )
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
      def reopened_alerts # rubocop:disable GitHub/UseRestfulActions
        count = log_timing(step: "build payload") do
          get_data(klass: Queries::ReopenedAlerts)
        end

        log_timing(step: "render") do
          render_camelback_json(json: { count: })
        end
      end

      sig { void }
      def age_of_alerts # rubocop:todo GitHub/UseRestfulActions
        result = get_data(klass: Queries::AgeOfAlerts)

        log_timing(step: "render") do
          render_camelback_json(json: { value: result.value, alert_count: result.alert_count })
        end
      end

      sig { void }
      def mean_time_to_remediate # rubocop:todo GitHub/UseRestfulActions
        result = T.let(log_timing(step: "build payload") do
          get_data(klass: Queries::MeanTimeToRemediate)
        end, SecurityOverviewAnalytics::Dashboards::Overview::Queries::MeanTimeToRemediate::Result)

        log_timing(step: "render") do
          render_camelback_json(json: { value: result.value, alert_count: result.alert_count })
        end
      end

      sig { void }
      def net_resolve_rate # rubocop:todo GitHub/UseRestfulActions
        result = T.let(log_timing(step: "build payload") do
          get_data(klass: Queries::NetResolveRate)
        end, SecurityOverviewAnalytics::Dashboards::Overview::Queries::NetResolveRate::Result)

        log_timing(step: "render") do
          render_camelback_json(json: { open_count: result.open_count, closed_count: result.closed_count })
        end
      end

      sig { void }
      def secrets_bypassed # rubocop:todo GitHub/UseRestfulActions
        response, err = log_timing(step: "build payload") do
          get_data(klass: Queries::BypassedSecrets)
        end

        log_timing(step: "render") do
          return render_camelback_json(json: {}, status: :internal_server_error) if err.present?
          render_camelback_json(json: response)
        end
      end

      sig { void }
      def repositories # rubocop:todo GitHub/UseRestfulActions
        repositories = log_timing(step: "build payload") do
          repository_data = get_data(klass: Queries::RepositoriesTable)

          apply_tenant_filter(repository_data)
        end

        url_info = {}
        log_timing(step: "resolve repo urls") do
          Repository
            .where(id: repositories.map { |repo_info| repo_info[:id] })
            .preload(:parent_advisory) # for repo.advisory_workspace? below
            .map { |repo| [repo.id, repo] }
            .to_h
            .each do |repo_id, repo|
              url_info[repo_id] = if repo.advisory_workspace?
                repository_path(repo)
              else
                repository_security_overview_path(repo.owner_display_login, repo)
              end
            end
        end

        repositories.each do |repo|
          repo.merge!(url: url_info[repo[:id]])
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
      def alert_activity # rubocop:todo GitHub/UseRestfulActions
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
          Queries::IntroducedAndPreventedChart.for_organization(
            organization: this_organization,
            allowed_repo_ids: allowed_repo_ids_for_code_scanning&.first,
            user: T.must(current_user),
            user_session:,
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
      def pull_request_alerts_fixed # rubocop:todo GitHub/UseRestfulActions
        payload = log_timing(step: "build payload") do
          Queries::PullRequestAlertsFixedQuery.for_organization(
            organization: this_organization,
            allowed_repo_ids: allowed_repo_ids_for_code_scanning&.first,
            user: T.must(current_user),
            user_session:,
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
          Queries::AlertsFixedWithAutofixQuery.for_organization(
            organization: this_organization,
            allowed_repo_ids: allowed_repo_ids_for_code_scanning&.first,
            user: T.must(current_user),
            user_session:,
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

      sig { returns(T.nilable([T::Array[Integer], T::Boolean])) }
      memoize def allowed_repo_ids_for_code_scanning
        if can_view_all_alerts?
          nil
        else
          allowed_repository_ids_by_feature_for_organization_members[::SecurityCenter::SecurityFeatures::CODE_SCANNING]
        end
      end

      sig do
        params(
          klass: T.any(T.class_of(Queries::Base), (T.class_of(Queries::AlertTrends::Base)))
        ).returns(T.any(Queries::Base::RunQueryOutputAlias, Queries::AlertTrends::Base::RunQueryOutputAlias))
      end
      def get_data(klass:)
        klass.for_organization(
          organization: this_organization,
          user: T.must(current_user),
          query:,
          start_date: T.must(start_date),
          end_date: T.must(end_date),
          user_session:,
          is_open_selected: alert_trends_chart_is_open_selected,
        ).perform
      end

      sig { params(repos: T::Array[T::Hash[T.untyped, T.untyped]]).returns(T::Array[T::Hash[T.untyped, T.untyped]]) }
      def apply_tenant_filter(repos)
        request_scope = :organization
        filter_tenant_rows(
          RequestScope.new(request_scope, this_organization, "soa-dashboard-repositories-table"),
          repos,
          -> (r) { r[:id] }
        ).first
      end

      sig { returns(::Search::Queries::SecurityCenter::QueryParser) }
      memoize def query
        ::Search::Queries::SecurityCenter::QueryParser.new(params.fetch(:query, ""))
      end

      sig { returns(T::Boolean) }
      memoize def alert_trends_chart_is_open_selected
        ActiveModel::Type::Boolean.new.cast(params.dig(:alert_trends_chart, :is_open_selected) || "true")
      end

      sig { returns(T::Boolean) }
      def allowed_repos_capped?
        return false if can_view_all_alerts?
        allowed_repository_ids_by_feature_for_organization_members
          .values.reduce(T.let(false, T::Boolean)) { |memo, (_, capped)| memo || capped }
      end

      sig { returns(T::Boolean) }
      memoize def is_alert_prioritization_experiment_in_progress?
        job_status = ::SecurityCenter::AlertPrioritization::CopilotPromptExperiments::OwnerRepoClassificationControlJob.status(this_organization)
        return false if job_status.blank?
        return false if job_status.finished?
        true
      end

      sig { returns([Organization, User]) }
      memoize def feature_flag_actors
        [this_organization, T.must(current_user)]
      end

      sig { returns(T::Array[String]) }
      def datadog_tags
        tags = super

        return tags if current_user.nil?

        [
          ::SecurityOverviewAnalytics::Filters::ByArchived.new(*query.get_positive_and_negative_qualified_values("archived")),
          ::SecurityOverviewAnalytics::Filters::ByRepository.new(query.get_unqualified_values, [], substring_match: true),
          ::SecurityOverviewAnalytics::Filters::ByRepository.new(*query.get_positive_and_negative_qualified_values("repo"), substring_match: true),
          ::SecurityOverviewAnalytics::Filters::ByTeam.new(*query.get_positive_and_negative_qualified_values("team"), organizations: [this_organization], user: T.must(current_user)),
          ::SecurityOverviewAnalytics::Filters::ByTopic.new(*query.get_positive_and_negative_qualified_values("topic"), organizations: [this_organization]),
          ::SecurityOverviewAnalytics::Filters::ByVisibility.new(*query.get_positive_and_negative_qualified_values("visibility")),
          ::SecurityOverviewAnalytics::Filters::ByResolution.new(*query.get_positive_and_negative_qualified_values("resolution")),
          ::SecurityOverviewAnalytics::Filters::BySeverity.new(*query.get_positive_and_negative_qualified_values("severity"))
        ].compact.map do |filter|
          next unless filter.respond_to?(:is_empty?)
          next if filter.is_empty?
          tags << "has_filter:#{filter.class.name&.demodulize.underscore}"
        end

        tags << "has_filter:by_custom_property" if query.custom_properties_string.present?

        pos_requested_security_features, neg_requested_security_features = query.get_positive_and_negative_qualified_values("tool")
        if pos_requested_security_features.present? || neg_requested_security_features.present?
          tags << "has_filter:by_tool"
        end

        tags
      end

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
        only: [:index]

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
    end
  end
end
