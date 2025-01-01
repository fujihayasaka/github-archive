# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

class ProcessMentionedReferencesJob < ApplicationJob
  use_primaries ApplicationRecord::IssuesPullRequests

  queue_as :process_mentioned_references

  retry_on_dirty_exit
  retry_on_recoverable_exceptions wait: :polynomially_longer, attempts: 8
  retry_on ActiveRecord::ConnectionFailed, wait: :polynomially_longer, attempts: 8

  discard_on ActiveJob::DeserializationError

  # Create cross references record mentioned in the referrer's body
  # via Referrer#create_mentioned_references.
  #
  # referrer - A model with the Referrer module included.
  # ref_time - Timestamp used to record when the reference was made.
  def perform(referrer, ref_time)
    CrossReference.throttle do
      referrer.create_mentioned_references(ref_time)
    end
  end
end
