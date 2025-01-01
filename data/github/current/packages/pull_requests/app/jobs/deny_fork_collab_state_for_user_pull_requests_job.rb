# typed: true
# frozen_string_literal: true

class DenyForkCollabStateForUserPullRequestsJob < ApplicationJob
  queue_as :deny_fork_collab_state

  exempt_from_tenant_context_requirement

  def perform(user_id:, resource_id:, resource_class:, resource_ids: nil)
    user = User.find_by(id: user_id)
    return unless user

    use_bulk_organizations = resource_class == "Organization" && !resource_ids.nil?
    head_repo_ids = if use_bulk_organizations
      Organization.where(id: resource_ids).map(&:repository_ids).flatten
    else
      repository_ids(resource_id, resource_class)
    end

    pull_requests = user.pull_requests.where(head_repository: head_repo_ids, fork_collab_state: :allowed)

    pull_requests.find_in_batches do |pull_requests_batch|
      pushable_statuses = Promise.all(pull_requests_batch.map { |pull_request| pull_request.async_head_repository_pushable_by?(user) }).sync

      update_ids = pull_requests_batch.each_with_index.map do |pull_request, index|
        next if pushable_statuses[index]

        pull_request.id
      end.compact

      # Skip callbacks so this is less likely to fail - if we don't clear this state it could grant unauthorized access.
      with_write do
        PullRequest.throttle do
          PullRequest.where(id: update_ids).update_all(fork_collab_state: :denied)
        end
      end
    end
  end

  def repository_ids(resource_id, resource_class)
    case resource_class
    when "Team"
      Team.find(resource_id).repository_ids
    when "BusinessTeam"
      BusinessTeam.find(resource_id).repository_ids
    when "Organization"
      Organization.find(resource_id).repositories.pluck(Arel.sql("/*vt+ IGNORE_MAX_MEMORY_ROWS=1 */ id"))
    when "Repository"
      [resource_id]
    else
      raise "Invalid Type"
    end
  end
end
