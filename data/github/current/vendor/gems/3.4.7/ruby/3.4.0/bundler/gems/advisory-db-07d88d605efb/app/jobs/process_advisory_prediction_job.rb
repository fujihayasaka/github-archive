# frozen_string_literal: true

# This job is intended to processes AdvisoryPrediction hydro messages
# These messages are produced by the ML model
# The AdvisoryPrediction predicts if the CVE advisory would be
# Rejected by human or blocklist (reject_prediction=:REJECT),
# or if it would be accepted into the dataset (reject_prediction=:NOT_REJECT).

class ProcessAdvisoryPredictionJob < ApplicationJob
  queue_as :low

  AdvisoryPredictionError = Class.new(StandardError)

  discard_on(AdvisoryPredictionError) do |_job, error|
    Failbot.report!(error)
  end

  ALLOWED_PREDICTIONS = %w[REJECT NOT_REJECT].freeze

  def perform(identifier:, reject_prediction:)
    feed_entry = FeedEntry.find_by(identifier: identifier)
    if feed_entry.nil?
      raise AdvisoryPredictionError, "Got advisory prediction for #{identifier} but no FeedEntry with that identifier is found"
    end

    unless ALLOWED_PREDICTIONS.include?(reject_prediction)
      raise AdvisoryPredictionError, "Got unsupported prediction: #{reject_prediction}"
    end

    feed_entry.ml_reject_prediction = reject_prediction.downcase
    return unless feed_entry.changed?

    feed_entry.save!
    return unless (advisory_review = feed_entry.advisory_review)

    case reject_prediction
    when "REJECT"
      if advisory_review.may_revert?
        advisory_review.revert!
      elsif advisory_review.may_close?
        advisory_review.close!
      end
    when "NOT_REJECT"
      advisory_review.reopen! if advisory_review.may_reopen? && !advisory_review.auto_closable?
    end
  end
end
