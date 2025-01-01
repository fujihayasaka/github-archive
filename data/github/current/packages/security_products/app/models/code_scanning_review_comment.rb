# typed: true
# frozen_string_literal: true

class CodeScanningReviewComment < ApplicationRecord::Domain::IssuesPullRequests
  attribute :alert_title, StringFromBinary.new
  attribute :alert_message, StringFromBinary.new

  # this validation is temporary until we've backfilled this field in old entries and can move
  # the restriction to the db schema
  validates :alert_message, presence: true

  include ::Repositories::BelongsToRepository
  belongs_to_repository_via_domain
  belongs_to :pull_request
  belongs_to :pull_request_review_comment

  validate :matches_pull_request_repository

  # This is only temporary until we've run another migration to set the
  # default value to false at the schema level.
  before_save :set_fixed_to_false_if_nil

  def fix!
    update!(fixed: true)
  end

  def reopen!
    update!(fixed: false)
  end

  def self.format_body(alert:, repository:)
    output = []
    output << "## #{ alert.rule_short_description}" if alert.rule_short_description.present?
    output << "#{ alert.message_text }" if alert.message_text.present?
    output << "[Show more details](#{UrlHelpers.repository_code_scanning_result_url(
      host: GitHub.url,
      user_id: repository.owner_display_login,
      repository: repository,
      number: alert.number,
    )})" if alert.number.nonzero?
    output.join("\n\n")
  end

  private

  def matches_pull_request_repository
    pr = pull_request
    return if pr.nil?
    if repository_id != pr.repository_id
      errors.add(:repository, "does not match the pull request's repository")
    end
  end

  def set_fixed_to_false_if_nil
    self.fixed ||= false
  end
end
