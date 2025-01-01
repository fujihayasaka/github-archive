# typed: strict
# frozen_string_literal: true

class Actions::PinnedWorkflow < ApplicationRecord::Domain::RepositoriesActionsChecks
  belongs_to :workflow, -> (pinned_workflow) { where(repository_id: pinned_workflow.repository_id) }, inverse_of: :pinned_workflow
  belongs_to :pinned_by, class_name: "User"
  validate :validate_limit, on: :create
  MAXIMUM_PINNED_WORKFLOWS = 5

  sig { params(repository: Repository, user: T.nilable(User)).returns(T::Boolean) }
  def self.allow_pinning?(repository, user)
    Actions::PinnedWorkflow.user_can_pin_workflows?(repository, user)
  end

  sig { params(repository_id: Integer).returns(T::Boolean) }
  def self.limit_reached?(repository_id)
    Actions::PinnedWorkflow.where(repository_id: repository_id).count >= MAXIMUM_PINNED_WORKFLOWS
  end

  sig { params(repository: Repository, user: T.nilable(User)).returns(T::Boolean) }
  def self.user_can_pin_workflows?(repository, user)
    return false unless user
    repository.writable_by?(user)
  end

  private

  sig { void }
  def validate_limit
    if Actions::PinnedWorkflow.limit_reached?(repository_id)
      errors.add(:repository, "has reached maximum number of pinned workflows")
    end
  end
end
