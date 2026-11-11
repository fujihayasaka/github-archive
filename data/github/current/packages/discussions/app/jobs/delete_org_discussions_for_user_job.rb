# typed: true
# frozen_string_literal: true

class DeleteOrgDiscussionsForUserJob < ApplicationJob
  queue_as :delete_org_discussions_for_user

  retry_on_dirty_exit
  retry_on_recoverable_exceptions

  # Discard the job if the subject or author are deleted before the job runs
  discard_on ActiveRecord::RecordNotFound

  attr_reader :actor

  def perform(organization_id:, user_id:, actor_id:)
    @actor = User.find(actor_id)
    organization = Organization.find(organization_id)
    user = User.find(user_id)

    # Since repos and orgs are in a different cluster than discussions, it'll probably be best to
    # fetch all the author's discussions, get the repo ids from those discussions, and then
    # filter out repos whose owner isn't the current org

    org_repo_ids = organization.repositories.pluck(:id)

    # Load the discussions in batches to avoid doing too much work at once
    user.discussions.in_batches(of: 50).each_record do |authored_discussion|
      delete_discussion(authored_discussion) if org_repo_ids.include?(authored_discussion.repository_id)
    end
  end

  private

  def delete_discussion(discussion)
    with_write do
      DeletedDiscussion.throttle do
        DiscussionDeleter.new(discussion).delete(actor)
      end
    end
  end
end
