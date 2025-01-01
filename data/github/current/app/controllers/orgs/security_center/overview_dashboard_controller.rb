# typed: strict
# frozen_string_literal: true

module Orgs
  module SecurityCenter
    class OverviewDashboardController < AbstractSecurityCenterController
      extend T::Sig
      include ReactHelper
      include ApplicationHelper
      include GitHub::SecurityCenter::TenantFilteringHelper
      include ::SecurityCenter::DateSpanControllerHelper

      Queries = ::SecurityOverviewAnalytics::Dashboards::Overview::Queries

      before_action :organization_read_required
      before_action :security_center_required
      before_action :no_data_response, only: [
        :alert_trends_by_age,
        :alert_trends_by_tool_code_scanning,
        :alert_trends_by_tool_dependabot_alerts,
        :alert_trends_by_tool_secret_scanning,
        :alert_trends_by_severity
      ]
      before_action :ensure_dates, except: [:index]

      # Ensure reconciliation
      after_action :ensure_security_overview_analytics_reconciliation, only: [:index]
      after_action :trigger_security_overview_analytics_backfill, only: [:index]

      # Telemetry
      track_latency_slo "p99-ui-request", 2500, only: [:index]
      track_latency_slo "p50-ui-request", 750, only: [:index]
      track_availability_slo "ui-request", only: [:index]

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
          :index,
          :alert_trends_by_age,
          :alert_trends_by_severity,
          :alert_trends_by_tool_code_scanning,
          :alert_trends_by_tool_dependabot_alerts,
          :alert_trends_by_tool_secret_scanning,
          :alert_activity,
          :introduced_prevented,
          :reopened_alerts,
          :age_of_alerts,
          :mean_time_to_remediate,
          :secrets_bypassed,
          :autofix_suggestions,
          :net_resolve_rate,
          :repositories,
          :advisories,
          :sast
        ]

      depends_on_clusters \
        ApplicationRecord::SecurityOverviewAnalytics,
        only: [
          :alert_trends_by_age,
          :alert_trends_by_severity,
          :alert_trends_by_tool_code_scanning,
          :alert_trends_by_tool_dependabot_alerts,
          :alert_trends_by_tool_secret_scanning,
          :alert_activity,
          :introduced_prevented,
          :reopened_alerts,
          :age_of_alerts,
          :mean_time_to_remediate,
          :secrets_bypassed,
          :autofix_suggestions,
          :net_resolve_rate,
          :repositories,
          :advisories,
          :sast
        ]

      depends_on_clusters ApplicationRecord::Copilot,
      only: [
        :age_of_alerts,
        :alert_activity,
        :introduced_prevented,
        :alert_trends_by_age,
        :alert_trends_by_severity,
        :alert_trends_by_tool_code_scanning,
        :alert_trends_by_tool_dependabot_alerts,
        :alert_trends_by_tool_secret_scanning,
        :index,
        :mean_time_to_remediate,
        :net_resolve_rate,
        :reopened_alerts,
        :repositories,
        :advisories,
        :secrets_bypassed,
        :sast
      ], optional: true

      depends_on_clusters \
        ApplicationRecord::SecurityOverviewAnalytics,
        optional: true,
        only: [
          :index,
        ]

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
              is_open_selected: alert_trends_chart_is_open_selected,
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
                  security_center_dashboards_show_sast_table: ::SecurityCenter::FeatureFlagHelper.dashboards_show_widget?(:sast_table, *feature_flag_actors),
                  security_center_dashboards_show_severity_filter: ::SecurityCenter::FeatureFlagHelper.dashboards_show_filter?(:severity, *feature_flag_actors),
                  security_center_dashboards_show_resolution_filter: ::SecurityCenter::FeatureFlagHelper.dashboards_show_filter?(:resolution, *feature_flag_actors),
                  security_center_dashboards_show_three_tab_dashboard: ::SecurityCenter::FeatureFlagHelper.show_three_tab_dashboard?(*feature_flag_actors),
                  security_center_show_csv_export: ::SecurityCenter::FeatureFlagHelper.overview_dashboard_csv_export?(*feature_flag_actors),
                  security_center_dashboards_show_autofix_card: CodeScanning::Autofix.enabled_for_org?(this_organization),
                  security_center_dashboards_cards_parallel_queries_per_tool: enable_parallel_queries_by_tool?,
                  security_center_dashboards_parallel_queries_by_4_slices: enable_parallel_queries_by_4_slices?,
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
          if enable_parallel_queries_by_tool?
            render_camelback_json(json: { value: result.value, alert_count: result.alert_count })
          else
            render_camelback_json(json: { count: result.value })
          end
        end
      end

      sig { void }
      def mean_time_to_remediate # rubocop:todo GitHub/UseRestfulActions
        result = T.let(log_timing(step: "build payload") do
          get_data(klass: Queries::MeanTimeToRemediate)
        end, SecurityOverviewAnalytics::Dashboards::Overview::Queries::MeanTimeToRemediate::Result)

        log_timing(step: "render") do
          if enable_parallel_queries_by_tool?
            render_camelback_json(json: { value: result.value, alert_count: result.alert_count })
          else
            render_camelback_json(json: { count: result.value })
          end
        end
      end

      sig { void }
      def net_resolve_rate # rubocop:todo GitHub/UseRestfulActions
        result = T.let(log_timing(step: "build payload") do
          get_data(klass: Queries::NetResolveRate)
        end, SecurityOverviewAnalytics::Dashboards::Overview::Queries::NetResolveRate::Result)

        log_timing(step: "render") do
          if enable_parallel_queries_by_tool?
            render_camelback_json(json: { open_count: result.open_count, closed_count: result.closed_count })
          else
            render_camelback_json(json: { count: result.value })
          end
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
      def autofix_suggestions # rubocop:todo GitHub/UseRestfulActions
        return render_404 unless CodeScanning::Autofix.enabled_for_org?(this_organization)

        result = log_timing(step: "build payload") do
          get_data(klass: Queries::AutofixSuggestions)
        end

        log_timing(step: "render") do
          return render_camelback_json(json: {}, status: :internal_server_error) if result.is_a? Queries::AutofixSuggestions::ErrorResult
          render_camelback_json(json: result.serialize)
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

        log_timing(step: "render") do
          render_camelback_json(json: { repositories:, url_info: })
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
          allowed_repository_ids_for_organization_members = if can_manage_security_products?
            nil
          else
            allowed_repository_ids_by_feature_for_organization_members[::SecurityCenter::SecurityFeatures::CODE_SCANNING]
          end

          if ::SecurityCenter::FeatureFlagHelper.use_introduced_and_prevented_chart_query_v2?(this_organization, T.must(current_user))
            Queries::IntroducedAndPreventedChartV2.for_organization(
              organization: this_organization,
              allowed_repo_ids: allowed_repository_ids_for_organization_members&.first,
              user: T.must(current_user),
              user_session:,
              query:,
              start_date: T.must(start_date),
              end_date: T.must(end_date),
            ).perform
          else
            Queries::IntroducedAndPreventedChart.for_organization(
              organization: this_organization,
              allowed_repo_ids: allowed_repository_ids_for_organization_members&.first,
              user: T.must(current_user),
              user_session:,
              query:,
              start_date: T.must(start_date),
              end_date: T.must(end_date),
            ).perform
          end
        end

        log_timing(step: "render") do
          render_camelback_json(json: payload.series.map(&:serialize))
        end
      end

      sig { void }
      def sast # rubocop:todo GitHub/UseRestfulActions
        return render_404 unless ::SecurityCenter::FeatureFlagHelper.dashboards_show_widget?(:sast_table, *feature_flag_actors)

        data = log_timing(step: "build payload") do
          get_data(klass: Queries::SastTable)
        end

        log_timing(step: "render") do
          render_camelback_json(json: { data: data.map(&:to_h) })
        end
      end

      private

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
          return_alert_count: enable_parallel_queries_by_tool?,
          is_open_selected: alert_trends_chart_is_open_selected,
          slice4:,
        ).perform
      end

      sig { returns(T::Boolean) }
      def enable_parallel_queries_by_tool?
        ::SecurityCenter::FeatureFlagHelper.dashboards_cards_parallel_queries_per_tool?(*feature_flag_actors)
      end

      sig { returns(T::Boolean) }
      def enable_parallel_queries_by_4_slices?
        ::SecurityCenter::FeatureFlagHelper.dashboards_parallel_queries_by_4_slices?(*feature_flag_actors)
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

      sig { returns(T.nilable(Integer)) }
      memoize def slice4
        val = params.fetch(:slice4, nil)
        if val.nil?
          nil
        else
          val.to_i
        end
      end

      sig { returns(T::Boolean) }
      memoize def alert_trends_chart_is_open_selected
        ActiveModel::Type::Boolean.new.cast(params.dig(:alert_trends_chart, :is_open_selected) || "true")
      end

      sig { returns(T::Boolean) }
      def allowed_repos_capped?
        return false if can_manage_security_products?
        allowed_repository_ids_by_feature_for_organization_members
          .values.reduce(T.let(false, T::Boolean)) { |memo, (_, capped)| memo || capped }
      end

      sig { returns(T::Boolean) }
      memoize def is_alert_prioritization_experiment_in_progress?
        job_status = ::SecurityCenter::AlertPrioritization::CopilotPromptExperiments::OwnerCsvJob.status(this_organization)
        return false if job_status.blank?
        return false if job_status.finished?
        true
      end

      sig { returns([Organization, User]) }
      memoize def feature_flag_actors
        [this_organization, T.must(current_user)]
      end

      sig { returns(T.untyped) }
      def no_data_response
        allowed_repo_ids_by_feature = nil
        unless can_manage_security_products?
          allowed_repo_ids_by_feature =
            allowed_repository_ids_by_feature_for_organization_members.transform_values(&:first)
        end

        repos_filterer = ::SecurityOverviewAnalytics::Dashboards::OrgReposFilterer
          .new(
            allowed_repo_ids_by_feature:,
            organization: this_organization,
            query:,
            user: T.must(current_user),
            user_session:
          )

        render_camelback_json(json: { no_data: "No repositories found" }) unless repos_filterer.any_feature_repo_metadata_rel.exists?
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
        :sast
    end
  end
end
