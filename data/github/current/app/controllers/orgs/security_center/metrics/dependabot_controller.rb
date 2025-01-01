# typed: strict
# frozen_string_literal: true

module Orgs
  module SecurityCenter
    module Metrics
      class DependabotController < AbstractSecurityCenterController
        include ::SecurityCenter::DateSpanControllerHelper

        # Access
        before_action :organization_read_required
        before_action :feature_required
        before_action :security_center_required
        before_action :require_feature_flag

        # Ensure reconciliation
        after_action :ensure_security_overview_analytics_reconciliation, only: [:index]
        after_action :trigger_security_overview_analytics_backfill, only: [:index]

        # Telemetry
        track_latency_slo "p99-ui-request", 2500, only: [:index]
        track_latency_slo "p50-ui-request", 750, only: [:index]
        track_availability_slo "ui-request", only: [:index]

        DEFAULT_QUERY = "archived:false"
        UngroupedAlertQueryFilterOptions = Search::Queries::SecurityCenter::DependabotAlertsQuery::QUALIFIERS

        UngroupedAlertQuery = RepositoryVulnerabilityAlert::UngroupedAlertQuery
        SecurityCenterCoverageListDataQuery = ::SecurityCenter::Coverage::ListDataQuery

        sig { void }
        def index
          payload = log_timing(step: "build React payload") do
            feedback = ::SecurityCenter::FeedbackLink.new(
              actor: current_user,
              scope: this_organization,
            )

            {
              initial_query: params.key?(:query) ? query.to_s : nil,
              feedback_link: {
                text: feedback.text,
                url: feedback.url,
              },
              show_incomplete_data_warning: allowed_repository_ids_for_organization_members&.last,
              incomplete_data_warning_doc_href: ::SecurityCenter::LimitedRepoWarningComponent::PERMISSIONS_DOC_HREF,
              custom_properties: ::SecurityCenter::Helpers::CustomProperties.new(org: this_organization, user: current_user).definitions_for_frontend,
              show_chart_features: this_organization.feature_enabled?(:dependabot_alerts_vad_show_charts),
              allowed_dependabot_qualifiers: UngroupedAlertQueryFilterOptions.map(&:to_s)
            }.to_camelback_keys
          end

          data = log_timing(step: "build locals") do
            {
              backfill_in_progress: this_organization.trigger_security_center_reconciliation,
              selected_tab: :dependabot_metrics,
            }
          end

          log_timing(step: "render") do
            render_react_app(
              app_name: "security-center",
              disable_ssr: true,
              payload:,
              title: "Security · Metrics · Dependabot · #{this_organization.display_login}",
              layout: "layouts/security_center/with_sidebar",
              page_data: { data: },
              app_payload_generator: -> do
                { enabled_features: {} }
              end,
            )
          end
        end

        sig { void }
        def alerts_fixed # rubocop:todo GitHub/UseRestfulActions
          payload = log_timing(step: "build payload") do
            # Query for all closed alerts with specific conditions
            manual_closed_count = closed_alerts_count(
              reason: %w[dependency_changed manifest_deleted manifest_superseded],
              last_state_change_push_id: false
            )

            # Query for alerts closed by Dependabot
            dependabot_closed_count = closed_alerts_count(
              reason: "dependency_updated",
              last_state_change_push_id: true
            )

            # Calculate counts and percentage
            total_closed_count = dependabot_closed_count + manual_closed_count

            # This is done to avoid division by zero
            # and to ensure that the percentage is 0.0 if there are no results
            percentage = if total_closed_count.zero?
              0.0
            else
              (dependabot_closed_count.to_f / total_closed_count * 100).round(2)
            end

            # Serialize the payload to match the expected structure
            {
              count: dependabot_closed_count,
              total: total_closed_count,
              percentage: percentage,
            }
          end

          log_timing(step: "render") do
            render_camelback_json(json: payload)
          end
        end

        sig { void }
        def alerts_funnel # rubocop:todo GitHub/UseRestfulActions
          payload = log_timing(step: "build payload") do
            # Start with base query which accounts for customer‑supplied filters (FilterBar query string) then apply tile-specific conditions
            ungrouped_alert_query = filtered_alerts_relation.open
            # Force the joins so that the count queries can reference them
            arel = ungrouped_alert_query.resolve(ignore_pagination: true, ignore_sorting: true, force_vulnerabilities_join: true, force_epss_join: true)

            map_category_to_sql_conditional_fragment = {
              "has:patch" => VulnerableVersionRange.arel_table[:fixed_in].not_eq(nil),
              "severity:critical,high" => Vulnerability.arel_table[:severity].in(%w[high critical]),
              "epss_percentage:>=0.01" => CVEEPSS.arel_table[:percentage].gteq(0.01),
            }
            # Caller can specify a custom order for the categories
            funnel_category_order = params[:funnel_order].present? ? params[:funnel_order].split(" ") : map_category_to_sql_conditional_fragment.keys

            # Although a private API, this is still untrusted user input, so let's ensure no SQL injection attack
            unless funnel_category_order.all? { |v| map_category_to_sql_conditional_fragment.keys.include?(v) }
              render json: { error: "Invalid funnel category." }, status: :unprocessable_entity
              return
            end

            # Now assemble the SQL query... each subsequent count inherits the filters of all preceding categories
            # The final result of count_columns will look something like:
            #  [
            #    "COUNT(*) AS `Matching Alerts`",
            #    "COUNT(CASE WHEN `vulnerabilities`.`severity` IN ('high', 'critical') THEN 1 END) AS `Critical or High Severity`",
            #    "COUNT(CASE WHEN `vulnerabilities`.`severity` IN ('high', 'critical') AND `vulnerable_version_ranges`.`fixed_in` IS NOT NULL THEN 1 END) AS `has:patch`",
            #    "COUNT(CASE WHEN `vulnerabilities`.`severity` IN ('high', 'critical') AND `vulnerable_version_ranges`.`fixed_in` IS NOT NULL AND `cve_epss`.`percentage` >= 0.01 THEN 1 END) AS `epss_percentage:>=0.01`"
            #  ]
            count_columns = [Arel.sql("COUNT(*) AS `Matching Alerts`")]
            category_conditions = []
            funnel_category_order.each do |category_name|
              # funnel_category_order may have untrusted user input, so use `fetch` which throws if someone's trying a SQL injection attack
              # that we somehow didn't protect against earlier... just because we're paranoid doesn't mean they're not out to get us.
              category_conditions << map_category_to_sql_conditional_fragment.fetch(category_name)
              # this is brittle since it uses the category name as the column name, but since we only use it in one place it's not worth adding an intermediate mapping
              count_columns << Arel.sql("COUNT(CASE WHEN #{Arel::Nodes::And.new(category_conditions).to_sql} THEN 1 END) AS `#{category_name}`")
            end

            counts = arel.select(count_columns).take

            # Since these are COUNT()'s, even if nothing matches, we intuitively expect 1 row of 0's to be returned.
            # However, due to https://stackoverflow.com/a/28399790/770425 ActiveRecord can send `WHERE 1=0` to the DB,
            # which will short-circuit the query and return no rows at all.
            # For example, counts will be nil rather than zeros when the user has no access to any repositories in the org.
            counts = Hash.new(0) if counts.nil?

            data = {
              label: "Matching Alerts",
              points: (["Matching Alerts"] + funnel_category_order).map { |category_name| { x: category_name, y: counts[category_name] } }
            }
          end

          log_timing(step: "render") do
            render_camelback_json(json: payload)
          end
        end

        # TODO: Implement or might change in the future
        sig { void }
        def alert_trends_by_status # rubocop:todo GitHub/UseRestfulActions
          payload = log_timing(step: "build payload") do
            # Return an empty payload for now
            { series: [] }
          end

          log_timing(step: "render") do
            render_camelback_json(json: payload[:series])
          end
        end

        # TODO: Implement or might change in the future
        sig { void }
        def alert_trends_by_severity # rubocop:todo GitHub/UseRestfulActions
          payload = log_timing(step: "build payload") do
            # Return an empty payload for now
            { series: [] }
          end

          log_timing(step: "render") do
            render_camelback_json(json: payload[:series])
          end
        end

        sig { void }
        def repositories # rubocop:todo GitHub/UseRestfulActions
          per_page   = 10
          cursor     = params[:cursor].to_i
          sort_field = params[:sort_field]&.to_sym || :countOpen
          sort_dir   = %w[asc desc].include?(params[:sort_direction]) ? params[:sort_direction] : "desc"

          payload = log_timing(step: "build repositories payload") do
            # Start with base query which accounts for customer‑supplied filters (FilterBar query string) then apply tile-specific conditions
            ungrouped_alert_query = filtered_alerts_relation.open
            # Force the joins so that the count queries can reference them
            base_arel = ungrouped_alert_query.resolve(ignore_pagination: true, ignore_sorting: true, force_vulnerabilities_join: true, force_epss_join: true)

            # Now tell MySQL to aggregate all of our metrics in one pass:
            aggregate_sql = <<~SQL.squish
                repository_vulnerability_alerts.repository_id,
                COUNT(*) AS count_open,
                COUNT(CASE WHEN vulnerabilities.severity = 'critical' THEN 1 END)   AS count_critical,
                COUNT(CASE WHEN vulnerabilities.severity = 'high'     THEN 1 END)   AS count_high,
                COUNT(CASE WHEN vulnerabilities.severity = 'moderate' THEN 1 END)   AS count_medium,
                COUNT(CASE WHEN vulnerabilities.severity = 'low'      THEN 1 END)   AS count_low,
                COUNT(CASE WHEN cve_epss.percentage     >= 0.01       THEN 1 END)   AS count_epss
              SQL

            # Map JSON‐side sortField to the SQL alias…
            sql_sort_column = {
              countOpen:     "count_open",
              countCritical: "count_critical",
              countHigh:     "count_high",
              countMedium:   "count_medium",
              countLow:      "count_low",
              countEPSS:     "count_epss"
            }[sort_field] || "count_open"

            # Fire off one single DB query that groups, orders, limits & offsets
            metrics = base_arel
              .select(Arel.sql(aggregate_sql))
              .group(RepositoryVulnerabilityAlert.arel_table[:repository_id])
              .order(Arel.sql("#{sql_sort_column} #{sort_dir.upcase}"))
              .limit(per_page + 1)
              .offset(cursor)
              .to_a

            has_next = metrics.size > per_page
            metrics  = metrics.first(per_page)

            repo_ids   = metrics.map(&:repository_id)
            repo_by_id = Repository.where(id: repo_ids).index_by(&:id)

            items = metrics.map do |m|
              repo = repo_by_id.fetch(m.repository_id)
              {
                id:            "#{this_organization.to_param}/#{repo.name}",
                displayName:   repo.name,
                href:          UrlHelpers.repository_alerts_path(repo.owner_display_login, repo),
                countOpen:     m.count_open.to_i,
                countEPSS:     m.count_epss.to_i,
                countCritical: m.count_critical.to_i,
                countHigh:     m.count_high.to_i,
                countMedium:   m.count_medium.to_i,
                countLow:      m.count_low.to_i,
                repo_id:       m.repository_id
              }
            end

            filtered_items = if allowed_repository_ids_for_organization_members
              allowed_ids = Array(allowed_repository_ids_for_organization_members&.first)
              items.select { |item| allowed_ids.include?(item[:repo_id]) }
            else
              items
            end

            {
              items:    filtered_items,
              previous: (cursor.zero? ? nil : [cursor - per_page, 0].max.to_s),
              next:     (has_next ? (cursor + per_page).to_s : nil)
            }
          end

          log_timing(step: "render repositories") do
            render_camelback_json(json: payload)
          end
        end

        private

        sig { void }
        def require_feature_flag
          render_404 unless ::SecurityCenter::FeatureFlagHelper.show_dependabot_alerts_vad?(current_user, this_organization)
        end

        sig { void }
        def feature_required
          render_404 unless ::SecurityCenter::SecurityFeatures.dependabot_metrics_enabled_for_instance?
        end

        sig { void }
        def security_center_required
          render_404 unless ::SecurityCenter::SecurityFeatures.security_center_available?(this_organization, dotcom_request_only: true)
        end

        sig { returns(::Search::Queries::SecurityCenter::QueryParser) }
        memoize def query
          ::Search::Queries::SecurityCenter::QueryParser.new(params.fetch(:query, ""))
        end

        sig { returns(T.nilable([T::Array[Integer], T::Boolean])) }
        memoize def allowed_repository_ids_for_organization_members
          return nil if can_view_all_alerts?
          allowed_repository_ids_by_feature_for_organization_members[::SecurityCenter::SecurityFeatures::DEPENDABOT_ALERTS]
        end

        sig { params(reason: T.any(String, T::Array[String]), last_state_change_push_id: T::Boolean).returns(Integer) }
        def closed_alerts_count(reason:, last_state_change_push_id:)
          # Start with base query which accounts for customer‑supplied filters (FilterBar query string) then apply tile-specific conditions
          ungrouped_alert_query = filtered_alerts_relation.closed
          arel = ungrouped_alert_query.resolve(ignore_pagination: true, ignore_sorting: true)

          arel.where(last_state_change_reason: reason)
           # Surprisingly, when merging Dependabot PR closes an alert, the `last_state_change_push_id` remains `nil`
           # TODO: cleanup `last_state_change_push_id` param confusingly maps `true` to `nil`
           .then { |query| last_state_change_push_id ? query.where(last_state_change_push_id: nil) : query.where.not(last_state_change_push_id: nil) }
           .count
        end

        sig { returns(String) }
        def unmodified_query
          params.fetch(:query, DEFAULT_QUERY)
        end

        # Dependabot Alerts UngroupedAlertsQueries support most parameters with the exception of
        # `:archived` - which is a property of the repository, not the alert.
        # So we filter out the `:archived` qualifier and pass it to the
        # SecurityOverviewAnalytics db to calculate the allowed_repository_ids
        sig { returns([String, String]) }
        def partition_query
          alert_filters, repo_filters = unmodified_query.split(/,\s+|\s+/).partition do |s|
            UngroupedAlertQueryFilterOptions.include?(s.split(":").first&.to_sym)
          end.map { |filter| filter.join(" ") }

          [
            alert_filters.presence || "",
            repo_filters.presence || ""
          ]
        end

        sig { returns(RepositoryVulnerabilityAlert::UngroupedAlertQuery) }
        def filtered_alerts_relation
          # This will not return any repo IDs if it receives a query it cannot parse
          alerts_query_string, repositories_query_string = partition_query

          repositories_query_parser = ::Search::Queries::SecurityCenter::CoverageQueryParser.new(
            repositories_query_string
          )
          repositories_query = SecurityCenterCoverageListDataQuery.for_organization(
            organization: this_organization,
            user: current_user,
            parser: repositories_query_parser,
          )

          repo_ids = Set.new(repositories_query.all.pluck(:repository_id))
          # For org-member permissions
          repo_ids.merge(Array(allowed_repository_ids_for_organization_members&.first))

          ungrouped_alerts_query_base = UngroupedAlertQuery.new(
            organization: this_organization,
            user: current_user,
            allowed_repository_ids: repo_ids.to_a,
          )

          alerts_query_hash = Search::Queries::SecurityCenter::DependabotAlertsQuery.parse_and_normalize(
            alerts_query_string,
            can_sort_by_most_important: true
          ).slice(*Search::Queries::SecurityCenter::DependabotAlertsQuery::QUALIFIERS) # Remove any invalid qualifiers

          ungrouped_alerts_query_base.
            resolutions_are(alerts_query_hash[:resolution]).resolutions_are_not(alerts_query_hash[:"-resolution"]).
            severities_are(alerts_query_hash[:severity]).severities_are_not(alerts_query_hash[:"-severity"]).
            manifests_are(alerts_query_hash[:manifest]).manifests_are_not(alerts_query_hash[:"-manifest"]).
            packages_are(alerts_query_hash[:package]).packages_are_not(alerts_query_hash[:"-package"]).
            ecosystems_are(alerts_query_hash[:ecosystem]).ecosystems_are_not(alerts_query_hash[:"-ecosystem"]).
            dependency_scopes_are(alerts_query_hash[:scope]).negated_dependency_scopes_are(alerts_query_hash[:"-scope"]).
            dependency_relationships_are(alerts_query_hash[:relationship]).negated_dependency_relationships_are(alerts_query_hash[:"-relationship"]).
            has_a(alerts_query_hash[:has]).has_none(alerts_query_hash[:"-has"]).
            search(alerts_query_hash[:phrase]).
            epss_percentages_are(alerts_query_hash[:epss_percentage]).epss_percentages_are_not(alerts_query_hash[:"-epss_percentage"]).
            repository_names_are(alerts_query_hash[:repo]).repository_names_are_not(alerts_query_hash[:"-repo"]).
            teams_are(alerts_query_hash[:team]).teams_are_not(alerts_query_hash[:"-team"]).
            topics_are(alerts_query_hash[:topic]).topics_are_not(alerts_query_hash[:"-topic"])
        end

        depends_on_clusters \
          ApplicationRecord::Collab,
          ApplicationRecord::Configurations,
          ApplicationRecord::IamAbilities,
          ApplicationRecord::Mysql1,
          ApplicationRecord::Notify,
          ApplicationRecord::Repositories,
          only: [:index]

        depends_on_clusters \
          ApplicationRecord::Billing,
          ApplicationRecord::Copilot,
          ApplicationRecord::Iam,
          ApplicationRecord::Mysql2,
          ApplicationRecord::Mysql5,
          ApplicationRecord::NotificationsEntries,
          ApplicationRecord::SecurityOverviewAnalytics,
          only: [:index],
          optional: true

        depends_on_clusters \
          ApplicationRecord::Collab,
          ApplicationRecord::Configurations,
          ApplicationRecord::Iam,
          ApplicationRecord::IamAbilities,
          ApplicationRecord::Mysql1,
          ApplicationRecord::Notify,
          ApplicationRecord::Repositories,
          ApplicationRecord::SecurityOverviewAnalytics,
          ApplicationRecord::Mysql2,
          ApplicationRecord::NotificationsEntries,
          only: [
            :alerts_fixed,
            :alerts_funnel,
            :alert_trends_by_status,
            :alert_trends_by_severity,
            :repositories,
          ]

        instrument_method \
          :index,
          :alerts_fixed,
          :alerts_funnel,
          :alert_trends_by_status,
          :alert_trends_by_severity,
          :repositories
      end
    end
  end
end
