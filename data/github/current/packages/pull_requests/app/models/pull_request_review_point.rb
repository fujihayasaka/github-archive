# typed: true
# frozen_string_literal: true

# rubocop:todo GitHub/DatabaseModelsShouldHaveTests
class PullRequestReviewPoint < ApplicationRecord::Domain::IssuesPullRequests
  # rubocop:enable GitHub/DatabaseModelsShouldHaveTests
  include ::Repositories::BelongsToRepository
  belongs_to_repository_via_domain
  belongs_to :pull_request
  belongs_to :pull_request_update
  belongs_to :actor, class_name: :User

  validates :number, presence: true, numericality: { only_integer: true, greater_than: 0 }, uniqueness: { scope: :pull_request_id }
  before_validation :set_number, on: :create

  after_commit :notify_pull_request_channel # rubocop:todo GitHub/AvoidActiveRecordCallbacks

  delegate :head_oid, :base_oid, :commits_count, to: :pull_request_update

  def self.number_desc
    order("`pull_request_review_points`.`number` DESC")
  end

  # Absolute permalink URL for this pull request review point.
  #
  # include_host - Turn off the `GitHub.url` host in the url. (default true)
  #                pull_request.permalink(include_host: false) => `/github/github/pull/4/files/BASE..HEAD`
  #
  def permalink(include_host: true)
    return nil unless T.must(pull_request).repository.present?
    return @permalink if defined?(@permalink)

    @permalink = "#{pull_request&.permalink(include_host: include_host)}#{url_path}"
  end

  def async_path_uri
    return @async_path_uri if defined?(@async_path_uri)

    @async_path_uri = Promise.all([async_pull_request.then { |x| T.must(x).async_path_uri }, async_pull_request_update]).then do |path_uri, _|
      path_uri = path_uri.dup
      path_uri.path = "#{path_uri.path}#{url_path}"
      path_uri
    end
  end

  private

  def set_number
    self.number = T.must(pull_request).review_points.order("number DESC").first&.number.to_i + 1
  end

  def notify_pull_request_channel
    pull_request&.notify_socket_subscribers
  end

  def url_path
    range_oids = []
    range_oids << base_oid unless base_oid == T.must(pull_request).base_sha
    range_oids << head_oid
    "/files/#{range_oids.join("..")}"
  end
end
