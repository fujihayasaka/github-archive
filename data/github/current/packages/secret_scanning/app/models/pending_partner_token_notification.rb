# typed: true
# frozen_string_literal: true

class PendingPartnerTokenNotification < ApplicationRecord::TokenScanningService

  validates_presence_of :repository_id, :blob_oid, :commit_oid, :path, :token_type, :requested_at

  validates_length_of :blob_oid, is: 40

  validates_numericality_of :start_line, :end_line, greater_than: -1

  validates_numericality_of :start_column, :end_column, greater_than: -1

  enum :repository_type, {
    unknown: 0,

    repository: 1,

    wiki: 2,

    gist: 3,
  }

  enum :notification_state, {
    # Token requested to be re-notified
    requested: 0,

    # Token scheduled to be notified in the current run.
    scheduled: 1,

    # No report_url found to notify.
    no_report_url: 2,

    # Failed to notify as raw token could not be extracted
    no_raw_token: 3,

    # Notification completed successfully.
    notified: 4,

    # Failed due to response timeouts from the partner.
    failed_timeout: 5,

    # Failed due to a 500 or other error response from the partner.
    failed_error: 6,

    # Notification could not be made after multiple retries.
    failed_retry_count_exceeded: 7,
  }

  # Create an entry for a token that was failed to be notified to partner
  def self.create_from_failed_token!(repository, token)
    attributes = generate_partner_token_attributes(repository, token)
    retry_on_find_or_create_error do
      PendingPartnerTokenNotification.find_by(attributes) || PendingPartnerTokenNotification.create!(attributes.merge({ requested_at: Time.now }))
    end
  end

  # Generate token attributes
  def self.generate_partner_token_attributes(repository, token)
    {
      token_type: token.type,
      repository_id: repository.id,
      blob_oid: token.blob,
      commit_oid: token.commit,
      path: token.path,
      start_line: token.start_line,
      end_line: token.end_line,
      start_column: token.start_column,
      end_column: token.end_column,
      repository_type: get_repository_type(repository),
    }
  end

  def self.get_repository_type(repository)
    if repository.is_a?(Repository)
      :repository
    elsif repository.is_a?(Gist)
      :gist
    elsif repository.is_a?(Wiki)
      :wiki
    else
      :invalid
    end
  end
end
