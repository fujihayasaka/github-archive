# typed: strict
# frozen_string_literal: true

module SecurityOverviewAnalytics
  module Dashboards
    module CodeScanningMetrics
      module Queries
        class AbstractQuery
          extend T::Helpers

          abstract!

          sig do
            params(
              business: ::Business,
              organizations: T::Array[Organization],
              user: ::User,
              query: ::Search::Queries::SecurityCenter::QueryParser,
              start_date: ::Date,
              end_date: ::Date,
            ).returns(T.attached_class)
          end
          def self.for_business(business:, organizations:, user:, query:, start_date:, end_date:)
            new(
              scope: business,
              user:,
              repos_filterer: EnterpriseReposFilterer.new(
                business:,
                organizations:,
                user:,
                query:,
              ),
              alerts_filterer: PullRequestAlertsFilterer.new(query),
              start_date:,
              end_date:,
            )
          end

          sig do
            params(
              organization: ::Organization,
              allowed_repo_ids: T.nilable(T::Array[Integer]),
              user: ::User,
              user_session: ::UserSession,
              query: ::Search::Queries::SecurityCenter::QueryParser,
              start_date: ::Date,
              end_date: ::Date,
            ).returns(T.attached_class)
          end
          def self.for_organization(organization:, allowed_repo_ids:, user:, user_session:, query:, start_date:, end_date:)
            new(
              scope: organization,
              user:,
              repos_filterer: OrgReposFilterer.new(
                organization:,
                allowed_repo_ids_by_feature: \
                  unless allowed_repo_ids.nil?
                    { ::SecurityCenter::SecurityFeatures::CODE_SCANNING => allowed_repo_ids }
                  end,
                user:,
                user_session:,
                query:,
              ),
              alerts_filterer: PullRequestAlertsFilterer.new(query),
              start_date:,
              end_date:,
            )
          end

          private_class_method :new

          sig do
            params(
              scope: T.any(::Business, ::Organization),
              user: ::User,
              repos_filterer: ReposFilterer,
              alerts_filterer: PullRequestAlertsFilterer,
              start_date: ::Date,
              end_date: ::Date,
            ).void
          end
          def initialize(scope:, user:, repos_filterer:, alerts_filterer:, start_date:, end_date:)
            @repos_filterer = repos_filterer
            @alerts_filterer = alerts_filterer
            @start_date = start_date
            @end_date = end_date
          end

          private

          sig { params(n: Integer, d: Integer).returns(Float) }
          def percentage(n, d)
            return 0.0 if d.zero?
            ((n * 100) / d.to_f).truncate(2).to_f
          end
        end
      end
    end
  end
end
