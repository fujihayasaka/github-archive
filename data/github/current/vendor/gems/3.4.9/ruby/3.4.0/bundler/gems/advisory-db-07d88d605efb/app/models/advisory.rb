# frozen_string_literal: true

require "github/encoding"

class Advisory < ApplicationRecord
  REVIEWED_FOLDER = "github-reviewed"
  UNREVIEWED_FOLDER = "unreviewed"

  has_many :references, -> { order(:index) }, inverse_of: :advisory
  has_many :vulnerabilities, -> { order(:index) }, inverse_of: :advisory
  has_many :advisory_alerting_events, inverse_of: :advisory, primary_key: :ghsa_id, foreign_key: :ghsa_id
  has_and_belongs_to_many :cwes # rubocop:disable Rails/HasAndBelongsToMany
  has_one :advisory_review, primary_key: "ghsa_id", foreign_key: "ghsa_id",
    inverse_of: :advisory
  has_one :sync_state, class_name: "AdvisorySyncState", dependent: :destroy
  has_one :cve_review, primary_key: "ghsa_id", foreign_key: "ghsa_id",
    inverse_of: :advisory

  attr_readonly :ghsa_id

  enum :severity, AdvisoryDB.severities, prefix: true

  validates :ghsa_id, ghsa_id: true, presence: true, uniqueness: { case_sensitive: false },
    on: :create
  validates :cve_id, cve_id: true, length: { minimum: 1, allow_nil: true }
  validates :summary, length: { maximum: 255 }, class: { is: String, allow_nil: true }
  validates :description, presence: true
  validates :cvss_v3, presence: false, cvss_vector_string: true
  validates :cvss_v4, presence: false, cvss_vector_string: true
  validates :published_at, presence: true

  with_options if: :reviewed? do
    validates :summary, presence: true
    validates :severity, presence: true
  end

  scope :withdrawn, -> { where.not(withdrawn_at: nil) }
  scope :not_withdrawn, -> { where(withdrawn_at: nil) }

  extend ::GitHub::Encoding
  force_utf8_encoding :description

  after_save :log_save

  def to_param
    ghsa_id
  end

  def database_url
    "https://github.com/advisories/#{ghsa_id}"
  end

  def repo_file_content
    return @repo_file_content if defined?(@repo_file_content)

    osv_data = AdvisoryDB::OSV.ghsa_to_osv(self)
    @repo_file_content = JSON.pretty_generate(osv_data)
  end

  def repo_file_path
    @repo_file_path ||= "advisories/#{reviewed? ? REVIEWED_FOLDER : UNREVIEWED_FOLDER}/#{published_at.year}/#{published_at.month.to_s.rjust(2, "0")}/#{ghsa_id}/#{ghsa_id}.json"
  end

  def withdraw
    update!(withdrawn_at: Time.current)
  end

  def withdrawn?
    withdrawn_at?
  end

  def hydro_payload
    payload = {
      ghsa_id: ghsa_id,
      description: description,
      sources: hydro_sources,
      vulnerabilities: vulnerabilities.filter_map(&:hydro_payload),
      references: references.map(&:hydro_payload),
      cwe_ids: cwes.pluck(:cwe_id),
      published_at: published_at,
      withdrawn_at: withdrawn_at,
      reviewed_at: reviewed_at,
      nvd_published_at: nvd_published_at,
      classification: advisory_review.malware_feed_entry? ? :MALWARE : :GENERAL,
    }

    payload[:cve_id] = cve_id if cve_id.present?
    payload[:white_source_id] = white_source_id if white_source_id.present?
    payload[:npm_id] = npm_id if npm_id.present?
    payload[:summary] = summary if summary.present?
    payload[:source_code_location] = source_code_location if source_code_location.present?
    payload[:severity] = severity.upcase if severity.present?
    payload[:cvss_v3] = cvss_v3 if cvss_v3.present?
    payload[:cvss_v4] = cvss_v4 if cvss_v4.present?

    payload
  end

  def hydro_status
    reviewed? ? :REVIEWED : :UNREVIEWED
  end

  def vulnerabilities_hash
    vulnerabilities_hash = {}

    vulnerabilities.each do |vuln|
      vulnerabilities_hash[vuln.index] = {
        "fix_commits" => vuln.fix_commits_array,
        "ecosystem" => vuln.package_ecosystem,
        "package_name" => vuln.package_name,
        "vulnerable_version_range" => vuln.vulnerable_version_range,
        "first_patched_version" => vuln.first_patched_version,
        "withdrawn" => vuln.withdrawn_at.present?,
      }
    end

    vulnerabilities_hash
  end

  def log_save
    ::GitHub::Telemetry::Logs.logger.info(
      "Logging a save of an Advisory",
      "gh.advisory_inbox.ghsa_id": ghsa_id,
      "gh.advisory_inbox.publisher.backtrace": caller.join(","),
      "gh.advisory_inbox.publisher.is_simulated": AdvisoryDB::GlobalVariables.in_simulated_publication?,
    )
  end

  private

  def hydro_sources
    advisory_review.feed_entries.map(&:hydro_source).uniq
  end
end
