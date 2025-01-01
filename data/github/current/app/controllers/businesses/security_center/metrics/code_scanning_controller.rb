# typed: strict
# frozen_string_literal: true

module Businesses
  module SecurityCenter
    module Metrics
      class CodeScanningController < Businesses::SecurityCenter::AbstractSecurityCenterController
        include ::SecurityCenter::DateSpanControllerHelper

        # Access
        before_action :feature_required
        before_action :security_center_required

        # Validation
        before_action :ensure_dates, except: [:index]

        # Reconciliation
        after_action :ensure_security_center_reconciliation, only: [:index]
        after_action :trigger_security_overview_analytics_backfill, only: [:index]

        Queries = SecurityOverviewAnalytics::Dashboards::CodeScanningMetrics::Queries

        sig { void }
        def index
          payload = log_timing(step: "build React payload") do
            feedback = ::SecurityCenter::FeedbackLink.new(
              actor: current_user,
              scope: this_business,
            )

            {
              initial_query: params.key?(:query) ? query.to_s : nil,
              initial_date_span:,
              watermark_date:,
              feedback_link: {
                text: feedback.text,
                url: feedback.url,
              },
              export_error_message: flash[:export_error],
              allow_autofix_features: CodeScanning::Autofix.any_allowed_by_business?(this_business),
              allow_csv_export: GitHub.dotcom_request?,
              allow_owner_type_filtering: false, # experience is code scanning only, no EMU support
              allow_autofix_remediation_time_tile: !GitHub.enterprise?,
            }.deep_transform_keys { |key| key.to_s.camelize(:lower) }
          end

          app_payload_generator = log_timing(step: "build app payload") do
            if show_blankslate
              blankslate_app_payload_generator(
                heading: "CodeQL pull request alerts",
                subheading: "A report of vulnerabilities prevented by CodeQL, caught in pull requests that have been merged to the default branch.",
                message: "No repositories to show.",
                description: blankslate_description,
                # TODO: Need a doc link
                # learn_more_link: {
                #   text: "Learn more about viewing the overview page.",
                #   url: "#",
                # },
              )
            else
              content_app_payload_generator
            end
          end

          log_timing(step: "render") do
            render_react_app(
              app_name: "security-center",
              disable_ssr: true,
              payload:,
              page_data: { selected_link: :business_code_scanning_metrics, sidebar: :code_security },
              title: "Security · Metrics · CodeQL Pull Request Alerts · #{this_business}",
              app_payload_generator:,
            )
          end
        end

        sig { void }
        def alerts_found # rubocop:todo GitHub/UseRestfulActions
          payload = log_timing(step: "build payload") do
            Queries::AlertsFoundQuery.for_business(
              business: this_business,
              organizations: authorized_orgs,
              user: current_user,
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
        def autofix_suggestions # rubocop:todo GitHub/UseRestfulActions
          payload = log_timing(step: "build payload") do
            Queries::AutofixSuggestionsQuery.for_business(
              business: this_business,
              organizations: authorized_orgs,
              user: current_user,
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
        def alerts_fixed # rubocop:todo GitHub/UseRestfulActions
          payload = log_timing(step: "build payload") do
            Queries::AlertsFixedQuery.for_business(
              business: this_business,
              organizations: authorized_orgs,
              user: current_user,
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
        def alert_trends_by_status # rubocop:todo GitHub/UseRestfulActions
          payload = log_timing(step: "build payload") do
            Queries::AlertTrendsQuery.for_business(
              business: this_business,
              organizations: authorized_orgs,
              user: current_user,
              query:,
              start_date: T.must(start_date),
              end_date: T.must(end_date),
            ).perform(group_by: Queries::AlertTrendsQuery::GroupOption::Status)
          end

          log_timing(step: "render") do
            render_camelback_json(json: payload.series.map(&:serialize))
          end
        end

        sig { void }
        def alert_trends_by_severity # rubocop:todo GitHub/UseRestfulActions
          payload = log_timing(step: "build payload") do
            Queries::AlertTrendsQuery.for_business(
              business: this_business,
              organizations: authorized_orgs,
              user: current_user,
              query:,
              start_date: T.must(start_date),
              end_date: T.must(end_date),
            ).perform(group_by: Queries::AlertTrendsQuery::GroupOption::Severity)
          end

          log_timing(step: "render") do
            render_camelback_json(json: payload.series.map(&:serialize))
          end
        end

        sig { void }
        def alerts_fixed_with_autofix # rubocop:todo GitHub/UseRestfulActions
          payload = log_timing(step: "build payload") do
            Queries::AlertsFixedWithAutofixQuery.for_business(
              business: this_business,
              organizations: authorized_orgs,
              user: current_user,
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
        def remediation_rates # rubocop:todo GitHub/UseRestfulActions
          payload = log_timing(step: "build payload") do
            Queries::RemediationRatesQuery.for_business(
              business: this_business,
              organizations: authorized_orgs,
              user: current_user,
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
        def remediation_time # rubocop:todo GitHub/UseRestfulActions
          render_404 and return if GitHub.enterprise?
          payload = log_timing(step: "build payload") do
            Queries::RemediationTimeQuery.for_business(
              business: this_business,
              organizations: authorized_orgs,
              user: current_user,
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
        def most_prevalent_rules # rubocop:todo GitHub/UseRestfulActions
          cursor = params.fetch(:cursor, "0")
          page_size = params.fetch(:page_size, 10).to_i

          payload = log_timing(step: "build payload") do
            Queries::MostPrevalentRulesQuery.for_business(
              business: this_business,
              organizations: authorized_orgs,
              user: current_user,
              query:,
              start_date: T.must(start_date),
              end_date: T.must(end_date),
            ).perform(
              cursor:,
              page_size:,
            )
          end

          log_timing(step: "render") do
            render_camelback_json(json: payload.serialize)
          end
        end

        sig { void }
        def repositories # rubocop:todo GitHub/UseRestfulActions
          cursor = params.fetch(:cursor, "0")
          sort_field = Queries::RepositoriesTableQuery::SortField.try_deserialize(params[:sort_field])
          sort_direction = Queries::RepositoriesTableQuery::SortDirection.try_deserialize(params[:sort_direction])

          payload = log_timing(step: "build payload") do
            Queries::RepositoriesTableQuery.for_business(
              business: this_business,
              organizations: authorized_orgs,
              user: current_user,
              query:,
              start_date: T.must(start_date),
              end_date: T.must(end_date),
            ).perform(
              cursor:,
              sort_field:,
              sort_direction:,
            )
          end

          log_timing(step: "render") do
            render_camelback_json(json: payload.serialize)
          end
        end

        private

        sig { override.returns(Symbol) }
        def authorized_orgs_actions
          :read_code_scanning
        end

        sig { void }
        def feature_required
          render_404 unless ::SecurityCenter::SecurityFeatures.code_scanning_enabled_for_instance?
        end

        sig { void }
        def security_center_required
          render_404 unless ::SecurityCenter::SecurityFeatures.security_center_available?(this_business, dotcom_request_only: true)
        end

        sig { returns([Business, User]) }
        memoize def feature_flag_actors
          [this_business, current_user]
        end

        sig { returns(::Search::Queries::SecurityCenter::QueryParser) }
        memoize def query
          ::Search::Queries::SecurityCenter::QueryParser.new(params.fetch(:query, ""))
        end

        depends_on_clusters \
          ApplicationRecord::Collab,
          ApplicationRecord::Configurations,
          ApplicationRecord::Iam,
          ApplicationRecord::IamAbilities,
          ApplicationRecord::Mysql1,
          ApplicationRecord::Repositories,
          only: [:index]

        depends_on_clusters \
          ApplicationRecord::Billing,
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
          ApplicationRecord::Repositories,
          ApplicationRecord::SecurityOverviewAnalytics,
          only: [
            :alert_trends_by_severity,
            :alert_trends_by_status,
            :alerts_fixed_with_autofix,
            :alerts_fixed,
            :alerts_found,
            :autofix_suggestions,
            :most_prevalent_rules,
            :remediation_rates,
            :remediation_time,
            :repositories,
          ]

        depends_on_clusters \
          ApplicationRecord::Copilot,
          only: [:index],
          optional: true

        instrument_method \
          :index,
          :alerts_found,
          :autofix_suggestions,
          :alerts_fixed,
          :alert_trends_by_status,
          :alert_trends_by_severity,
          :alerts_fixed_with_autofix,
          :remediation_rates,
          :remediation_time,
          :most_prevalent_rules,
          :repositories
      end
    end
  end
end
