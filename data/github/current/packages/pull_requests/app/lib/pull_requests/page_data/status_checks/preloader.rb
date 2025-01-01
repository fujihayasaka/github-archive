# typed: strict
# frozen_string_literal: true

module PullRequests
  module PageData
    module StatusChecks
      class Preloader
        include PullRequests::External::Domain::StatusChecks::IPreloader

        sig { params(repository: T.nilable(Repositories::IRepository), avatar_size: Integer).void }
        def initialize(repository, avatar_size:)
          @repository = repository
          @avatar_size = avatar_size
        end

        sig { override.params(records: T::Enumerable[Status]).void }
        def preload_statuses(records)
          GitHub::PrefillAssociations.prefill_associations(
            records,
            [
              :creator,
              { oauth_application: [:user] },
            ],
          )

          oauth_apps = records.filter_map(&:oauth_application)
          Promise.all(
            oauth_apps.map { _1.async_preferred_avatar_url(size: @avatar_size) }
          ).sync
        end

        sig { override.params(records: T::Enumerable[CombinedStatus::CheckRunAdapter]).void }
        def preload_check_runs(records)
          # PrefillAssociations doesn't work through a SimpleDelegator
          check_runs = records.map(&:__getobj__)

          GitHub::PrefillAssociations.prefill_associations(
            check_runs,
            [
              :workflow_job_run,
              :repository,
              {
                check_suite: [
                  :workflow_run,
                  { github_app: :bot },
                ],
              },
            ],
            available_records: [@repository].compact,
          )

          bots = check_runs.filter_map { _1.check_suite&.github_app&.bot }
          Promise.all(bots.map(&:async_primary_avatar_path)).sync
        end
      end
    end
  end
end
