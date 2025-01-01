# typed: strict
# frozen_string_literal: true

module Orgs
  module SecurityCenter
    module Metrics
      class EnablementTrendsController < AbstractSecurityCenterController
        include ApplicationHelper
        include ::SecurityCenter::DateSpanControllerHelper

        # Access
        before_action :organization_read_required
        before_action :security_center_required

        # Validation
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
              actor: current_user,
              scope: this_organization,
            )

            {
              initial_query: params.key?(:query) ? query.to_s : nil,
              initial_date_span:,
              watermark_date:,
              feedback_link: {
                text: feedback.text,
                url: feedback.url,
              },
              show_incomplete_data_warning: allowed_repos_capped?,
              incomplete_data_warning_doc_href: ::SecurityCenter::LimitedRepoWarningComponent::PERMISSIONS_DOC_HREF,
              custom_properties: ::SecurityCenter::Helpers::CustomProperties.new(org: this_organization, user: current_user).definitions_for_frontend,
            }.to_camelback_keys
          end

          data = log_timing(step: "build locals") do
            {
              backfill_in_progress: this_organization.trigger_security_center_reconciliation,
              selected_tab: :adoption_report,
            }
          end

          log_timing(step: "render") do
            render_react_app(
              app_name: "security-center",
              disable_ssr: true,
              payload:,
              title: "Security · Metrics · Enablement Trends · #{this_organization.display_login}",
              layout: "layouts/security_center/with_sidebar",
              page_data: { data: },
              app_payload_generator: -> do
                { enabled_features: {} }
              end,
            )
          end
        end

        sig { void }
        def enablement_trends # rubocop:todo GitHub/UseRestfulActions
          unless repos_filterer.any_feature_repo_metadata_rel.exists?
            return render_camelback_json(json: { no_data: "No repositories found" })
          end

          trend_data = log_timing(step: "build payload") do
            ::SecurityOverviewAnalytics::Dashboards::EnablementTrends::Queries::EnablementTrendsChart.new(
              scope: this_organization,
              start_date: T.must(start_date),
              end_date: T.must(end_date),
              repos_filterer:,
            )
            .perform
          end

          log_timing(step: "render") do
            # explicitly invoking `serialize` here to get a hash that can be camelized
            render_camelback_json(json: { trend_data: trend_data.map(&:serialize) })
          end
        end

        private

        sig { returns([Organization, User]) }
        def feature_flag_actors
          [this_organization, current_user]
        end

        # A watermark date indicates the earliest date for when we have data.
        # We performed an initial onboarding of feature status revisions on 2023-10-08.
        # However, to give users a sensible start, we're opting to set the watermark for 2024-01-01
        sig { override.returns(T.nilable(Date)) }
        def watermark_date
          ::Date.new(2024, 1, 1).to_time.utc.to_date
        end

        sig { returns(::Search::Queries::SecurityCenter::QueryParser) }
        memoize def query
          ::Search::Queries::SecurityCenter::QueryParser.new(params.fetch(:query, ""))
        end

        sig { returns(T::Boolean) }
        def allowed_repos_capped?
          adminable_repo_ids.last
        end

        sig { returns(::SecurityOverviewAnalytics::Dashboards::OrgReposFilterer) }
        def repos_filterer
          # Viewing feature enablement is an all-or-nothing permission, requiring
          # org owner, security manager, or repo admin.
          allowed_repo_ids, _ = adminable_repo_ids

          # We need a hash to satisfy the contract of the filterer,
          # but it will just concat the .values arrays.
          allowed_repo_ids_by_feature = if allowed_repo_ids.present?
            { all: allowed_repo_ids }
          end

          ::SecurityOverviewAnalytics::Dashboards::OrgReposFilterer
            .new(
              allowed_repo_ids_by_feature:,
              organization: this_organization,
              query:,
              user: current_user,
              user_session:
            )
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
          only: [:index]

        depends_on_clusters \
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
          only: [:enablement_trends]

        depends_on_clusters \
          ApplicationRecord::Copilot,
          ApplicationRecord::SecurityOverviewAnalytics,
          only: [
            :index,
            :enablement_trends,
          ],
          optional: true

        instrument_method \
          :allowed_repo_ids,
          :index,
          :enablement_trends
      end
    end
  end
end
