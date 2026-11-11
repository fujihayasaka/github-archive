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
              allowed_dependabot_qualifiers: UngroupedAlertQueryFilterOptions.map(&:to_s)
            }.deep_transform_keys { |key| key.to_s.camelize(:lower) }
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
        def alerts_closed_by_state # rubocop:todo GitHub/UseRestfulActions
          payload = log_timing(step: "build payload") do
            if metrics_from_elasticsearch?
              Scientist.run("dependabot_alerts_metrics_closed_by_state") do |experiment|
                experiment.use { closed_alerts_by_state_data_mysql }
                experiment.try { closed_alerts_by_state_data_es }
              end
            else
              closed_alerts_by_state_data_mysql
            end
          end

          log_timing(step: "render") do
            render_camelback_json(json: payload)
          end
        end

        sig { void }
        def alerts_funnel # rubocop:todo GitHub/UseRestfulActions
          payload = log_timing(step: "build payload") do
            # Setup and validate the funnel categories
            default_category_order = [
              "has:patch",
              "severity:critical,high",
              "epss_percentage:>=0.01"
            ]
            # Caller can specify a custom order for the categories
            funnel_category_order = params[:funnel_order].present? ? params[:funnel_order].split(" ") : default_category_order

            # Although a private API, this is still untrusted user input, so let's ensure no SQL injection attack
            unless funnel_category_order.all? { |v| default_category_order.include?(v) }
              render json: { error: "Invalid funnel category." }, status: :unprocessable_entity
              return
            end

            counts = if metrics_from_elasticsearch?
              Scientist.run("dependabot_alerts_metrics_alerts_funnel") do |experiment|
                experiment.use { alerts_funnel_data_mysql(funnel_category_order) }
                experiment.try { alerts_funnel_data_es(funnel_category_order) }
              end
            else
              alerts_funnel_data_mysql(funnel_category_order)
            end

            {
              label: "Matching alerts",
              points: (["Matching alerts"] + funnel_category_order).map { |category_name| { x: category_name, y: counts[category_name] } }
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
        def most_vulnerable_package # rubocop:todo GitHub/UseRestfulActions
          payload = log_timing(step: "build payload") do
            if metrics_from_elasticsearch?
              Scientist.run("dependabot_alerts_metrics_most_vulnerable_package") do |experiment|
                experiment.use { package_name_with_most_vulnerablilities_mysql }
                experiment.try { package_name_with_most_vulnerablilities_es }
              end
            else
              package_name_with_most_vulnerablilities_mysql
            end
          end
          log_timing(step: "render") do
            render_camelback_json(json: payload)
          end
        end

        sig { void }
        def repositories # rubocop:todo GitHub/UseRestfulActions
          per_page   = 10
          cursor     = params[:cursor].to_i
          sort_field = params[:sort_field]&.to_sym || :countOpen
          sort_dir   = %w[asc desc].include?(params[:sort_direction]) ? params[:sort_direction]&.to_sym : :desc

          payload = log_timing(step: "build repositories payload") do
            data = if metrics_from_elasticsearch?
              Scientist.run("dependabot_alerts_metrics_repositories_data") do |experiment|
                experiment.use { repositories_data_mysql(cursor: cursor, sort_by: sort_field, sort_dir: sort_dir, per_page: per_page) }
                experiment.try { repositories_data_es(cursor: cursor, sort_by: sort_field, sort_dir: sort_dir, per_page: per_page) }
              end
            else
              repositories_data_mysql(cursor: cursor, sort_by: sort_field, sort_dir: sort_dir, per_page: per_page)
            end

            has_next = data.size > per_page
            items  = data.take(per_page)

            {
              items:    items,
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
        def feature_required
          render_404 unless ::SecurityCenter::SecurityFeatures.dependabot_metrics_enabled_for_instance?
        end

        sig { returns(String) }
        memoize def query
          ::Search::Queries::SecurityCenter::DependabotAlertsQuery.canonicalize(params.fetch(:query, ""))
        end

        sig { returns(T.nilable([T::Array[Integer], T::Boolean])) }
        memoize def allowed_repository_ids_for_organization_members
          return nil if can_view_all_alerts?
          allowed_repository_ids_by_feature_for_organization_members[::SecurityCenter::SecurityFeatures::DEPENDABOT_ALERTS]
        end

        sig { returns(String) }
        def unmodified_query
          params.fetch(:query, DEFAULT_QUERY)
        end

        # Dependabot Alerts UngroupedAlertsQueries support most parameters with the exception of
        # `:archived` - which is a property of the repository, not the alert.
        # So we filter out the `:archived` qualifier and pass it to the
        # SecurityOverviewAnalytics db to calculate the allowed_repository_ids
        # We partition the query by whether the key for each k:v pair in the query is a Dependabot Alert filter
        # The ListDataQuery can parse the remaining repository filters and handle errors related to invalid filters
        sig { returns([String, String]) }
        def partition_query
          alert_filters, repo_filters = unmodified_query.split(/,\s+|\s+/).partition do |s|
            UngroupedAlertQueryFilterOptions.any? do |qualifier|
              key = s.split(":").first&.delete_prefix("-")
              case qualifier
              when Symbol
                qualifier == key&.to_sym
              when Regexp
                qualifier.match?(key)
              else
                false
              end
            end
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

          # If the user can view code_scanning, secret scanning, and dependabot alerts
          allowed_repo_ids = if can_view_all_alerts?
            # Nil is a sentinel for all repositories
            nil
          else
            allowed_ids, _ = allowed_repository_ids_for_organization_members
            # The repositories query does not filter by user permissions
            # So the results include private repositories that the user does not have access to.
            # We need to intersect the resulting repo ids with allowed_repository_ids_for_organization_members
            # to ensure the user only sees repositories they have access to.
            Array(allowed_ids) & Array(repositories_query.all.pluck(:repository_id))
          end

          ungrouped_alerts_query_base = UngroupedAlertQuery.new(
            organization: this_organization,
            user: current_user,
            allowed_repository_ids: allowed_repo_ids,
          )

          alerts_query_hash = Search::Queries::SecurityCenter::DependabotAlertsQuery.parse_and_normalize(alerts_query_string)

          ungrouped_alerts_query_base.
            resolutions_are(alerts_query_hash[:resolution]).resolutions_are_not(alerts_query_hash[:"-resolution"]).
            severities_are(alerts_query_hash[:severity]).severities_are_not(alerts_query_hash[:"-severity"]).
            manifests_are(alerts_query_hash[:manifest]).manifests_are_not(alerts_query_hash[:"-manifest"]).
            packages_are(alerts_query_hash[:package]).packages_are_not(alerts_query_hash[:"-package"]).
            ecosystems_are(alerts_query_hash[:ecosystem]).ecosystems_are_not(alerts_query_hash[:"-ecosystem"]).
            dependency_scopes_are(alerts_query_hash[:scope]).negated_dependency_scopes_are(alerts_query_hash[:"-scope"]).
            dependency_relationships_are(alerts_query_hash[:relationship]).negated_dependency_relationships_are(alerts_query_hash[:"-relationship"]).
            visibility_scopes_are(alerts_query_hash[:vulnerability_scope]).
            has_a(alerts_query_hash[:has]).has_none(alerts_query_hash[:"-has"]).
            search(alerts_query_hash[:phrase]).
            epss_percentages_are(alerts_query_hash[:epss_percentage]).epss_percentages_are_not(alerts_query_hash[:"-epss_percentage"]).
            artifact_registry_urls_are(alerts_query_hash[:"artifact-registry-url"]).artifact_registry_urls_are_not(alerts_query_hash[:"-artifact-registry-url"]).
            artifact_registries_are(alerts_query_hash[:"artifact-registry"]).
            runtime_risks_are(alerts_query_hash[:"runtime-risk"]).
            repository_names_are(alerts_query_hash[:repo]).repository_names_are_not(alerts_query_hash[:"-repo"]).
            teams_are(alerts_query_hash[:team]).teams_are_not(alerts_query_hash[:"-team"]).
            topics_are(alerts_query_hash[:topic]).topics_are_not(alerts_query_hash[:"-topic"]).
            custom_properties_are(Search::Queries::SecurityCenter::DependabotAlertsQuery.custom_properties_string(alerts_query_hash))
        end

        sig { returns(T::Hash[Symbol, T.untyped]) }
        def package_name_with_most_vulnerablilities_mysql
          filtered_alerts_relation.open.package_name_with_most_vulnerablilities
        end

        sig { returns(T::Hash[Symbol, T.untyped]) }
        def package_name_with_most_vulnerablilities_es
          query = elasticsearch_aggregations_query(is: :open)
          query.most_vulnerable_package
        end

        sig { returns(T::Hash[Symbol, T.untyped]) }
        def closed_alerts_by_state_data_mysql
          # Start with base query which accounts for customer‑supplied filters (FilterBar query string) then apply tile-specific conditions
          ungrouped_alert_query = filtered_alerts_relation.closed
          ungrouped_alert_query.closed_alerts_by_state
        end

        sig { returns(T::Hash[Symbol, T.untyped]) }
        def closed_alerts_by_state_data_es
          query = elasticsearch_aggregations_query(is: :closed)
          query.closed_alerts_by_state
        end

        sig { params(funnel_category_order: T::Array[String]).returns(T::Hash[String, Integer])  }
        def alerts_funnel_data_mysql(funnel_category_order)
          # Start with base query which accounts for customer‑supplied filters (FilterBar query string) then apply tile-specific conditions
          ungrouped_alert_query = filtered_alerts_relation.open
          ungrouped_alert_query.alerts_funnel_data(funnel_category_order)
        end

        sig { params(funnel_category_order: T::Array[String]).returns(T::Hash[String, Integer]) }
        def alerts_funnel_data_es(funnel_category_order)
          query = elasticsearch_aggregations_query(is: :open)
          query.alerts_funnel_data(funnel_category_order)
        end

        sig do
          params(
            cursor: Integer,
            sort_by: Symbol,
            sort_dir: Symbol,
            per_page: Integer
          ).returns(T::Array[T::Hash[Symbol, T.untyped]])
        end
        def repositories_data_mysql(cursor:, sort_by:, sort_dir:, per_page:)
          # Start with base query which accounts for customer‑supplied filters (FilterBar query string) then apply tile-specific conditions
          filtered_alerts_relation.open.repositories_data(
            cursor: cursor,
            sort_by: sort_by,
            sort_dir: sort_dir,
            per_page: per_page
          )
        end

        sig do
          params(
            cursor: Integer,
            sort_by: Symbol,
            sort_dir: Symbol,
            per_page: Integer
          ).returns(T::Array[T::Hash[Symbol, T.untyped]])
        end
        def repositories_data_es(cursor:, sort_by:, sort_dir:, per_page:)
          query = elasticsearch_aggregations_query(is: :open)
          query.repositories_data(cursor: cursor, sort_by: sort_by, sort_dir: sort_dir, per_page: per_page)
        end

        sig { params(qualifiers: T.untyped).returns(Search::Queries::DependabotAlertsAggregationsQuery) }
        def elasticsearch_aggregations_query(**qualifiers)
          extra_query_phrase = qualifiers.map { |k, v| "#{k}:#{Array(v).join(",")}" }.compact.join(" ")
          query = Search::Queries::DependabotAlertsAggregationsQuery.new(
            phrase: "#{unmodified_query} #{extra_query_phrase}".strip,
            scope: this_organization,
            current_user: current_user,
            cap_filter: cap_filter
          )
        end

        sig { returns(T::Boolean) }
        memoize def metrics_from_elasticsearch?
          return false unless GitHub.dependabot_es_search_enabled?

          actors = [current_user, this_organization]
          FeatureFlag.vexi.enabled?(:dependabot_alerts_metrics_from_es, *actors, default: false)
        end

        depends_on_clusters \
          ApplicationRecord::ArtifactRegistry,
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
          ApplicationRecord::ArtifactRegistry,
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
            :alerts_closed_by_state,
            :alerts_funnel,
            :alert_trends_by_status,
            :alert_trends_by_severity,
            :repositories,
            :most_vulnerable_package,
          ]

        instrument_method \
          :index,
          :alerts_closed_by_state,
          :alerts_funnel,
          :alert_trends_by_status,
          :alert_trends_by_severity,
          :repositories,
          :most_vulnerable_package
      end
    end
  end
end
