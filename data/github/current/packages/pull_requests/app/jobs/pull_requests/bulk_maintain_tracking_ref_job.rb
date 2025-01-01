# typed: true
# frozen_string_literal: true

module PullRequests
  class BulkMaintainTrackingRefJob < ApplicationJob

    use_replicas ApplicationRecord::Configurations,
      ApplicationRecord::Collab,
      ApplicationRecord::IamAbilities,
      ApplicationRecord::IssuesPullRequests,
      ApplicationRecord::Mysql1,
      ApplicationRecord::Spokes,
      ApplicationRecord::Repositories

    retry_on_dirty_exit
    queue_as do
      _, named_args = T.unsafe(self).arguments

      if named_args && named_args[:importing]
        :maintain_tracking_ref_importing
      else
        :maintain_tracking_ref
      end
    end

    MAX_RETRIES = 10

    sig { params(repository_id: Integer, start: T.nilable(Integer), attempt: Integer, importing: T::Boolean).void }
    def perform(repository_id, start: nil, attempt: 0, importing: false)
      with_telemetry(repository_id, start:) do
        repository = if FeatureFlag.vexi.enabled?(:repos_domain_find_by, default: false)
          T.cast(Repositories.domain.by_id(repository_id), T.nilable(Repository)) # rubocop:todo GitHub/AvoidCast
        else
          Repository.find_by(id: repository_id)
        end

        if repository.nil?
          GitHub.logger.info({
            "gh.pull_requests.failure_reason": "repository_not_found"
          })

          return
        end

        repository.pull_requests.joins(:issue).in_batches(of: 50, start:) do |batch| # domain-isolation-query-violation:ignore:packages/issues (SELECT)
          commits = GitSystems::BatchReadCommits.new
          skipped = T.let([], T::Array[Integer])
          # In batches of has yielded identical records multiple times when observed in production.
          refs = T.let({}, T::Hash[String, String])

          # Loop over each pull request, validate the data, and add the request to the batch.
          pulls = batch.pluck(:id, :"issue.number", :head_sha).reject { _1.any?(&:blank?) } # domain-isolation-query-violation:ignore:packages/issues (SELECT)
          starting_id = T.let(pulls.dig(0, 0).to_i, Integer)

          pulls.each { |(_id, _number, head_sha)| commits.request(repository, head_sha) }

          # Execute the batch call.
          commits.execute

          # Loop each pull request, determine if the head_sha exists. There are scenarios when importing repositories,
          # `git gc`, or users force pushing with rewritten history that could cause a commit oid to not be found. Batch
          # ref updates will fail if any of the objects within the request do not exist.
          pulls.each do |(_id, number, head_sha)|
            if commits.read(repository, head_sha)
              refs["refs/pull/#{number}/head"] = head_sha
            else
              skipped << number
            end
          end

          if refs.any?
            begin
              repository.batch_write_refs(
                User.ghost,
                refs.map { |refname, sha| [refname, nil, sha] },
                no_custom_hooks: true,
                post_receive: false,
                priority: :low
              )
              if FeatureFlag.vexi.enabled?(:increment_push_stats_bulk_refs, repository, repository.owner, default: false)
                with_write { repository.network&.increment_pushed_counts }
              end
            rescue => exception # rubocop:disable Lint/RescueException
              Failbot.report(exception)

              if attempt > MAX_RETRIES
                GitHub.dogstats.increment("pull_requests.batch_maintain_tracking_ref.result", tags: ["outcome:failed"])
                # We're out of attempts, log and give up.
                GitHub.logger.info({
                  "gh.pull_requests.failure_reason": "failed",
                  "code.error": exception.class.name,
                  "code.message": exception.message,
                })

                ActiveSupport::Notifications.instrument("pull_requests.batch_maintain_tracking_ref.result", {
                  repository_id: repository_id,
                  result: "failed",
                  importing: importing,
                }) if repository.organization&.feature_flag_enabled?(:bulk_ref_notifications, default: false)
              else
                GitHub.dogstats.increment("pull_requests.batch_maintain_tracking_ref.result", tags: ["outcome:retried"])
                GitHub.logger.info({
                  "gh.pull_requests.failure_reason": "retrying",
                  "code.error": exception.class.name,
                  "code.message": exception.message,
                })

                # Wait a minute, and retry the current batch.
                self.class.set(wait: 1.minute).perform_later(
                  repository_id,
                  start: starting_id,
                  attempt: attempt + 1,
                  importing: importing
                )
              end

              # Exit from the job.
              return
            end
          end

          GitHub.dogstats.count("pull_requests.batch_maintain_tracking_ref.updated", refs.length)
          GitHub.dogstats.count("pull_requests.batch_maintain_tracking_ref.processed", pulls.size)

          GitHub.logger.info({
            "gh.pull_requests.tracking_refs": refs,
            "gh.pull_requests.skipped": skipped,
          })
        end

        GitHub.dogstats.increment("pull_requests.batch_maintain_tracking_ref.result", tags: ["outcome:success"])
        ActiveSupport::Notifications.instrument("pull_requests.batch_maintain_tracking_ref.result", {
          repository_id: repository_id,
          result: "success",
          importing: importing,
        }) if repository.organization&.feature_flag_enabled?(:bulk_ref_notifications, default: false)
      end
    end

    def with_telemetry(repository_id, start:, &block)
      Failbot.push({
        "gh.repo.id": repository_id,
        "arguments.start": start.inspect,
      })

      GitHub.logger.with_named_tags(
        "code.namespace": self.class.name,
        "code.function": "perform",
        "gh.repo.id": repository_id,
        "arguments.start": start.inspect,
        &block
      )
    end
  end
end
