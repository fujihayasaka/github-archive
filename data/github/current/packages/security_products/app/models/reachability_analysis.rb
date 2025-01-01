# typed: true
# frozen_string_literal: true

class ReachabilityAnalysis < ApplicationRecord::Notify
  include ::Repositories::BelongsToRepository
  flagged_belongs_to_repository_via_domain
  destroy_in_background_with :repository

  has_many :status_updates, class_name: "ReachabilityAnalysisStatusUpdate", dependent: :destroy

  enum :state, {
    requested: 0,
    enqueued: 1,
    running: 2,
    completed: 3,
    incomplete: 4,
    failed: 5,
  }

  validates :repository, presence: true
  validates :sha, presence: true, length: { is: 40 }
  validate :no_other_active_run, on: :create

  def no_other_active_run
    if ReachabilityAnalysis.for_repository_id(self.repository_id).unfinished.exists?
      errors.add(:repository, "already has an active reachability analysis")
    end
  end

  scope :for_repository_id, -> (repository_id) { where(repository_id:) }
  scope :finished, -> { where(state: %i{completed incomplete failed}) }
  scope :unfinished, -> { where.not(state: %i{completed incomplete failed}) }

  class InvalidStateTransition < StandardError; end

  def set_enqueued
    raise InvalidStateTransition.new("Cannot transition to enqueued from #{state}") unless state == "requested"
    update!(state: :enqueued)
  end

  def set_running
    raise InvalidStateTransition.new("Cannot transition to running from #{state}") unless state == "enqueued"
    update!(state: :running)
  end

  def set_completed
    raise InvalidStateTransition.new("Cannot transition to completed from #{state}") unless state == "running"
    update!(state: :completed)
  end

  def set_incomplete
    raise InvalidStateTransition.new("Cannot transition to incomplete from #{state}") unless state == "running"
    update!(state: :incomplete)
  end

  def set_failed
    update!(state: :failed)
  end
end
