# frozen_string_literal: true

require "github/encoding"
require "normal_yaml"

class AdvisoryReview < ApplicationRecord
  include AASM
  extend GHSAIDGenerator
  include SinceYesterday

  belongs_to :advisory, primary_key: "ghsa_id", foreign_key: "ghsa_id",
    optional: true, inverse_of: :advisory_review
  belongs_to :cve_review, primary_key: "ghsa_id", foreign_key: "ghsa_id",
    optional: true, inverse_of: :advisory_review

  has_many :feed_entries
  has_many :approvals, class_name: "AdvisoryReviewApproval", dependent: :delete_all
  has_many :ai_predictions, dependent: :delete_all

  has_many :blocklist_matches, dependent: :delete_all
  has_many :blocklisted_terms, through: :blocklist_matches

  has_many :advisory_reviews_campaigns, dependent: :delete_all
  has_many :campaigns, through: :advisory_reviews_campaigns

  has_many :advisory_reviews_labels, dependent: :delete_all
  has_many :labels, through: :advisory_reviews_labels

  has_one :cve_review_feed_entry,
    -> { where(source: CVEReviewImporter.source) },
    class_name: "FeedEntry",
    inverse_of: :advisory_review
  has_one :repository_advisory_feed_entry,
    -> { where(source: RepositoryAdvisoriesImporter.source) },
    class_name: "FeedEntry",
    inverse_of: :advisory_review

  attr_readonly :ghsa_id

  serialize :advisory_payload, coder: NormalYAML
  # This property is an interim implementation of a structured advisory payload.
  # At the time of this writing you should not expect it to be authoritative or reliably populated.
  # https://github.com/github/advisory-db/pull/2150
  #
  # Once this is backfilled and stable, we can simplify our severity sorting and filtering too.
  # Look for uses of `advisory_reviews.advisory_payload` in the codebase.
  has_one :structured_advisory_payload, inverse_of: :payload_container, as: :payload_container

  validates :ghsa_id, ghsa_id: true, presence: true
  validates :cve_id, cve_id: true, length: { minimum: 1, allow_nil: true }
  validates :state, presence: true
  validates :advisory_payload, exclusion: { in: [nil] } # Forbid nil, allow {}
  validates :default_ecosystem, length: { maximum: 40, allow_nil: true }

  scope :curation_state_waiting, lambda {
    where(state: [:open, :in_review])
      .left_joins(:cve_review_feed_entry, :repository_advisory_feed_entry) # Join feed entries
      .where.not(cve_review_feed_entry: { id: nil }) # Has a CVE review feed entry, and...
      .where(repository_advisory_feed_entry: { id: nil }) # ...has no repository advisory feed entry
  }
  scope :curation_state_open, lambda {
    where(state: [:open, :in_review])
      .left_joins(:cve_review_feed_entry, :repository_advisory_feed_entry)
      .merge(
        where(cve_review_feed_entry: { id: nil }) # Either has no CVE review feed entry, or...
          .or(where.not(repository_advisory_feed_entry: { id: nil })), # ...has both
      )
  }
  scope :curation_state_open_create, lambda {
    curation_state_open.left_joins(:advisory).where(advisories: { id: nil }).or(
      curation_state_open.left_joins(:advisory).where(advisories: { reviewed: false }),
    )
  }
  scope :curation_state_open_update, -> { curation_state_open.joins(:advisory).where(advisories: { reviewed: true }) }
  scope :curation_state_ready_to_publish, -> { approved_to_publish }
  scope :curation_state_ready_to_withdraw, -> { approved_to_withdraw }
  scope :curation_state_ready, -> { where(state: [:approved_to_publish, :approved_to_withdraw]) }
  scope :curation_state_published, -> { accepted.joins(:advisory).where(advisories: { withdrawn_at: nil }) }
  scope :curation_state_published_reviewed, -> { curation_state_published.where(advisories: { reviewed: true }) }
  scope :curation_state_published_unreviewed, -> { curation_state_published.where(advisories: { reviewed: false }) }
  scope :curation_state_withdrawn, -> { accepted.joins(:advisory).where.not(advisories: { withdrawn_at: nil }) }
  scope :curation_state_closed, -> { where(state: [:closed, :rejected]) }
  scope :by_curation_state, lambda { |curation_state|
    case curation_state
    when "waiting" then curation_state_waiting
    when "open" then curation_state_open
    when "open_create" then curation_state_open_create
    when "open_update" then curation_state_open_update
    when "ready" then curation_state_ready
    when "ready_to_publish" then curation_state_ready_to_publish
    when "ready_to_withdraw" then curation_state_ready_to_withdraw
    when "published" then curation_state_published
    when "published_reviewed" then curation_state_published_reviewed
    when "published_unreviewed" then curation_state_published_unreviewed
    when "withdrawn" then curation_state_withdrawn
    when "closed" then curation_state_closed
    end
  }
  scope :by_curator, lambda { |login|
    case login
    when "none"
      left_joins(:approvals)
        .where("advisory_review_approvals.created_at > advisory_reviews.review_requested_at or advisory_review_approvals.created_at is null")
        .where(advisory_review_approvals: { id: nil })
    when "all"
      all
    else
      joins(approvals: :user)
        .merge(AdvisoryReviewApproval.current_review_request)
        .where(users: { login: login })
    end
  }
  scope :by_source, lambda { |source|
    case source
    when "all"
      all
    when "pending_trusted"
      where.not(id: AdvisoryReview.by_source("pending_untrusted").select(:id))
    when "pending_untrusted"
      joins(:feed_entries).where(feed_entries: { source: AdvisoryDB.untrusted_sources }).where("feed_entries.updated_at >= advisory_reviews.review_requested_at").distinct
    else
      joins(:feed_entries).where(feed_entries: { source: source }).distinct if AdvisoryDB.sources.include?(source)
    end
  }
  scope :by_default_ecosystem, lambda { |ecosystem|
    if AdvisoryDB.curated_ecosystems.include?(ecosystem)
      where(default_ecosystem: ecosystem)
    elsif ecosystem == "none"
      where(default_ecosystem: nil)
    else
      all
    end
  }

  scope :by_campaign, lambda { |campaign_id, campaign_review_state = nil|
    if campaign_id.nil?
      where.not(id: AdvisoryReviewsCampaign.active_campaign_advisory_review_ids)
    else
      scoped = joins(:advisory_reviews_campaigns).where(advisory_reviews_campaigns: { campaign_id: campaign_id })

      case campaign_review_state
      when "pending"
        scoped = scoped.merge(AdvisoryReviewsCampaign.pending)
      when "complete"
        scoped = scoped.merge(AdvisoryReviewsCampaign.complete)
      end

      scoped
    end
  }

  scope :by_label_ids, lambda { |label_ids|
    next all if label_ids.blank?

    include_advisory_review_id_sets = [] # array of arrays because inclusion is an AND operation
    exclude_advisory_review_ids = [] # single array because exclusion is an OR operation
    label_ids.each do |label_id|
      advisory_review_ids = AdvisoryReviewsLabel.where(label_id: label_id.to_i.abs).pluck(:advisory_review_id)
      if label_id.starts_with?("-")
        exclude_advisory_review_ids.concat(advisory_review_ids)
      else
        include_advisory_review_id_sets << advisory_review_ids
      end
    end
    include_advisory_review_ids = include_advisory_review_id_sets.inject(:&)

    advisory_reviews = include_advisory_review_ids.present? ? AdvisoryReview.where(id: include_advisory_review_ids) : AdvisoryReview.all
    advisory_reviews.where.not(id: exclude_advisory_review_ids)
  }

  scope :by_severity, lambda { |severity|
    if AdvisoryDB.severities.include?(severity.to_s)
      where("advisory_reviews.advisory_payload REGEXP ?", "(?m)^severity: #{severity}$")
    else
      all
    end
  }

  scope :search_identifiers, lambda { |query|
    next all if query.blank?

    # Find CVE and GHSA IDs to search
    cve_id_pattern = query.upcase.scan(/\b(CVE-[\d-]+)\b/).flatten.join("|").presence
    ghsa_id_pattern = query.gsub(/ghsa-/i, "GHSA-").scan(/\b(GHSA-[\w-]+)\b/).flatten.join("|").presence

    if cve_id_pattern && ghsa_id_pattern
      where("advisory_reviews.cve_id REGEXP ? OR advisory_reviews.ghsa_id REGEXP ?", cve_id_pattern, ghsa_id_pattern)
    elsif cve_id_pattern
      where("advisory_reviews.cve_id REGEXP ?", cve_id_pattern)
    elsif ghsa_id_pattern
      where("advisory_reviews.ghsa_id REGEXP ?", ghsa_id_pattern)
    else
      none
    end
  }

  extend ::GitHub::Encoding
  force_utf8_encoding :review_notes

  before_validation :clear_empty_cve_id
  before_save :before_save
  before_create :set_review_requested_at, unless: :review_requested_at?
  after_save :after_save
  after_commit :publish_transition_to_hydro, if: :state_previously_changed?

  # States of an advisory review.
  # As we re-use the same advisory review for different sources
  # This state could go back to 'open' at anytime.
  #
  # open: Initial state. An open advisory review.
  #   Review has not started.
  # closed: The system has closed the review. Probably
  #   because of a filter on advisories we ignore.
  # accepted: The advisory was published. That means
  #   the Curator decided to create or update the Advisory.
  # rejected: The review was closed manually, by a human.
  #   It means we chose not to publish that Advisory.
  # in_review: Curators have begin saving changes to the review,
  #   thus it started with the review process for that advisory.
  # approved_to_publish: The advisory was approved for publication
  #  by one curator, another curator needs to accept the publication.
  # approved_to_withdraw: The advisory was approved for withdrawal
  #  by one curator, another curator needs to accept the withdrawal.
  enum :state, { open: 0, closed: 1, accepted: 2, rejected: 3, in_review: 4, approved_to_publish: 5, approved_to_withdraw: 6 }

  aasm column: :state, enum: true, whiny_persistence: true do
    state :open, initial: true
    state :closed
    state :rejected
    state :in_review
    state :approved_to_publish
    state :approved_to_withdraw
    state :accepted

    event :reopen_approved_from_new_feed, after_commit: :clear_last_approval do
      transitions from: [:approved_to_publish, :approved_to_withdraw], to: :in_review
    end

    event :reopen_accepted_from_new_feed do
      transitions from: :accepted, to: :in_review, guard: :reviewed_advisory?
      transitions from: :accepted, to: :open
      before :set_review_requested_at
    end

    event :reopen_closed_from_new_feed do
      transitions from: [:closed, :rejected],
        to: :open,
        guard: :non_nvd_feed_entry?
    end

    event :restart_review do
      transitions from: :rejected, to: :in_review
      transitions from: :closed, to: :in_review
    end

    event :start_review do
      transitions from: :open, to: :in_review
    end

    event :approve_to_publish do
      transitions from: [:open, :in_review], to: :approved_to_publish
    end

    event :approve_to_withdraw do
      transitions from: [:open, :in_review], to: :approved_to_withdraw
    end

    event :accept do
      transitions from: [:open, :in_review, :approved_to_publish, :approved_to_withdraw], to: :accepted
    end

    event :reject do
      transitions from: [:open, :in_review, :approved_to_publish], to: :rejected
    end

    event :close do
      transitions from: :open, to: :closed
    end

    event :reopen do
      transitions from: :closed, to: :open
    end

    event :revisit do
      transitions from: :accepted, to: :in_review
      before :set_review_requested_at
    end

    event :merge do
      transitions from: [:open, :in_review, :rejected, :approved_to_publish, :approved_to_withdraw, :accepted],
        to: :closed
    end

    # Deliver stats tell us what state transitions are happening
    after_all_transitions do
      AdvisoryDB.stats.increment(
        "advisory_review.transition",
        tags: AdvisoryDB.dogtags(
          from: aasm.from_state,
          to: aasm.to_state,
          event: aasm.current_event.to_s.delete_suffix("!"), # trim the final "!" off the event name so we get "start_review", not "start_review!"
        ),
      )
    end
  end

  # return the advisory review that goes with the feed entry
  # returns nil if no advisory review currently exists
  def self.find_advisory_review_for_feed_entry(feed_entry)
    # use the advisory review attached to the feed entry, if one is already attached
    advisory_review = feed_entry.advisory_review
    return advisory_review if advisory_review

    if feed_entry.ghsa_id.present?
      # feed entries with ghsa id defined (repo advisories) **must** get attached to an advisory-review with the same ghsa id
      # even if the feed entry has a cve id that matches a different advisory review
      advisory_review ||= find_by(ghsa_id: feed_entry.ghsa_id)
    else
      # feed entries without ghsa id defined can get attached to any existing advisory review with any suitable matching id secondary id

      # Check white source id
      advisory_review ||= find_by(white_source_id: feed_entry.white_source_id) if feed_entry.white_source_id.present?
      # check friends of php id
      advisory_review ||= find_by(friends_of_php_id: feed_entry.friends_of_php_id) if feed_entry.friends_of_php_id.present?
      # check rubysec id
      advisory_review ||= find_by(rubysec_id: feed_entry.rubysec_id) if feed_entry.rubysec_id.present?
      # check npm id
      advisory_review ||= find_by(npm_id: feed_entry.npm_id) if feed_entry.npm_id.present?
      # check rustsec id
      advisory_review ||= find_by(rustsec_id: feed_entry.rustsec_id) if feed_entry.rustsec_id.present?

      # LAST: check cve id
      # cve id should be checked last because there is a feature for dealing with cases where cve ID "overlaps"
      # if above ids match some advisory review without a cve, and some other advisory review has the cve,
      # a banner on the review page will help the curator resolve it.
      advisory_review ||= find_by(cve_id: feed_entry.cve_id) if feed_entry.cve_id.present?
    end

    advisory_review
  end

  def self.build_blank
    new(
      ghsa_id: generate_unique_ghsa_id,
      state: "in_review",
      advisory_payload: {},
    )
  end

  # Only open or closed advisory reviews are subject to the blocklist. To build
  # the text content for each advisory review, we need its feed entries, so we
  # preload those here.
  #
  # By default, all blocklisted terms are loaded into memory and applied to all
  # eligible advisory reviews. Or a subset of blocklisted terms can be provided.
  def self.apply_blocklist(blocklisted_terms: BlocklistedTerm.all.to_a)
    where(state: %w[open closed]).preload(:feed_entries).find_each do |advisory_review|
      advisory_review.apply_blocklist(blocklisted_terms: blocklisted_terms)
    end
  end

  def self.severity_order_sql
    Arel.sql(<<~SQL.squish)
      CASE REGEXP_SUBSTR(advisory_reviews.advisory_payload, '(?m)(?<=^severity: )[:alpha:]+$')
        WHEN 'low' THEN 40
        WHEN 'moderate' THEN 30
        WHEN 'high' THEN 20
        WHEN 'critical' THEN 10
        ELSE 100
      END
    SQL
  end

  def to_param
    ghsa_id
  end

  def curation_state
    if open? || in_review?
      if cve_review_feed_entry && !repository_advisory_feed_entry
        "waiting"
      elsif reviewed_advisory?
        "open_update"
      else
        "open_create"
      end
    elsif closed? || rejected?
      "closed"
    elsif approved_to_publish?
      "ready_to_publish"
    elsif approved_to_withdraw?
      "ready_to_withdraw"
    elsif accepted?
      if advisory&.withdrawn?
        "withdrawn"
      elsif reviewed_advisory?
        "published_reviewed"
      else
        "published_unreviewed"
      end
    end
  end

  def read_only?
    read_only_reason.present?
  end

  def read_only_reason
    if closed? || rejected?
      :closed
    elsif accepted?
      :advisory_published
    end
  end

  def before_save
    # Curious about why we're not doing a full normalize here?
    # Our current status quo is that data is *not* normalized when saved.
    # This means that unnormalized data can make it's way into what's saved for us.
    # Adding a full normalization pass here will surprise other parts of the code.
    # We have some checks etc that seem to rely on normalization failures to signal
    #  the check should fail, so normalization is something that we do before publication,
    #  but not reliably before save.
    # This is something that could be changed to help make the system more predictable.
    advisory_payload["description"] = AdvisoryDBToolkit.normalize_description_line_endings(advisory_payload["description"]) if advisory_payload["description"].present?

    return unless advisory_payload["references"].is_a?(Array)

    advisory_payload["references"] =
      AdvisoryDBToolkit::ReferenceSorter.sorted_reference_list(advisory_payload["references"])
  end

  def after_save
    # Why after_save?
    # > Note that this callback is still wrapped in the transaction around save.
    # https://apidock.com/rails/ActiveRecord/Callbacks/after_save
    if AdvisoryDB::Features.enabled?("advisory_db_structured_payload_double_write")
      AdvisoryDB::AdvisoryPayloadConverter.upsert_structured_payload_for_advisory_payload(self, dry_run: false)
    end

    # returning false will cause this method to cancel the callback chain, we explicitly return true for clarity.
    true
  end

  def record_approval(user_id)
    # Find my assigned approval
    approval = approvals.current_review_request.unapproved.where(user_id: user_id).first
    # Use an already assigned approval
    approval ||= approvals.current_review_request.unapproved.first
    # Create a missing approval
    approval ||= approvals.build

    approval.update!(user_id: user_id, approved_at: Time.current)
  end

  def title
    summary || description || cve_id || ghsa_id
  end

  def summary
    advisory_payload["summary"].presence
  end

  def description
    advisory_payload["description"].presence
  end

  def source_code_location
    advisory_payload["source_code_location"].presence
  end

  def severity
    advisory_payload["severity"].presence
  end

  def references
    advisory_payload.fetch("references") { [] }
  end

  def cvss_v3
    advisory_payload["cvss_v3"]
  end

  def cvss_v4
    advisory_payload["cvss_v4"]
  end

  def cwe_ids
    advisory_payload["cwe_ids"].presence || []
  end

  def vulnerabilities
    advisory_payload.fetch("vulnerabilities") { {} }
  end

  def withdrawn?
    advisory_payload["withdrawn"] == true
  end

  def may_withdraw?
    may_accept? && advisory.present? && !advisory.withdrawn?
  end

  def withdraw!
    advisory_payload["withdrawn"] = true
    save!
  end

  def may_revert?
    may_accept? && advisory.present?
  end

  def revert!
    vulnerabilities = advisory.vulnerabilities_hash

    assign_attributes(advisory_payload: {
      cvss_v3: advisory.cvss_v3,
      cvss_v4: advisory.cvss_v4,
      description: advisory.description,
      severity: advisory.severity,
      source_code_location: advisory.source_code_location,
      summary: advisory.summary,
      references: advisory.references.pluck(:url),
      vulnerabilities: vulnerabilities,
      cwe_ids: advisory.cwe_ids,
      withdrawn: advisory.withdrawn?,
    })
    accept!

    prs_to_close = []
    pending_advisory_improvements.each do |feed_entry|
      pr_number = feed_entry.raw_payload["pr_number"].presence
      prs_to_close.push(pr_number) if pr_number

      # This won't be neded when we add credits to the advisory payload (https://github.com/github/team-advisory-database/issues/2420),
      # but for now we need a way to make sure we don't automatically credit these folks as contributors.
      feed_entry.raw_payload["rejected"] = true
      feed_entry.save!
    end

    if prs_to_close.present?
      ResolveAdvisoryPRsJob.perform_later(ghsa_id: ghsa_id, pr_numbers: prs_to_close, merge: false)
    end
  end

  def auto_closable?
    return false if advisory
    return false if non_nvd_feed_entry?
    return false if cve_id.blank?
    return false if cve_review.present?

    # Autoclosable if it is rejected or if it was withdrawn before we published the advisory.
    advisory_payload["description"].include?("** REJECT **")
  end

  def held_from_publishing?
    labels.any? { |label| label.label_settings.hold_publication? }
  end

  def cve_url
    cve_id? ? "https://nvd.nist.gov/vuln/detail/#{cve_id}" : nil
  end

  def nvd_published_at
    timestamp = nil
    feed_entries.where(source: "nvd").find_each do |entry|
      # The timestamp used to be stored as `publishedDate`, but now it's `published`
      timestamp = entry.raw_payload["publishedDate"]&.to_datetime
      timestamp ||= entry.raw_payload["published"]&.to_datetime

      break if timestamp
    end
    timestamp
  end

  # Evaluates the advisory review against blocklisted terms. By default, all
  # blocklisted terms are applied. Blocklist matches are only added or removed
  # if their blocklisted terms are among those given.
  def apply_blocklist(blocklisted_terms: BlocklistedTerm.all.to_a)
    with_lock do
      matching_terms = []
      text_content = nil

      blocklisted_terms.each do |blocklisted_term|
        case blocklisted_term.term_type
        when "cna"
          matching_terms.concat(build_cna(blocklisted_term: blocklisted_term))
        when "cpe"
          matching_terms.concat(build_cpe(blocklisted_term: blocklisted_term))
        else
          text_content ||= build_text_content
          if text_content.present? && blocklisted_term.match?(text_content)
            matching_terms << blocklisted_term
          end
        end
      end

      current_terms = self.blocklisted_terms.to_a
      terms_to_remove = blocklisted_terms & (current_terms - matching_terms)
      terms_to_add = blocklisted_terms & (matching_terms - current_terms)
      new_terms = current_terms - terms_to_remove + terms_to_add

      self.blocklisted_terms = new_terms

      if open? && self.blocklisted_terms.removes_from_curation.present?
        may_revert? ? revert! : close!
      end
    end
  end

  def clear_last_approval
    approvals.approved.last.update!(approved_at: nil)
  end

  def required_approvals?
    approvals.approved.size >= AdvisoryReviewApproval::REQUIRED_APPROVAL_COUNT
  end

  def reviewed_advisory?
    advisory&.reviewed?
  end

  def non_nvd_feed_entry?
    feed_entries.any? { |fe| fe.source != NVDImporter.source }
  end

  def cve_review_feed_entry?
    feed_entries.any? { |fe| fe.source == CVEReviewImporter.source }
  end

  def repository_advisory_feed_entry?
    feed_entries.any? { |fe| fe.source == RepositoryAdvisoriesImporter.source }
  end

  def malware_feed_entry?
    feed_entries.any? { |fe| fe.source == MalwareAdvisoryImporter.source }
  end

  def overlapping_advisory_reviews
    if cve_id
      AdvisoryReview
        .joins(:feed_entries)
        .distinct
        .where(
          cve_id: nil,
          feed_entries: { cve_id: cve_id },
        )
    else
      cve_ids = feed_entries.distinct.where.not(cve_id: nil).pluck(:cve_id)

      if cve_ids.any?
        AdvisoryReview.where(cve_id: cve_ids)
      else
        AdvisoryReview.none
      end
    end
  end

  def pending_advisory_improvements
    return [] unless advisory

    feed_entries.where(
      source: AdvisoryImprovementImporter.source,
      resolution_state: "resolved",
    ).filter do |feed_entry|
      # This won't be neded when we add credits to the advisory payload (https://github.com/github/team-advisory-database/issues/2420),
      # but for now we need a way to make sure we don't automatically credit these folks as contributors.
      feed_entry.updated_at > advisory.updated_at && !feed_entry.raw_payload["rejected"]
    end
  end

  def body_version
    return "" unless versions.last

    versions.last.id.to_s
  end

  def record_curation_decision(type:, decision:, curator:)
    if campaigns.active.present?
      unless decision == "open" || decision.starts_with?("ready_to_")
        advisory_reviews_campaigns.pending.each { |campaign_review| campaign_review.update(reviewed_at: Time.current) }
      end

      return
    end

    last_state_change = versions.reverse.find { |version| version.changeset.include?(:state) || version.changeset.include?(:created_at) }
    time_to_decision = Time.current - last_state_change.created_at

    if in_review? && cve_review_feed_entry && repository_advisory_feed_entry && repository_advisory_feed_entry.created_at > cve_review_feed_entry.created_at
      time_spent_waiting = repository_advisory_feed_entry.created_at - [last_state_change.created_at, cve_review_feed_entry.created_at].max
      time_to_decision -= time_spent_waiting if time_spent_waiting > 0
    end

    PublishCurationDecisionToHydroJob.perform_later(
      type: type,
      decision: decision,
      curator: curator,
      ghsa_id: ghsa_id,
      sources: feed_entries.map(&:source).uniq,
      time_to_decision: time_to_decision,
    )
  end

  def notify_user_saved_event(user = nil)
    PublishAdvisoryReviewSavedToHydroJob.perform_later(
      hydro_payload,
      changed_attributes: saved_changes.keys,
      old_delta: hydro_payload(saved_changes.keys.map(&:to_sym).index_with { |key| saved_changes[key][0] }),
      new_delta: hydro_payload(saved_changes.keys.map(&:to_sym).index_with { |key| saved_changes[key][1] }),
      saved_by: user.login,
    )
  end

  # we use this method to convert advisory review attributes to a publishable hydro message
  def hydro_payload(from = nil)
    from = self if from.nil?
    event = {}

    set_if_specified(event, :id, from)
    set_if_specified(event, :created_at, from)
    set_if_specified(event, :updated_at, from)
    set_if_specified(event, :review_requested_at, from)
    event[:advisory_payload] = AdvisoryPayload.new(data: from[:advisory_payload]).hydro_payload if from[:advisory_payload].present?

    set_if_specified(event, :ghsa_id, from)
    set_if_specified(event, :cve_id, from)
    set_if_specified(event, :state, from)
    set_if_specified(event, :white_source_id, from, to_s: true)
    set_if_specified(event, :friends_of_php_id, from, to_s: true)
    set_if_specified(event, :rubysec_id, from, to_s: true)
    set_if_specified(event, :npm_id, from, to_s: true)
    set_if_specified(event, :rustsec_id, from, to_s: true)
    set_if_specified(event, :review_notes, from)
    set_if_specified(event, :default_ecosystem, from)
    event
  end

  private

  def set_if_specified(event, property_name, from, to_s: false)
    value = from[property_name]
    if value.present?
      value = value.to_s if to_s
      event[property_name] = value
    end
  end

  def build_text_content
    parts = [
      advisory_payload["summary"],
      advisory_payload["description"],
    ]

    feed_entries.each do |feed_entry|
      next unless feed_entry.subject_to_blocklist?

      parts << feed_entry.advisory_payload["summary"]
      parts << feed_entry.advisory_payload["description"]
    end

    parts.compact_blank!
    parts.join("\n")
  end

  def build_cna(blocklisted_term: nil)
    matching_terms = []
    feed_entries.each do |feed_entry|
      next unless feed_entry.subject_to_blocklist?

      cna = feed_entry.cna
      if blocklisted_term.match?(cna)
        matching_terms << blocklisted_term
      end
    end
    matching_terms
  end

  def build_cpe(blocklisted_term: nil)
    matching_terms = []
    feed_entries.each do |feed_entry|
      next unless feed_entry.subject_to_blocklist?

      feed_entry.cpe_match_criteria&.each do |criteria|
        matching_terms << blocklisted_term if blocklisted_term.match?(criteria)
      end
    end
    matching_terms
  end

  def set_review_requested_at
    self.review_requested_at = Time.current
  end

  def publish_transition_to_hydro
    old_state, new_state = previous_changes.fetch(:state)

    feed_entries.each do |feed_entry|
      PublishChangeFeedEntryStateToHydroJob.perform_later(
        feed_entry,
        old_state: old_state&.to_s,
        new_state: new_state&.to_s,
      )
    end
  end

  def clear_empty_cve_id
    self.cve_id = cve_id.presence
  end
end
