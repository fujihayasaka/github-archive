# typed: false
# frozen_string_literal: true

module Newsies
  class AutoSubscribeUsersToRepositoryJob < ApplicationJob
    class AutoSubscribeUsersToRepositoryError < StandardError; end

    use_primaries ApplicationRecord::Mysql2

    queue_as :notifications

    retry_on_dirty_exit

    retry_on AutoSubscribeUsersToRepositoryError, wait: :polynomially_longer

    BATCH_SIZE = 100

    resolve_tenant_context do |repo_id|
      Repositories::Public.resolve_tenant(id: repo_id)
    end

    def perform(repo_id, user_ids, repository_creator_id = nil)
      return if user_ids.empty?
      return unless repo = find_repository(repo_id)

      GitHub.tracer.in_span("auto_subscribe_all", kind: :internal, attributes: { "gh.notifications.auto_subscribe_all.user.count" => user_ids.size }) do
        user_ids.each_slice(BATCH_SIZE) do |slice|
          users = User.where(id: slice.flatten.compact)
          users.each do |user|
            notify = !repository_creator_id || repository_creator_id != user.id

            auto_subscribe_to_own_repos = repo.owner_id == user.id
            # Throttling on Domain::Notifications because auto_subscribe writes
            # using the ListSubscription and ThreadTypeSubscription models which
            # belong to the Notifications domain.
            response = GitHub.tracer.in_span("auto_subscribe_individual", kind: :internal, attributes: { "gh.user.id" => user.id, "gh.repo.id" => repo.id }) do
              ApplicationRecord::Domain::Notifications.throttle { GitHub.newsies.auto_subscribe(user, repo, notify, auto_subscribe_to_own_repos) }
            end
            raise AutoSubscribeUsersToRepositoryError unless response.success?
          end
        end
      end
    end

    private

    def find_repository(repo_id)
      repo = Repository.find_by_id(repo_id)
      if repo.present?
        GitHub.dogstats.increment("auto_subscribe_users_to_repository_job.repo_found_replica")
        return repo
      end
      GitHub.dogstats.increment("auto_subscribe_users_to_repository_job.repo_missing_replica")

      # If the repo is not found on a replica, fallback to a primary and also log how often this occurs
      repo = with_write { Repository.find_by_id(repo_id) }
      if repo.nil?
        GitHub.dogstats.increment("auto_subscribe_users_to_repository_job.repo_missing_primary")
      else
        GitHub.dogstats.increment("auto_subscribe_users_to_repository_job.repo_found_primary")
      end
      repo
    end
  end
end
