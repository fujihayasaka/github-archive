# typed: strict
# frozen_string_literal: true

module Copilot
  class CompletionFeedback < ApplicationRecord::Copilot

    self.table_name = "copilot_completion_feedback"

    enum :sentiment, %i(neutral positive negative)

    class Classification
      EMPTY = "empty"
      TEXT_COMPLETION_UNHELPFUL = "text_completion_unhelpful"
      SUMMARY_INACCURATE = "summary_inaccurate"
      SUMMARY_HARMFUL = "summary_harmful"
      UI_BUG = "ui_bug"
      OTHER = "other"
    end

    enum :classification, {
      Classification::EMPTY => 0,
      Classification::TEXT_COMPLETION_UNHELPFUL => 1,
      Classification::SUMMARY_INACCURATE => 2,
      Classification::SUMMARY_HARMFUL => 3,
      Classification::UI_BUG => 4,
      Classification::OTHER => 5
    }

    serialize :context, type: Hash

    include ::Repositories::BelongsToRepository
    flagged_belongs_to_repository_via_domain
    belongs_to :user, class_name: "::User"

    validates :repository_id, presence: true
    validates :user_id, presence: true
    validates :job_id, presence: true, unless: ->(feedback) { feedback.session_id.present? }
    validates :session_id, presence: true, unless: ->(feedback) { feedback.job_id.present? }
    validates :context, presence: true

    sig { returns(String) }
    def feedback_type
      if !job_id.blank? && !session_id.blank?
        "summary with text completion"
      elsif !session_id.blank?
        "text completion"
      else
        "summary"
      end
    end

    sig { returns(T::Hash[String, String]) }
    def self.classification_map
      {
        Classification::TEXT_COMPLETION_UNHELPFUL => "Text completion was unhelpful",
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

    # Finds for a text completion session, considering any that were created by a summary job before we had a session.
    sig { params(user_id: Integer, repository_id: Integer, session_id: String, job_id: T.nilable(String)).returns(T.nilable(Copilot::CompletionFeedback)) }
    def self.for_text_completion_session(user_id, repository_id, session_id, job_id)
      # For a typical user we already have the context stored in KV, this is just a mechanism to filter out junk submissions
      cached_session_id = Codespaces::Kv.store.get("completion_feedback_#{user_id}_#{repository_id}").value { nil }
      return unless cached_session_id && cached_session_id == session_id

      session_context = { session_id:, repository_id:, actor_id: user_id }

      existing = find_by(session_id:)
      if !existing && job_id
        existing = where(job_id: job_id).first
      end

      if existing
        if !existing.session_id
          existing.update!(session_id:, context: existing.context.merge(session_context))
        elsif !existing.job_id && job_id
          existing.update!(job_id:, context: session_context.merge!(Copilot::CompletionJobStatus.find!(job_id).context))
        end

        return existing
      end

      if job_id
        session_context.merge!(Copilot::CompletionJobStatus.find!(job_id).context)
      end
      new(
        repository_id:,
        user_id:,
        session_id:,
        job_id:,
        context: session_context,
      )
    end
  end
end
