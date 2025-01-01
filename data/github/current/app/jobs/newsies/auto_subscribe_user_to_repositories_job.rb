# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

module Newsies
  class AutoSubscribeUserToRepositoriesJob < ApplicationJob
    queue_as :notifications

    BATCH_SIZE = 100

    class AutoSubscribeError < StandardError; end

    retry_on AutoSubscribeError, wait: :polynomially_longer
    retry_on_dirty_exit

    # Subscribes a User to a set of repositories, by calling GitHub.newsies.auto_subscribe.
    #
    #
    # user_id - A User id
    # repository_ids - An array of Repository ids. Could be just one.
    # notify - Boolean that determines if the user is notified.
    #
    def perform(user_id, repository_ids, notify = true)
      return if repository_ids.empty?
      return unless user = User.find_by(id: user_id)

      GitHub.tracer.in_span("auto_subscribe_all", kind: :internal, attributes: { "gh.user.id" => user.id, "gh.notifications.job.repo.count" => repository_ids.size }) do
        repository_ids.each_slice(BATCH_SIZE) do |slice|
          repos = Repository.where(id: slice.flatten.compact)

          repos.each do |repo|
            # Throttling on Domain::Notifications because auto_subscribe writes
            # using the ListSubscription and ThreadTypeSubscription models which
            # belong to the Notifications domain.
            response = GitHub.tracer.in_span("auto_subscribe_individual", kind: :internal, attributes: { "gh.user.id" => user.id, "gh.repo.id" => repo.id }) do
              with_write do
                ApplicationRecord::Domain::Notifications.throttle do
                  GitHub.newsies.auto_subscribe(user, repo, notify)
                end
              end
            end
            raise AutoSubscribeError unless response.success?
          end
        end
      end
    end
  end
end
