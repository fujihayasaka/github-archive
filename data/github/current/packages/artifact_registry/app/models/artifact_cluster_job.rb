# typed: strict
# frozen_string_literal: true

class ArtifactClusterJob < ApplicationRecord::Domain::ArtifactRegistry
  belongs_to :owner, class_name: "Organization"

  STATUSES = %w[pending processing completed failed].freeze
  ERROR_CAUSES = %w[job_failure repo_no_longer_owned].freeze
  STALE_JOB_THRESHOLD = T.let(1.hour, ActiveSupport::Duration)

  validates :cluster, presence: true, length: { maximum: 128 }
  validates :logical_environment, presence: true, length: { maximum: 128 }
  validates :physical_environment, length: { maximum: 128 }
  validates :status, inclusion: { in: STATUSES }

  scope :for_cluster, ->(owner_id, cluster, logical_environment, physical_environment) {
    where(owner_id: owner_id, cluster: cluster, logical_environment: logical_environment, physical_environment: physical_environment)
  }

  sig { void }
  def mark_processing!
    update!(status: "processing", started_at: Time.current)
  end

  sig { params(count: Integer, job_errors: T.nilable(T::Array[T::Hash[String, T.untyped]])).void }
  def mark_completed!(count:, job_errors: nil)
    update!(status: "completed", total_count: count, job_errors: job_errors)
  end

  sig { params(error_message: String).void }
  def mark_failed!(error_message)
    update!(status: "failed", job_errors: [{ "cause" => "job_failure", "message" => error_message }])
  end
end
