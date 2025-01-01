# typed: true
# frozen_string_literal: true

class LastSeenPullRequestRevision < ApplicationRecord::Domain::IssuesPullRequests

  belongs_to :pull_request
  serialize :last_revision, coder: GitHub::Hex

  KEEP_NUM_REVS = 1

  before_create :set_repository_id # rubocop:todo GitHub/AvoidActiveRecordCallbacks

  scope :latest_for, -> (pull_request_id, user_id) {
    where(pull_request_id: pull_request_id, user_id: user_id).
      order("updated_at DESC")
  }

  def self.add_seen_rev(pull_request, user, head)
    # This ends up being called from controllers on GET so ensure
    # we can write at this point.
    ActiveRecord::Base.connected_to(role: :writing) do
      LastSeenPullRequestRevision.create!(
        pull_request_id: pull_request.id,
        user_id: user.id,
        last_revision: head,
      )

      prune_old_revs(pull_request, user)
    end
  end

  def self.prune_old_revs(pull_request, user)
    LastSeenPullRequestRevision.
      latest_for(pull_request.id, user.id).
      offset(KEEP_NUM_REVS).
      destroy_all
  end

  def self.clear(pull_request, user = nil)
    scope = where(pull_request_id: pull_request.id)
    scope = scope.where(user_id: user.id) if user
    scope.destroy_all
  end

  private

  def set_repository_id
    self.repository_id = self.pull_request&.repository_id
  end
end
