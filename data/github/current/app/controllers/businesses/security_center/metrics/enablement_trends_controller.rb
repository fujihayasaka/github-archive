# typed: strict
# frozen_string_literal: true

module Businesses
  module SecurityCenter
    module Metrics
      class EnablementTrendsController < Businesses::SecurityCenter::AbstractSecurityCenterController
        include ::SecurityCenter::DateSpanControllerHelper

        # Access
        before_action :security_center_required

        # Validation
        before_action :ensure_dates, except: [:index]

        # Reconciliation
        after_action :ensure_security_center_reconciliation, only: [:index]
        after_action :trigger_security_overview_analytics_backfill, only: [:index]

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
              allow_owner_type_filtering: can_see_personal_repos?,
            }.to_camelback_keys
          end

          app_payload_generator = log_timing(step: "build app payload") do
            if show_blankslate
              blankslate_app_payload_generator(
                heading: "Enablement trends",
                subheading: "Trends of security feature enablement across your enterprise.",
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
              title: "Security · Metrics · Enablement Trends · #{this_business}",
              page_data: { selected_link: :business_security_center_metrics_enablement, sidebar: :code_security },
              app_payload_generator:,
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
              scope: this_business,
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

        sig { override.returns(Symbol) }
        def authorized_orgs_actions
          :manage_security_products
        end

        sig { returns([Business, User]) }
        memoize def feature_flag_actors
          [this_business, current_user]
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

        sig { returns(::SecurityOverviewAnalytics::Dashboards::EnterpriseReposFilterer) }
        def repos_filterer
          ::SecurityOverviewAnalytics::Dashboards::EnterpriseReposFilterer
            .new(
              business: this_business,
              organizations: authorized_orgs,
              query:,
              user: current_user
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
          only: [
            :index,
            :enablement_trends,
          ],
          optional: true

        depends_on_clusters \
          ApplicationRecord::SecurityOverviewAnalytics,
          only: [:index],
          optional: true

        instrument_method \
          :allowed_repo_ids,
          :index,
          :enablement_trends
      end
    end
  end
end
