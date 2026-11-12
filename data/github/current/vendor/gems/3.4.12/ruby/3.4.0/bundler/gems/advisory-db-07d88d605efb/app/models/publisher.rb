# frozen_string_literal: true

require "digest/md5"

class Publisher
  include ActiveModel::Validations
  include Diffable

  # Override the default validation context so that validations on this
  # class use the full suite of validations available on AdvisoryPayload
  DEFAULT_VALIDATION_CONTEXT = :publication

  validates :ghsa_id, ghsa_id: true, presence: true
  validate :advisory_review_must_be_an_advisory_review
  validate :advisory_review_must_be_persisted
  validate :advisory_review_must_be_unchanged
  validate :advisory_review_must_be_acceptable_or_accepted, on: :autopublication
  validate :advisory_review_must_be_acceptable, on: :publication
  validate :advisory_review_must_be_approved, on: :publication
  validate :advisory_review_cwes_must_exist
  validates :advisory_payload, nested: true
  validates :advisory_summary, presence: true, length: { maximum: 255 }, on: :publication

  attr_reader :advisory_review, :validation_context

  class NestedTransactionError < StandardError; end

  def initialize(advisory_review)
    @advisory_review = advisory_review
    @validation_context = DEFAULT_VALIDATION_CONTEXT
  end

  def auto_publish(merger: nil, suppress_transaction_check: false)
    # This should look weird: as a mitigation, we are going to allow a suppressed transaction check for some auto_publication.
    # This is *mostly* due to how convuluted trying to decompose the publication flow from the feed entry merging is.
    # We probably should be redesigning that code to more predictably have committed transactions + issued publications.
    # If a caller uses suppress_transaction_check: true, MAKE SURE to republish the advisory *AFTER* transaction completion is done.
    ensure_no_parent_transactions unless suppress_transaction_check

    advisory = Advisory.transaction do
      merger&.send(:merge_feed_entry)

      @validation_context = :autopublication
      address_fixable_errors

      publish_to_the_database(reviewed: advisory_review.reviewed_advisory? || advisory_review.malware_feed_entry?, merger: merger)
    end

    publish_externally(advisory)

    @validation_context = DEFAULT_VALIDATION_CONTEXT

    advisory
  end

  def publish(approve_as_user: nil, withdraw_advisory_review: false)
    ensure_no_parent_transactions

    advisory, advisory_improvements = Advisory.transaction do
      if approve_as_user.present?
        advisory_review.record_approval(approve_as_user)
      end

      unless advisory_review.required_approvals?
        raise ApprovalsNotMetError("Required approvals were not present for advisory publication.")
      end

      AdvisoryReview.transaction do
        if withdraw_advisory_review
          advisory_review.withdraw!
        end
      end

      validate!(@validation_context) # Raises a ValidationError unless all validations pass

      advisory_improvements = advisory_review.pending_advisory_improvements
      advisory = publish_to_the_database
      [advisory, advisory_improvements]
    end

    publish_externally(advisory, advisory_improvements)

    advisory
  end

  def simulate
    # Changes made to the database will be rolled back. See below.
    AdvisoryDB::GlobalVariables.assign_in_simulated_publication(true) do
      Advisory.transaction do
        advisory_review.record_approval(User.first.id) unless advisory_review.required_approvals?
        advisory_review.record_approval(User.first.id) unless advisory_review.required_approvals?

        validate!(@validation_context) # Raises a ValidationError unless all validations pass

        publish_to_the_database

        # Raising an ActiveRecord::Rollback error causes the database transaction
        # to roll back, resulting in no changes being made to the database, as is
        # the behavior for any exception raised in a transaction block. The
        # ActiveRecord::Rollback error is special in that it's not re-raised. The
        # transaction block will exit cleanly.
        raise ActiveRecord::Rollback
      end

      # Reload so the DB rollback is reflected in memory
      advisory_review.reload
      true
    rescue StandardError => error
      ::GitHub::Telemetry::Logs.logger.error(
        "Error during executing simulated publication for advisory",
        exception: error,
        "gh.ghsa_id": advisory_review.ghsa_id,
      )
      errors.add(:advisory_review, :unexpected_error, message: "The advisory_review being published had an unexpected error during publication: #{error}. \n An advisory inbox developer should be able to help.")

      # Reload so the DB rollback is reflected in memory
      advisory_review.reload
      false
    end
  end

  def changeset
    advisory = Advisory.find_by(ghsa_id: ghsa_id)
    return {} unless advisory

    # We're doing this because of force_utf8_encoding's implementation.
    # https://github.com/github/advisory-db/blob/28707414e0d0465f16127aff5217a6e005a3cf3c/lib/github/encoding.rb#L34
    # Calls to the attribute will actually change the string value to match.
    # We wouldn't have to do this if we had a more elegant data access pattern, but as it is this is also
    # how dotcom handles encoding mismatches with the DB. There is probably a better pattern
    # that does something on a hook whenever a record has data loaded from a database, but this hack
    # works with our current approach in encoding.rb.
    # Suspected reason for the need: the full .Attributes property is used by changes,
    # and the monkey patch is limited to only individual property getters. :grimace:
    advisory.description
    copy_attributes(advisory)

    changes = advisory.changes

    if advisory.cwe_ids.sort != advisory_review.cwe_ids.sort
      changes["cwe_ids"] = [advisory.cwe_ids, advisory_review.cwe_ids]
    end

    advisory_references_without_blanks = advisory.references.pluck(:url).reject(&:empty?)
    advisory_review_references_without_blanks = advisory_review.references.reject(&:empty?)
    if advisory_references_without_blanks.to_set != advisory_review_references_without_blanks.to_set
      changes["references"] = [advisory_references_without_blanks, advisory_review_references_without_blanks]
    end

    normalized_vulnerabilities_advisory = AdvisoryPayload.new(data: { "vulnerabilities" => advisory.vulnerabilities_hash }).data["vulnerabilities"]
    normalized_vulnerabilities_review = AdvisoryPayload.new(data: { "vulnerabilities" => advisory_review.vulnerabilities }).data["vulnerabilities"]
    if normalized_vulnerabilities_advisory != normalized_vulnerabilities_review
      changes["vulnerabilities"] = [normalized_vulnerabilities_advisory, normalized_vulnerabilities_review]
    end

    changes
  end

  private

  def address_fixable_errors
    invalid_cwes = unknown_cwe_ids
    if invalid_cwes.present?
      advisory_review.advisory_payload["cwe_ids"] -= invalid_cwes
      advisory_review.save!
    end

    validate!(@validation_context)
  end

  def publish_externally(advisory, advisory_improvements = [])
    json_serialized_payload = JSON.dump(advisory.hydro_payload)
    ::GitHub::Telemetry::Logs.logger.info(
      log_body("Publishing advisory externally"),
      "gh.advisory_inbox.publisher.payload": json_serialized_payload,
      "gh.advisory_inbox.paper_trail_version_id": advisory.versions.last.id,
      "gh.advisory_inbox.publisher.backtrace": caller.join(","),
    )

    credits = advisory_improvements.map { |fe| { recipient_id: fe.raw_payload["actor_id"] } }
    prs_being_published = advisory_improvements.filter_map { |fe| fe.raw_payload["pr_number"].presence }

    # send to GitHub's Advisory Database
    PublishAdvisoryToHydroJob.perform_later(advisory, credits: credits)

    # send to github/advisory-database repo
    unless advisory_review.malware_feed_entry?
      AdvisorySyncState.enqueue(advisory)
      PushAdvisoriesToRepoJob.perform_later if ENV["FEATURE_FLAG_RUN_PUSH_ADVISORIES_TO_REPO_JOB"] == "true"
    end

    # report status to community contributors
    if prs_being_published.present?
      ResolveAdvisoryPRsJob.perform_later(ghsa_id: ghsa_id, pr_numbers: prs_being_published, merge: true)
    end
  end

  # Publication to the database needs to happen within one big database
  # transaction so the process is all or nothing. Only after publication to the
  # database succeeds should we enqueue any follow-up jobs that make calls to
  # external services.
  #
  # Returns a fresh instance of the published advisory on success. Any failure
  # to publish cleanly will raise an exception.
  # This method may be encompassed by another transaction, but that should only happen within the Publisher class itself.
  # ^ implies that this method should not do any async messaging (like w/ Hydro) inside its body, since data won't be guaranteed to be committed
  def publish_to_the_database(reviewed: true, merger: nil)
    Advisory.transaction do
      if advisory_review.held_from_publishing?
        raise AdvisoryDB::PublicationHeldError, "Cannot publish an advisory review that has a 'hold' label applied."
      end

      merger&.send(:merge_feed_entry)

      # Lock the advisory review and the target advisory (if it exists).
      advisory_review.lock!
      advisory = Advisory.lock.find_or_initialize_by(ghsa_id: ghsa_id)
      advisory.reviewed = reviewed
      copy_attributes(advisory)
      advisory.reviewed_at ||= Time.current if reviewed
      advisory.published_at ||= Time.current

      # Save the advisory in such a way that an error is raised and the
      # transaction is rolled back if validations, callbacks, or persistence
      # fails.
      advisory.save!

      advisory.cwe_ids = advisory_review.cwe_ids

      # Publish the advisory's references and update their indexes as needed.
      advisory_review.references.reject(&:empty?).each_with_index do |reference_url, index|
        reference = advisory.references.find_or_initialize_by(url: reference_url)

        reference.index = index
        reference.save!
      end
      advisory.references.where.not(url: advisory_review.references).destroy_all

      # Publish the advisory's vulnerabilities and update their indexes as
      # needed.
      advisory_review.vulnerabilities.each do |index, vulnerability_payload|
        vulnerability = advisory.vulnerabilities.find_or_initialize_by(index: index)

        vulnerability.package_ecosystem = vulnerability_payload.fetch("ecosystem")
        vulnerability.package_name = vulnerability_payload.fetch("package_name")
        vulnerability.severity = advisory.severity
        vulnerability.vulnerable_version_range = vulnerability_payload.fetch("vulnerable_version_range")
        vulnerability.first_patched_version = vulnerability_payload.fetch("first_patched_version")
        vulnerability.withdrawn_at = vulnerability_payload.fetch("withdrawn", false) == true ? Time.current : nil

        fix_commits_input = vulnerability_payload.fetch("fix_commits", [])
        fix_commits_input.each_with_index do |fix_commit_url, commit_index|
          fix_commit = vulnerability.fix_commits.find_or_initialize_by(commit_url: fix_commit_url)

          fix_commit.index = commit_index
          fix_commit.save!
        end

        vulnerability.fix_commits.where.not(commit_url: fix_commits_input).destroy_all
        vulnerability.save!
      end

      advisory_review.accept! if reviewed && !advisory_review.accepted?

      # Do a *full* reload of the advisory so we're sure we have the latest
      # information with nothing cached.
      return_this_advisory = Advisory.find(advisory.id)
      json_serialized_payload = JSON.dump(return_this_advisory.hydro_payload)
      ::GitHub::Telemetry::Logs.logger.info(
        log_body("Returning advisory after publishing to database, before a reload"),
        "gh.advisory_inbox.publisher.payload": json_serialized_payload,
        "gh.advisory_inbox.paper_trail_version_id": advisory.versions.last.id,
        "gh.advisory_inbox.hydro_payload_hash": Digest::MD5.hexdigest(json_serialized_payload),
        "gh.advisory_inbox.publisher.backtrace": caller.join(","),
      )

      return_this_advisory = return_this_advisory.reload
      json_serialized_payload = JSON.dump(return_this_advisory.hydro_payload)
      ::GitHub::Telemetry::Logs.logger.info(
        log_body("Returning advisory after publishing to database, after a reload"),
        "gh.advisory_inbox.publisher.payload": json_serialized_payload,
        "gh.advisory_inbox.paper_trail_version_id": advisory.versions.last.id,
        "gh.advisory_inbox.hydro_payload_hash": Digest::MD5.hexdigest(json_serialized_payload),
        "gh.advisory_inbox.publisher.backtrace": caller.join(","),
      )

      return_this_advisory
    end
  end

  def copy_attributes(advisory)
    # Copy attributes from the advisory review to the advisory.
    advisory.cve_id = advisory_review.cve_id
    advisory.white_source_id = advisory_review.white_source_id
    advisory.npm_id = advisory_review.npm_id
    advisory.summary = advisory_review.summary
    advisory.description = advisory_review.description
    advisory.source_code_location = advisory_review.source_code_location
    advisory.severity = advisory_review.severity
    advisory.cvss_v3 = advisory_review.cvss_v3
    advisory.cvss_v4 = advisory_review.cvss_v4
    advisory.nvd_published_at ||= advisory_review.nvd_published_at

    # Handle the withdrawn status of the advisory.
    if advisory_review.withdrawn?
      # Set the withdrawn_at timestamp (if it's not already set) to the
      # current time if the advisory should be withdrawn.
      advisory.withdrawn_at ||= Time.current
    else
      # Make sure the withdrawn_at timestamp is cleared if the advisory review
      # is not (or is no longer) withdrawn.
      advisory.withdrawn_at = nil
    end
  end

  def log_body(body)
    AdvisoryDB::GlobalVariables.in_simulated_publication? ? "[Simulation] #{body}" : body
  end

  def ghsa_id
    advisory_review.ghsa_id
  end

  def advisory_summary
    advisory_review.summary
  end

  # The advisory review provided must actually _be_ an AdvisoryReview.
  def advisory_review_must_be_an_advisory_review
    return if advisory_review.instance_of?(AdvisoryReview)

    errors.add(:advisory_review, :confused, class_name: advisory_review.class.name, message: "The advisory_review being published was not an AdvisoryReview object instance.")
  end

  # The advisory review must be persisted to the database.
  def advisory_review_must_be_persisted
    return if advisory_review.persisted?

    errors.add(:advisory_review, :unpersisted, message: "The advisory_review being published was not persisted to the database.")
  end

  # The advisory review must be free of unpersisted (dirty) attribute changes to
  # avoid any unintended strange behavior.
  def advisory_review_must_be_unchanged
    return unless advisory_review.changed?

    ::GitHub::Telemetry::Logs.logger.error(
      "Advisory review validation failed during publication because the advisory review was changed.",
      "gh.advisory_inbox.advisory_review.unpersisted_changes": advisory_review.changes.to_json,
      "gh.ghsa_id": advisory_review.ghsa_id,
    )
    errors.add(:advisory_review, :changed, changes: advisory_review.changes, message: "Advisory review validation failed during publication because the advisory review was changed. The following keys changed #{advisory_review.changes.keys}")
  end

  # The publication process transitions the advisory review's state to
  # "accepted" so we need to be able to make that transition successfully when
  # the time comes.
  def advisory_review_must_be_acceptable
    return if advisory_review.may_accept?

    errors.add(:advisory_review, :unacceptable, state: advisory_review.state, message: "The advisory_review being published was not able to be transitioned to Accepted.")
  end

  def advisory_review_must_be_acceptable_or_accepted
    return if advisory_review.accepted? || advisory_review.may_accept?

    errors.add(:advisory_review, :unacceptable, state: advisory_review.state, message: "The advisory_review being published was neither acceptable nor already accepted.")
  end

  def advisory_review_must_be_approved
    return if advisory_review.required_approvals?

    errors.add(:advisory_review, :not_approved, approvals: advisory_review.approvals.approved.count, message: "The advisory_review being published does not have the required approvals.")
  end

  def advisory_review_cwes_must_exist
    invalid_cwes = unknown_cwe_ids

    return if invalid_cwes.empty?

    errors.add(:advisory_review, :unknown_cwe_id, ids: invalid_cwes, message: "The advisory_review being published has invalid CWEs.")
  end

  def unknown_cwe_ids
    cwe_ids = advisory_review.cwe_ids
    cwe_ids - CWE.where(cwe_id: cwe_ids).pluck(:cwe_id)
  end

  def advisory_payload
    AdvisoryPayload.new(data: advisory_review.advisory_payload)
  end

  # The publisher manages its own transactionality and also encapsulates async communication.
  # This method is meant be used in any public method in the publisher that uses transactions to control data commits.
  def ensure_no_parent_transactions
    if (Rails.env.production? && ActiveRecord::Base.connection.open_transactions > 0) ||
       (Rails.env.test? && ActiveRecord::Base.connection.open_transactions > 2) # Tests always run inside a transaction.
      # If this happens, we run the risk of having the job request reach our workers before the data is committed in DB.
      raise Publisher::NestedTransactionError, "We should never call publish with an existing transaction wrapping the method call!"
    end
  end
end
