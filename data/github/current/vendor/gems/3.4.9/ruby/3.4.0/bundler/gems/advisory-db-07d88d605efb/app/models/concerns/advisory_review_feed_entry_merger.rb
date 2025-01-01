# frozen_string_literal: true

class AdvisoryReviewFeedEntryMerger
  PAYLOAD_KEYS_ALLOWED_TO_AUTO_ACCEPT = %w[cwe_ids cvss_v3 cvss_v4 references].freeze
  APPROVED_REFERENCES_DOMAINS_REGEX = Regexp.union(%w[
    https://www.oracle.com/security-alerts
    https://lists.fedoraproject.org
    https://lists.debian.org
    https://www.debian.org
    https://lists.apache.org
    https://www.openwall.com/lists/
    https://nvd.nist.gov/
    https://security.netapp.com/advisory
    https://access.redhat.com
    https://bugzilla.redhat.com
  ]).freeze

  attr_reader :advisory_review, :feed_entry, :feed_entry_changes

  def self.merge(feed_entry)
    new(feed_entry).merge
  end

  def initialize(feed_entry)
    @feed_entry = feed_entry
    @feed_entry_changes = feed_entry.unresolved_changes
    @advisory_review = AdvisoryReview.find_advisory_review_for_feed_entry(feed_entry)
  end

  def merge
    needs_republish = false

    if advisory_review
      log("Merging feed entry data into existing advisory review")
      update_advisory_review
    else
      log("Merging feed entry data into new advisory review")
      create_advisory_review
    end

    if feed_entry_changes.blank?
      log("Skipping publication/curation for feed entry data matching advisory review")
      return advisory_review, needs_republish
    end

    if advisory_review.auto_closable?
      log("Skipping publication/curation on feed merge for auto-closable advisory review")
      advisory_review.close! if advisory_review.may_close?
      return advisory_review, needs_republish
    end

    if advisory_changes_auto_publishable?
      log("Auto-publishing advisory review's merged feed data")
      should_skip_curation = feed_changes_may_skip_curation? # record this before the advisory gets updated
      published_advisory = auto_publish
      # If we get here, there is a chance that publication occurred and so we need to republish after our current "stack" of transactions is committed.
      # This is the caller's responsibility.
      needs_republish = true

      if published_advisory && should_skip_curation
        log("Skipping curation for auto-published feed merge")
        advisory_review.accept! if advisory_review.open?
        return advisory_review, needs_republish
      end
    end

    if feed_entry.subject_to_blocklist?
      log("Applying blocklist from new feed data")
      advisory_review.apply_blocklist
    end

    if advisory_review.blocklisted_terms.removes_from_curation.present?
      log("Advisory review skipping curation from a blocking term")
      return advisory_review, needs_republish
    end

    if advisory_review.may_reopen_accepted_from_new_feed?
      advisory_review.reopen_accepted_from_new_feed!
      log("Reopened accepted advisory review for curation of new feed data")
    elsif advisory_review.may_reopen_approved_from_new_feed?
      advisory_review.reopen_approved_from_new_feed!
      log("Reopened approved advisory review for curation of new feed data")
    elsif advisory_review.may_reopen_closed_from_new_feed? && feed_entry.source != NVDImporter.source
      advisory_review.reopen_closed_from_new_feed!
      log("Reopened rejected advisory review for curation of new feed data")
    end

    [advisory_review, needs_republish]
  end

  def importer_auto_publish
    if advisory_changes_auto_publishable? # this should never not be true but safety check just in case
      auto_publish
    end
  end

  private

  def log(message)
    ::GitHub::Telemetry::Logs.logger.info(
      message,
      "gh.advisory_inbox.feed_entry.id": feed_entry.id,
      "gh.ghsa_id": advisory_review&.ghsa_id,
    )
  end

  def create_advisory_review
    @advisory_review = AdvisoryReview.create!(
      ghsa_id: feed_entry.ghsa_id.presence || GHSAIDGenerator.generate_unique_ghsa_id,
      friends_of_php_id: feed_entry.friends_of_php_id,
      rubysec_id: feed_entry.rubysec_id,
      npm_id: feed_entry.npm_id,
      rustsec_id: feed_entry.rustsec_id,
      state: "open",
      advisory_payload: feed_entry.advisory_payload,
      cve_id: feed_entry_cve_identifier,
      default_ecosystem: feed_entry.ecosystem,
    )
    feed_entry.update!(advisory_review_id: advisory_review.id)
    log("Merged feed entry data into new advisory review")
  end

  def update_advisory_review
    if feed_entry.advisory_review_id.nil?
      feed_entry.update!(advisory_review_id: advisory_review.id)
      @feed_entry_changes = feed_entry.unresolved_changes # removes "changes" that the advisory already has
    end

    if feed_entry_changes.present?
      merge_feed_entry
      log("Merged feed entry data into existing advisory review")
    else
      log("Feed entry has no data to merge into existing advisory review")
    end
  end

  def advisory_changes_auto_publishable?
    # Malware feeds are always auto-publishable as the review is done by the folks reporting them
    return true if advisory_review.malware_feed_entry?

    # Only additive references from the approved list are auto-publishable for already reviewed advisories
    if advisory_review.accepted? && advisory_review.reviewed_advisory?
      advisory_changes = Publisher.new(advisory_review).changeset

      return false unless advisory_changes.keys == ["references"]

      references_removed = advisory_changes["references"][0] - advisory_changes["references"][1]
      references_added = advisory_changes["references"][1] - advisory_changes["references"][0]

      return references_removed.empty? && references_added.all? { |url| url.starts_with?(APPROVED_REFERENCES_DOMAINS_REGEX) }
    end

    # New/updated unreviewed NVD feeds are auto-publishable when not actively in-review
    (advisory_review.open? || advisory_review.accepted?) && !advisory_review.reviewed_advisory? && !advisory_review.non_nvd_feed_entry?
  end

  def auto_publish
    # By using 'suppress_transaction_check: true' we are signing up to republish the advisory after this code completes.
    advisory = Publisher.new(advisory_review).auto_publish(suppress_transaction_check: true)
    log("Auto-publised advisory review's merged feed data")

    advisory
  rescue StandardError => error
    raise if error.is_a? Publisher::NestedTransactionError

    Failbot.report!(error, { ghsa_id: advisory_review.ghsa_id })
    log("Failed to auto-publish advisory review's merged feed data")

    nil
  end

  # We can auto-accept unpublished advisories if they are too old to be curatable or are malware.
  # We don't need to reopen accepted unreviewed advisories in the following situations:
  # - New CWEs were added
  # - CVSS was nil and a score was added
  # - New references were added
  # We don't need to reopen accepted reviewed advisories in the following situations:
  # - New references were added from the approved list of domains
  # - They are malware
  # If ANY OTHER CHANGES are included in a new/updated feed entry, they NEED to be seen by a
  # human as the info may change the decision about whether or not the advisory should be curated!
  def feed_changes_may_skip_curation?
    return false unless advisory_changes_auto_publishable?
    return false unless advisory_review.valid?
    return true if advisory_review.malware_feed_entry?

    if advisory_review.accepted? && advisory_review.reviewed_advisory?
      # Not auto-acceptable if the incoming information has any changes aside from references
      return false unless feed_entry_changes.keys == ["advisory_payload"] && feed_entry_changes["advisory_payload"].keys == ["references"]

      # Only auto-acceptable if they are a strict superset of the current published values & belong to the approved domains list
      references_removed, references_added = collection_changes("references", advisory_review.advisory.references.pluck(:url))
      return references_removed.empty? && references_added.all? { |url| url.starts_with?(APPROVED_REFERENCES_DOMAINS_REGEX) }
    elsif advisory_review.accepted? && advisory_review.advisory && !advisory_review.reviewed_advisory?
      # Not auto-acceptable if the incoming information has any changes aside from CVSS, CWEs, or references
      return false unless feed_entry_changes.keys == ["advisory_payload"] && (feed_entry_changes["advisory_payload"].keys - PAYLOAD_KEYS_ALLOWED_TO_AUTO_ACCEPT).empty?

      # If CVSS is changing, it is only auto-acceptable if the current value is blank
      return false if feed_entry_changes["advisory_payload"]["cvss_v3"] && advisory_review.advisory.cvss_v3.present?

      # If CVSS is changing, it is only auto-acceptable if the current value is blank (v4 as well)
      return false if feed_entry_changes["advisory_payload"]["cvss_v4"] && advisory_review.advisory.cvss_v4.present?

      # If CWEs are changing, only auto-acceptable if they are a strict superset of the current values
      cwe_ids_removed, _cwe_ids_added = collection_changes("cwe_ids", advisory_review.advisory.cwe_ids)
      return false if cwe_ids_removed.present?

      # If references are changing, only auto-acceptable if they are a strict superset of the current published values
      references_removed, _references_added = collection_changes("references", advisory_review.advisory.references.pluck(:url))
      return false if references_removed.present?

      return true
    end

    return false if advisory_review.cve_id.blank?
    return false if advisory_review.cve_review.present?

    cve_year = advisory_review.cve_id.slice(AdvisoryDBToolkit::CVEIDValidator::PATTERN, :year)

    cve_year.to_i < CVEItem::MIN_CURATABLE_YEAR
  end

  def collection_changes(attribute, published_collection)
    return [nil, nil] if feed_entry_changes["advisory_payload"][attribute].blank?

    feed_removed = feed_entry_changes["advisory_payload"][attribute].filter_map { |value| value.starts_with?("-") && value[1..] }
    feed_added = feed_entry_changes["advisory_payload"][attribute].reject { |value| value.starts_with?("-") }

    advisory_removed = feed_removed.select { |value| published_collection.include?(value) }
    advisory_added = feed_added - published_collection

    [advisory_removed, advisory_added]
  end

  # Updates the advisory review with any additive feed entry data. This does not
  # represent all information from a feed that may be relevant, just removes some
  # of the manual process of a curator needing to copy new data over when we think
  # it's likely to be relevant. For updates to existing information, a human needs
  # to determine how to incorporate the new data against the existing data.
  def merge_feed_entry
    return if AdvisoryDB.untrusted_sources.include?(feed_entry.source)

    merge_feed_entry_identifiers
    merge_feed_entry_references
    merge_feed_entry_cwe_ids
    merge_feed_entry_vulnerabilities
    merge_feed_entry_description
    merge_feed_entry_advisory_payload

    advisory_review.save! if advisory_review.changed?
  end

  def merge_feed_entry_identifiers
    advisory_review.default_ecosystem = feed_entry.ecosystem         if advisory_review.default_ecosystem.blank?
    advisory_review.friends_of_php_id = feed_entry.friends_of_php_id if advisory_review.friends_of_php_id.blank?
    advisory_review.rubysec_id        = feed_entry.rubysec_id        if advisory_review.rubysec_id.blank?
    advisory_review.npm_id            = feed_entry.npm_id            if advisory_review.npm_id.blank?
    advisory_review.rustsec_id        = feed_entry.rustsec_id        if advisory_review.rustsec_id.blank?
    advisory_review.cve_id            = feed_entry_cve_identifier    if advisory_review.cve_id.blank?
  end

  def feed_entry_cve_identifier
    # if the feed entry is from a repository_advisory and it specifies a cve_id,
    # it's possible that an advisory review already exists with that same
    # cve_id (i.e. because it was ingested thru the NVD feed).
    #
    # because we can't trust the repository_advisory input is correct, and
    # we consider advisory reviews to be unique on cve_ids, if an advisory review
    # with this specified cve id already exists, then we leave it off this review.
    #
    # there is a feature for dealing with cases where cve ID "overlaps" between one review
    # and feed entries of another: a banner calls this out and a curator can "merge" reviews
    if feed_entry.cve_id.present? && !AdvisoryReview.exists?(cve_id: feed_entry.cve_id)
      return feed_entry.cve_id
    end

    nil
  end

  def merge_feed_entry_references
    advisory_review.advisory_payload["references"] = AdvisoryDBToolkit::ReferenceSorter.sorted_reference_list(
      advisory_review.advisory_payload.fetch("references", []) +
      feed_entry.advisory_payload.fetch("references", []),
    )
  end

  def merge_feed_entry_cwe_ids
    advisory_review.advisory_payload["cwe_ids"] = (
      (advisory_review.advisory_payload["cwe_ids"] || []) +
      (feed_entry.advisory_payload["cwe_ids"] || [])
    ).sort_by { |number| number.scan(/\d+/).first.to_i }.uniq
  end

  def merge_feed_entry_vulnerabilities
    # uniqueness constraints only apply to non-withdrawn vulns, so we want to
    # map the unique key to the correct non-withdrawn index to update
    unique_vuln_indexes = {}

    advisory_review.advisory_payload["vulnerabilities"] ||= {}
    advisory_review.advisory_payload["vulnerabilities"].each do |i, vuln|
      unique_vuln_indexes[unique_vulnerability_key(vuln)] = i unless vuln["withdrawn"]
    end

    # merge in or add any new non-withdrawn vulns based on the cached inexes
    feed_entry.advisory_payload.fetch("vulnerabilities", {}).each_value do |new_vuln|
      next if new_vuln["withdrawn"]

      unique_key = unique_vulnerability_key(new_vuln)
      existing_vuln_index = unique_vuln_indexes[unique_key]

      if existing_vuln_index.present?
        existing_vuln = advisory_review.advisory_payload["vulnerabilities"][existing_vuln_index]
        merge_vulnerability_data(existing_vuln, new_vuln)
      else
        new_index = advisory_review.advisory_payload["vulnerabilities"].length

        advisory_review.advisory_payload["vulnerabilities"][new_index] = new_vuln
        unique_vuln_indexes[unique_key] = new_index
      end
    end
  end

  def unique_vulnerability_key(vuln)
    "#{vuln["ecosystem"]}|#{vuln["package_name"]}|#{vuln["vulnerable_version_range"]}"
  end

  def merge_vulnerability_data(existing_vuln, new_vuln)
    existing_vuln["first_patched_version"] = new_vuln["first_patched_version"] if existing_vuln["first_patched_version"].blank?
  end

  def merge_feed_entry_description
    return unless feed_entry.source == RepositoryAdvisoriesImporter.source

    advisory_review.advisory_payload["description"] = feed_entry.advisory_payload["description"]
  end

  def merge_feed_entry_advisory_payload
    new_payload = advisory_review.advisory_payload
    feed_entry.advisory_payload.each do |key, value|
      new_payload[key] = value if new_payload[key].blank?
    end
    advisory_review.advisory_payload = new_payload
  end
end
