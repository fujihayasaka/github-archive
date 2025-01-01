# frozen_string_literal: true

require "github/encoding"
require "cve_json_builder"

# CVEReview encapsulates a review decision made by GitHub CNA on a CVERequest, or set of CVERequests form the same GHSA ID
class CVEReview < ApplicationRecord
  include SinceYesterday

  # cve requests are associated via the ghsa_id column
  has_many :cve_requests,
    primary_key: :ghsa_id,
    foreign_key: :ghsa_id,
    inverse_of: :cve_review

  belongs_to :advisory_review, primary_key: "ghsa_id", foreign_key: "ghsa_id",
    optional: true, inverse_of: :cve_review
  belongs_to :advisory, primary_key: "ghsa_id", foreign_key: "ghsa_id",
    optional: true, inverse_of: :cve_review

  has_one :cve, primary_key: :assigned_cve_id, foreign_key: :cve_id, inverse_of: :cve_review
  has_one :ghsl_request,
    primary_key: :ghsa_id,
    foreign_key: :ghsa_id,
    inverse_of: :cve_review
  # The feed entry association here only exists to serve calculation of
  # curation state. Otherwise, the relationship between CVE reviews and feed
  # entries isn't very realistic or helpful.
  has_one :repository_advisory_feed_entry,
    -> { where(source: RepositoryAdvisoriesImporter.source) },
    class_name: "FeedEntry",
    foreign_key: "ghsa_id",
    primary_key: "ghsa_id",
    inverse_of: false

  # these columns are lists, but not worth formalizing as association to separate tables
  # these values are used only for CVE JSON generation
  serialize :version_values, type: Array
  serialize :problemtype_values, type: Array
  serialize :misc_references, type: Array

  # return the most recently made cve request for this cve review
  def current_cve_request
    cve_requests.order(:id).last
  end

  # cve submissions to mitre
  has_many :mitre_cve_submissions,
    primary_key: :ghsa_id,
    foreign_key: :ghsa_id,
    inverse_of: :cve_review

  validates :ghsa_id, presence: true, uniqueness: { case_sensitive: true }
  validates :assigned_cve_id, cve_id: true, uniqueness: { case_sensitive: false, allow_nil: true }
  validates :cvss_vectorString, presence: false, cvss_vector_string: true
  validates :title, presence: true

  extend ::GitHub::Encoding
  force_utf8_encoding :comment,
    :title,
    :description,
    :vendor_name,
    :product

  before_save :before_save
  before_create :set_review_requested_at, unless: :review_requested_at?

  enum :decision, { undecided: 0, assigned: 1, not_assigned: 2 }

  # the states of a CVE Review
  #
  # open:      The decision is still pending, the review PR is still open.
  #            All CVE Reviews start here.
  #            Also, when a not_assigned review is re-submitted again, it is also open.
  # notified:  The underlying advisory has been notified of the CVE Review decision.
  #            A CVE ID was either assigned, or not_assigned.
  # submitted: The CVE has been submitted to MITRE for publication
  # rejected:  The CVE has been marked as REJECTED in MITRE's CVE database
  # open_update: The CVE was previously published to MITRE, but will be republished with an update.
  #
  enum :state, { open: 0, notified: 1, submitted: 2, rejected: 3, open_update: 4 }

  scope :search_identifiers, lambda { |query|
    next all if query.blank?

    # Find CVE and GHSA IDs to search
    cve_id_pattern = query.upcase.scan(/\b(CVE-[\d-]+)\b/).flatten.join("|").presence
    ghsa_id_pattern = query.gsub(/ghsa-/i, "GHSA-").scan(/\b(GHSA-[\w-]+)\b/).flatten.join("|").presence

    if cve_id_pattern && ghsa_id_pattern
      where("cve_reviews.assigned_cve_id REGEXP ? OR cve_reviews.ghsa_id REGEXP ?", cve_id_pattern, ghsa_id_pattern)
    elsif cve_id_pattern
      where("cve_reviews.assigned_cve_id REGEXP ?", cve_id_pattern)
    elsif ghsa_id_pattern
      where("cve_reviews.ghsa_id REGEXP ?", ghsa_id_pattern)
    else
      none
    end
  }

  scope :curation_state_in_triage, lambda { |after_id: nil|
    scoped = open
    scoped = scoped.order(:id).where(arel_table[:id].gt(after_id)) if after_id
    scoped
  }
  scope :curation_state_waiting, -> { notified.assigned.left_joins(:repository_advisory_feed_entry, :ghsl_request).where(feed_entries: { id: nil }, ghsl_requests: { id: nil }) }
  scope :curation_state_open, -> { notified.assigned.left_joins(:repository_advisory_feed_entry, :ghsl_request).where("feed_entries.id IS NOT NULL OR ghsl_requests.id IS NOT NULL") }
  scope :curation_state_published, -> { submitted.assigned }
  scope :curation_state_closed, -> { notified.not_assigned }
  scope :curation_state_rejected, -> { rejected }
  scope :curation_state_open_update, -> { open_update }
  scope :by_curation_state, lambda { |curation_state|
    case curation_state
    when "in_triage" then curation_state_in_triage
    when "waiting" then curation_state_waiting
    when "open" then curation_state_open
    when "published" then curation_state_published
    when "closed" then curation_state_closed
    when "rejected" then curation_state_rejected
    when "open_update" then curation_state_open_update
    end
  }

  extend ::GitHub::Encoding
  force_utf8_encoding :review_notes

  include AASM
  aasm :state, enum: true, whiny_persistence: true do
    state :open
    state :notified
    state :submitted
    state :rejected
    state :open_update

    # this event is invoked when decision is finalized and maintainer should be notified
    # this corresponds with merging of review PR
    event :notify, after_commit: [:publish_to_hydro, :import_related_advisory] do
      transitions from: :open,
        to: :notified,
        guards: [:notifiable?]
    end

    # for an existing review, when a new request shows up:
    # if open, stay open and do nothing
    # if notified and not_assigned, then change to reopened state
    # otherwise not allowed
    event :receive_request do
      transitions from: :open,
        to: :open

      transitions from: :notified,
        to: :open,
        guards: [:not_assigned?],
        after: :reset_decision

      before :set_review_requested_at
    end

    event :submit_to_mitre do
      transitions from: [:notified, :open_update], to: :submitted, guard: proc { curation_state == "open" || curation_state == "open_update" }
    end

    event :reject do
      transitions from: [:notified, :open_update], to: :rejected, guard: :assigned?
    end

    event :reopen do
      transitions from: [:submitted, :rejected], to: :open_update
    end
  end

  # Make a new CVE Request or re-open a not_assigned CVE Request
  def self.create_or_reopen_from_cve_request!(cve_request)
    cve_review = CVEReview.find_by(ghsa_id: cve_request.ghsa_id)

    if cve_review
      cve_review.receive_request!
    else
      cvss_vector_string = if AdvisoryDB::Features.enabled?("advisory_db_cvss_v4")
                             cve_request.cvss_v4 || cve_request.cvss_v3
                           else
                             cve_request.cvss_v3
                           end

      cve_review = create!(
        ghsa_id: cve_request.ghsa_id,
        title: cve_request.title,
        description: cve_request.description,
        confirm_reference: cve_request.advisory_permalink,
        vendor_name: cve_request.repo_owner,
        product: cve_request.repo_name,
        problemtype_values: cve_request.cwe_ids,
        cvss_vectorString: cvss_vector_string,
        cvss_v4: cve_request.cvss_v4,
      )
    end

    cve_review
  end

  def to_param
    ghsa_id
  end

  def curation_state
    if open?
      "in_triage"
    elsif notified?
      if assigned?
        repository_advisory_feed_entry || ghsl_request.present? ? "open" : "waiting"
      else
        "closed"
      end
    elsif submitted?
      "published"
    elsif rejected?
      "rejected"
    elsif open_update?
      "open_update"
    end
  end

  def curation_state_in_triage?
    curation_state == "in_triage"
  end

  # returns a list of errors that prevent notifying
  def notification_errors
    errors = []
    case decision
    when "assigned"
      errors << "#{decision} reviews require assigned_cve_id" if assigned_cve_id.blank?
    when "not_assigned"
      errors << "#{decision} reviews require comment" if comment.blank?
    else
      errors << "#{decision} is not a notifiable decision"
    end
    errors
  end

  def notifiable?
    notification_errors.empty?
  end

  def hydro_payload
    payload = {
      ghsa_id: ghsa_id,
      assigned_cve_id: assigned_cve_id || "",
      comment: comment || "",
    }
    payload["decision"] = case decision
                          when "assigned", "not_assigned"
                            decision.upcase
                          else
                            "UNKNOWN"
                          end
    payload
  end

  def cve_json_builder
    CVEJSONBuilder.new(
      ghsa_id: ghsa_id,
      ghsl_id: ghsl_request&.ghsl_id,
      cve_id: assigned_cve_id,
      title: title,
      description: description,
      vendor_name: vendor_name,
      product: product,
      version_values: version_values,
      problemtype_values: problemtype_values,
      confirm_reference: confirm_reference,
      misc_references: misc_references,
      cvss_vectorString: cvss_vectorString,
    )
  end

  def branch_name
    "add_#{assigned_cve_id}" if assigned_cve_id
  end

  def importable?
    # ensure the state is not open
    return false unless notified? || submitted?

    # ensure a cve id was actually assigned
    return false unless assigned?

    true
  end

  def identifier
    "cve_review/#{ghsa_id}"
  end

  def combined_references
    [confirm_reference] + misc_references
  end

  def vulnerabilities
    {}
  end

  def cwe_ids
    problemtype_values&.filter_map { |cwe_id| cwe_id[/CWE-\d+/] }
  end

  def advisory_payload
    severity = nil
    cvss_v3_vector_string = ""
    cvss_v4_vector_string = ""

    if cvss_v4.present?
      severity = SeverityCalculator.from_cvss_v4(cvss_v4)
      cvss_v4_vector_string = cvss_vectorString
    elsif cvss_vectorString.present?
      severity = SeverityCalculator.from_cvss_v3(cvss_vectorString)
      cvss_v3_vector_string = cvss_vectorString
    end

    {
      summary: title,
      description: AdvisoryDBToolkit.normalize_description_line_endings(description),
      severity: severity,
      references: combined_references,
      cwe_ids: cwe_ids,
      cvss_v3: cvss_v3_vector_string,
      cvss_v4: cvss_v4_vector_string,
      vulnerabilities: vulnerabilities,
      withdrawn: false,
    }
  end

  def importer_object
    {
      identifier: identifier,
      ghsa_id: ghsa_id,
      cve_id: assigned_cve_id,
      raw_payload: attributes,
      advisory_payload: advisory_payload,
    }
  end

  def read_only?
    read_only_reason.present?
  end

  def read_only_reason
    if open?
      :not_triaged
    elsif submitted?
      :cve_published
    elsif !assigned?
      :no_cve_id
    elsif rejected?
      :rejected
    end
  end

  # Sometimes we receive unexpected problemtype values, sometimes a single
  # string, sometimes an array of hashes, sometimes a single hash with multiple
  # key/value pairs. Here we try to massage incoming values to be our expected
  # array of strings.
  def problemtype_values=(values)
    super(convert_problemtype_values(values))
  end

  def related_cve_reviews
    CVEReview.where(vendor_name: vendor_name, product: product).where.not(id: id)
  end

  def record_curation_decision(type:, decision:, curator:)
    last_state_change = versions.reverse.find { |version| version.changeset.include?(:state) || version.changeset.include?(:created_at) }
    time_to_decision = Time.current - last_state_change.created_at

    if notified? && assigned? && repository_advisory_feed_entry
      time_spent_waiting = repository_advisory_feed_entry.created_at - last_state_change.created_at
      time_to_decision -= time_spent_waiting if time_spent_waiting > 0
    end

    PublishCurationDecisionToHydroJob.perform_later(
      type: type,
      decision: decision,
      curator: curator,
      ghsa_id: ghsa_id,
      time_to_decision: time_to_decision,
    )
  end

  def import_related_advisory
    # Only a CVE Review which is assigned should result in an Advisory Review
    return unless assigned?

    ImportJob.perform_later(
      CVEReviewImporter.source,
      cve_review_id: id,
      report_to_slack: false, # Don't cause noise in Slack room
    )
  end

  private

  def before_save
    self.cvss_v4 = cvss_vectorString if cvss_vectorString.present? && cvss_vectorString.starts_with?("CVSS:4.0/")
    self.misc_references = AdvisoryDBToolkit::ReferenceSorter.sorted_reference_list(misc_references) if misc_references.present?
    self.description = AdvisoryDBToolkit.normalize_description_line_endings(description) if description.present?
  end

  def convert_problemtype_values(values)
    case values
    when String
      values.lines(chomp: true)
    when Array
      values.flat_map do |value|
        convert_problemtype_values(value)
      end
    when Hash
      values.map do |key, value|
        "#{key}: #{value}"
      end
    end
  end

  def set_review_requested_at
    self.review_requested_at = Time.current
  end

  def reset_decision
    self.decision = :undecided
  end

  def publish_to_hydro
    PublishCVEReviewToHydroJob.perform_later(cve_review_id: id)
  end
end
