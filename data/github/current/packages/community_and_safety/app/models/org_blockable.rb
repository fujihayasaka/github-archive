# typed: false
# frozen_string_literal: true

# Mixin for repo owned content: Issues, IssueComments, PullRequests, PullRequestReviews, PullRequestReviewComments, CommitComments
# for allowing users to be blocked from an org from these issues
module OrgBlockable

  # Check if the viewer can block the creator of this content from the organization
  # Returns a boolean
  def async_viewer_can_block_from_org?(viewer)
    return Promise.resolve(false) unless viewer

    self.async_user.then do |user|
      next false unless user
      next false if user == viewer
      self.async_repository.then do |repo|
        repo.async_owner.then do |owner|
          next false unless owner.is_a? Organization
          user.async_blocked_by?(owner).then do |blocked|
            next false if blocked

            owner.async_member?(user).then do |is_member|
              next false if is_member
              owner.async_blocked_users_manageable_by?(viewer)
            end
          end
        end
      end
    end
  end

  def viewer_can_block_from_org?(viewer)
    async_viewer_can_block_from_org?(viewer).sync
  end

  # Checks if a viewer can unblock the creator of this content from this organization
  # Returns a boolean
  def async_viewer_can_unblock_from_org?(viewer)
    return Promise.resolve(false) unless viewer

    self.async_user.then do |user|
      next false unless user
      next false if user == viewer
      self.async_repository.then do |repo|
        repo.async_owner.then do |owner|
          next false unless owner.is_a? Organization
          user.async_blocked_by?(owner).then do |blocked|
            next false unless blocked
            owner.async_blocked_users_manageable_by?(viewer)
          end
        end
      end
    end
  end

  def viewer_can_unblock_from_org?(viewer)
    async_viewer_can_unblock_from_org?(viewer).sync
  end
end
