# typed: strict
# frozen_string_literal: true

module Copilot
  class CompletionFeedback < ApplicationRecord::Copilot

    self.table_name = "copilot_completion_feedback"

    enum :sentiment, %i(neutral positive negative)

    class Classification
      EMPTY = "empty"
      SUMMARY_INACCURATE = "summary_inaccurate"
      SUMMARY_HARMFUL = "summary_harmful"
      UI_BUG = "ui_bug"
      OTHER = "other"
    end

    enum :classification, {
      Classification::EMPTY => 0,
      Classification::SUMMARY_INACCURATE => 2,
      Classification::SUMMARY_HARMFUL => 3,
      Classification::UI_BUG => 4,
      Classification::OTHER => 5
    }

    serialize :context, type: Hash

    include ::Repositories::BelongsToRepository
    belongs_to_repository_via_domain legacy_return_type: true
    belongs_to :user, class_name: "::User"

    validates :repository_id, presence: true
    validates :user_id, presence: true
    validates :job_id, presence: true, unless: ->(feedback) { feedback.session_id.present? }
    validates :session_id, presence: true, unless: ->(feedback) { feedback.job_id.present? }
    validates :context, presence: true

    sig { returns(String) }
    def feedback_type
      "summary"
    end

    sig { returns(T::Hash[String, String]) }
    def self.classification_map
      {
        Classification::SUMMARY_INACCURATE => "Generated summary was inaccurate",
        Classification::SUMMARY_HARMFUL => "Generated summary produced harmful content",
        Classification::UI_BUG => "UI bug",
        Classification::OTHER => "Other"
      }
    end

    sig { params(job_id: String).returns(Copilot::CompletionFeedback) }
    def self.for_job(job_id)
      existing = where(job_id: job_id).first
      existing || begin
        job = Copilot::CompletionJobStatus.find!(job_id)
        new(
          repository: job.repository,
          user: job.actor,
          job_id: job.id,
          context: job.context
        )
      end
    end
  end
end
