# typed: false
# frozen_string_literal: true

class AbuseReport < ApplicationRecord::Collab

  include GitHub::RateLimitable
  include GitHub::Relay::GlobalIdentification
  include Spam::Spammable
  extend GitHub::SimplePagination

  ZENDESK_SEARCH_BASE_URL = "https://github.zendesk.com/agent/search/1"

  belongs_to :reported_content, polymorphic: true
  belongs_to :reporting_user, class_name: "User"
  belongs_to :reported_user, class_name: "User"
  include ::Repositories::BelongsToRepository
  belongs_to_repository_via_domain optional: true

  belongs_to :reported_user_sponsors_listing_stafftools_metadata, primary_key: "sponsorable_id",
    foreign_key: "reported_user_id", inverse_of: :sponsorable_received_abuse_reports,
    class_name: "SponsorsListingStafftoolsMetadata"

  setup_spammable(:reporting_user)

  validates :reported_user_id, presence: true
  validates_uniqueness_of :reported_content_id, scope: [:reporting_user, :reported_content_type], message: "cannot be reported more than once"

  before_validation :set_reported_user, if: :reported_content
  before_validation :set_repository, if: :reported_content
  before_validation :ensure_not_rate_limited, if: :reporting_user
  before_validation :ensure_user_can_report_to_maintainer, if: :show_to_maintainer

  after_create :report_gist_as_spammy
  after_create :report_sponsors_listing_abuse_report, if: -> { GitHub.sponsors_enabled? }
  after_create_commit :instrument_creation, if: :reported_content

  enum :reason, [:unspecified, :abuse, :off_topic, :spam]

  # This displays to maintainers the most recent reports,
  # in the event that there are multiple reports against the same
  # content. The subquery fetches only identifiers for the latest-created records
  # within each group of [reported_content_id, reported_content_type] reports;
  # the outer query reconciles that data into full-sized records. MySQL
  # does not have a primitive way to express "sort by column within group".
  scope :most_recent_for_each_reported_content, -> (repo_id) {
    sql = <<-SQL
      JOIN (select reported_content_id, reported_content_type, MAX(created_at) as maxdate FROM abuse_reports WHERE show_to_maintainer = true AND repository_id = :repo_id GROUP BY reported_content_type, reported_content_id) latest
      ON abuse_reports.reported_content_id = latest.reported_content_id
      AND abuse_reports.reported_content_type = latest.reported_content_type
      AND abuse_reports.created_at = latest.maxdate
      AND abuse_reports.show_to_maintainer = true
      AND abuse_reports.repository_id = :repo_id
    SQL

    sanitized_sql = sanitize_sql_array([sql, repo_id: repo_id])
    order(created_at: :desc).joins(sanitized_sql)
  }

  scope :for_repository_maintainer, -> (repository_id) {
    where(repository_id:, show_to_maintainer: true)
  }

  # Public: The Zendesk search URL to return abuse reports for this
  #         reported content.
  #
  # Returns a String|nil.
  def async_zendesk_url
    if user_report?
      Promise.all([async_reporting_user, async_reported_user]).then do |reporter, reported_user|
        next unless reporter || reported_user
        template = Addressable::Template.new("#{ZENDESK_SEARCH_BASE_URL}?q={query}")
        template.expand({ query: "#{reporter.try(:login)} #{reported_user.try(:login)}" }).to_s
      end
    else
      async_reported_content.then do |content|
        if content.respond_to?(:async_path_uri)
          content.async_path_uri.then do |content_path|
            template = Addressable::Template.new("#{ZENDESK_SEARCH_BASE_URL}?q={path}")
            template.expand({ path: content_path }).to_s
          end
        elsif content.respond_to?(:name_with_display_owner)
          # Repository
          template = Addressable::Template.new("#{ZENDESK_SEARCH_BASE_URL}?q={path}")
          template.expand({ path: content.name_with_display_owner }).to_s
        end
      end
    end
  end

  def async_readable_by?(actor)
    return Promise.resolve(false) unless actor.present?
    return Promise.resolve(true) if actor.site_admin?
    return Promise.resolve(false) unless show_to_maintainer?

    async_repository.then do |repo|
      repo.async_adminable_by?(actor)
    end
  end

  # Public: Returns true if this is a report of the user, false if content.
  #
  # Returns a Boolean.
  def user_report?
    # AbuseReports with no reported content sets the id to 0
    reported_content_id == 0 || reported_content_id.nil?
  end

  # Public: Returns true if this is a report of a user's content, false otherwise.
  #
  # Returns a Boolean.
  def content_report?
    !user_report?
  end

  # Public: Returns true if this is a report of content already marked as spam, false otherwise.
  #
  # Returns a Boolean.
  def content_spammy?
    reported_content&.spammy? || reported_content&.belongs_to_spammy_content? # domain-isolation-query-violation:ignore:packages/issues (SELECT)
  end

  # Public: Returns reported_content if the user is permitted to view that content, nil otherwise.
  #
  # Returns a String|nil.
  def reported_content_for(actor)
    return unless reported_content.present? # domain-isolation-query-violation:ignore:packages/issues (SELECT)
    return reported_content if reported_content.is_a?(::Gist) || reported_content.is_a?(::GistComment)

    # if a repository is made private after abuse is reported,
    # we need to return `nil` instead of leaking private content
    # to site admins.
    if reported_content.repository.readable_by?(actor)
      reported_content
    end
  end

  def mark_resolved(actor)
    if async_readable_by?(actor).sync && update(resolved: true) # domain-isolation-query-violation:ignore:packages/issues (SELECT)
      instrument_resolve_abuse_report(actor)
      true
    else
      errors.add(:base, "You cannot perform that action at this time.")
      false
    end
  end

  def self.mark_resolved_for_content(actor, type, id)
    reports = reports_for_content(type, id)
    return false unless reports.any? &&
      reports.first.async_readable_by?(actor).sync # since they're all for the same content,
    # they all have the same readability
    if reports.update_all(resolved: true)
      instrument_resolve_abuse_reports(actor, reports)
      true
    else
      false
    end
  end

  def mark_unresolved(actor)
    if async_readable_by?(actor).sync && update(resolved: false) # domain-isolation-query-violation:ignore:packages/issues (SELECT)
      instrument_unresolve_abuse_report(actor)
      true
    else
      errors.add(:base, "You cannot perform that action at this time.")
      false
    end
  end

  def self.mark_unresolved_for_content(actor, type, id)
    reports = reports_for_content(type, id)
    return false unless reports.any? &&
      reports.first.async_readable_by?(actor).sync # since they're all for the same content,
    # they all have the same readability
    if reports.update_all(resolved: false)
      instrument_unresolve_abuse_reports(actor, reports)
      true
    else
      false
    end
  end

  private

  def report_sponsors_listing_abuse_report
    return unless reported_user_id && reported_user_sponsors_listing_stafftools_metadata
    return if reported_user_sponsors_listing_stafftools_metadata.has_received_abuse_report?
    reported_user_sponsors_listing_stafftools_metadata.update_column(:has_received_abuse_report, true)
  end

  def instrument_creation
    org = nil
    if repository && repository.owner.organization?
      org = reported_content.repository.owner
    end
    content_url = reported_content.is_a?(GistComment) ? reported_content.comment_path_url : reported_content.try(:url) # domain-isolation-query-violation:ignore:packages/issues (SELECT)

    reporting_user.instrument(:report_abuse, reported_user: reported_user, org: org, repo: repository, content_url: content_url)
  end

  def ensure_not_rate_limited
    if rate_limit_increment("report_content_limiter:#{reporting_user.id}", { max_tries: 5, ttl: 1.minute.to_i }).at_limit?
      errors.add(:base, "We've received too many reports from your account recently. Please wait a few minutes and try again.")
    end
  end

  def set_reported_user
    self.reported_user = self.reported_content.user if self.reported_content
  end

  def set_repository
    return if self.reported_content.is_a?(Gist) || self.reported_content.is_a?(GistComment)
    self.repository = self.reported_content.repository if self.reported_content
  end

  def report_gist_as_spammy
    if self.reported_content.is_a?(Gist)
      # If a Gist is being reported, also add it to the spam queue.
      # This is the old behavior when a user would report a Gist.
      GistFlaggedByUserJob.perform_later(self.reported_content.id, self.reporting_user.id)
    end
  end

  def ensure_user_can_report_to_maintainer
    unless self.reported_content.async_viewer_can_report_to_maintainer?(self.reporting_user).sync
      errors.add(:base, "You cannot perform that action at this time")
    end
  end

  def instrument_resolve_abuse_report(actor)
    repository.instrument(:resolve_abuse_report, abuse_report: self.id)
  end

  def instrument_unresolve_abuse_report(actor)
    repository.instrument(:unresolve_abuse_report, abuse_report: self.id)
  end

  # assumes all reports are on the same content
  private_class_method def self.instrument_resolve_abuse_reports(actor, reports)
    reports.first.repository.instrument(:resolve_abuse_report, abuse_reports: reports.map(&:id).sort)
  end

  # assumes all reports are on the same content
  private_class_method def self.instrument_unresolve_abuse_reports(actor, reports)
    reports.first.repository.instrument(:unresolve_abuse_report, abuse_reports: reports.map(&:id).sort)
  end

  private_class_method def self.reports_for_content(type, id)
    @reports = AbuseReport.where(reported_content_type: type, reported_content_id: id, show_to_maintainer: true)
  end
end
