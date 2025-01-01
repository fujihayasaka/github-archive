# typed: true
# frozen_string_literal: true

module GitSigning
  autoload :GPG, "git_signing/gpg"
  autoload :SMIME, "git_signing/smime"
  autoload :SSH, "git_signing/ssh"
  autoload :Verifiable, "git_signing/verifiable"
  autoload :NPlusOne, "git_signing/n_plus_one"

  class Error < StandardError; end
  class InvalidSignatureError < Error; end
  class OCSPError < Error; end

  # Where to report errors.
  FAILBOT_APP = "git_signing"

  # Which background job queue to use for any jobs.
  QUEUE = "git_signing"

  # Reasons that signature verification may fail.
  VALID                 = "valid"
  INVALID               = "invalid"
  MALFORMED_SIG         = "malformed_signature"
  UNKNOWN_KEY           = "unknown_key"
  BAD_EMAIL             = "bad_email"
  UNVERIFIED_EMAIL      = "unverified_email"
  NO_USER               = "no_user"
  UNKNOWN_SIG_TYPE      = "unknown_signature_type"
  UNSIGNED              = "unsigned"
  GPGVERIFY_UNAVAILABLE = "gpgverify_unavailable"
  GPGVERIFY_ERROR       = "gpgverify_error"
  NOT_SIGNING_KEY       = "not_signing_key"
  EXPIRED_KEY           = "expired_key"
  OCSP_PENDING          = "ocsp_pending"
  OCSP_ERROR            = "ocsp_error"
  OCSP_REVOKED          = "ocsp_revoked"
  BAD_CERT              = "bad_cert"

  REASONS = [
    VALID, INVALID, MALFORMED_SIG, UNKNOWN_KEY, BAD_EMAIL, UNVERIFIED_EMAIL,
    NO_USER, UNKNOWN_SIG_TYPE, UNSIGNED, GPGVERIFY_UNAVAILABLE, GPGVERIFY_ERROR,
    NOT_SIGNING_KEY, EXPIRED_KEY, OCSP_PENDING, OCSP_ERROR, OCSP_REVOKED
  ]

  # Verify a set of messages/signatures.
  #
  # requests - An Array of request Hashes.
  #            :message   - The String message.
  #            :signature - The String signature.
  #            :email     - The email of the User that allegedly signed the
  #                         message.
  #            :id        - A unique String to identify this Hash.
  #            :network_id - The Number network_id to be used to fetch authentic commits.
  #
  # ff_repo  - A Repository to check for feature flag status
  # save_to_db - If true, verified statuses will be saved to the AuthenticCommit table. This should only be
  #              false if it's possible the commits may not ultimately be accepted by our servers after this
  #              check runs.
  #
  # Returns request Hashes, updated to include :valid and :reason keys, plus
  # other metadata.
  def verify_signatures(requests, ff_repo = nil, save_to_db: true)
    # Raise if a web/api request results in multiple, identical calls.
    NPlusOne.check! if Rails.env.test?

    return requests if requests.empty?
    maybe_valid = requests.dup

    # Weed out requests without a signature.
    maybe_valid.select! do |req|
      if req[:signature].nil?
        req[:reason] = UNSIGNED
        req[:valid] = false
      elsif klass = [SMIME, GPG, SSH].find { |k| k.signature?(req[:signature]) }
        req[:class] = klass
      else
        req[:reason] = UNKNOWN_SIG_TYPE
        req[:valid] = false
      end
    end

    to_group = maybe_valid.filter_map do |req|
      [req[:business], req[:email].to_s.downcase] unless req[:email].nil?
    end

    # Create a hash of emails for each business
    emails = to_group.group_by { |b| b.shift }.transform_values { |v| v.flatten.uniq.compact }

    # no need to add business here since it will be part of the hash and resolved
    # in the User.find_by_emails
    users = User.find_by_emails_with_business(emails)

    # Weed out requests with missing user or unverified email.
    maybe_valid.select! do |req|
      email = req[:email].to_s.downcase
      user = users[email]

      if user.nil? || user.spammy?
        req[:reason] = NO_USER
        req[:valid] = false
      else
        req[:user] = user

        if user.is_a?(Bot) || user.user_email_state == "verified"
          true
        elsif !GitHub.email_verification_enabled?
          true # Email verification isn't require on Enterprise or Cloud.
        else
          req[:reason] = UNVERIFIED_EMAIL
          req[:valid] = false
        end
      end
    end

    # The ff_repo argument is only used to check FFs.
    # Once both this FF and :save_lazy_authentic_commits below are removed, the argument should be removed
    if ff_repo&.feature_enabled?(:process_authentic_commits)
      # Please note that requests without `network_id` in theory shouldn't reach this stage,
      # because requests without `repo` are marked as `nil_signing_data` in `prefill_signing_data`,
      # and filtered out above.
      process_authentic_commits(maybe_valid:)
    end

    # Group requests by class and do actual verification.
    maybe_valid.group_by do |req|
      req[:class]
    end.each do |klass, reqs|
      klass.verify_signatures(reqs)
    end

    requests.group_by do |req|
      req[:reason]
    end.each do |reason, reqs|
      GitHub.dogstats.count("git_signing.verification", reqs.size, tags: ["reason:#{reason}"])
    end

    # The ff_repo argument is only used to check FFs.
    # Once both this FF and :process_authentic_commits above are removed, the argument should be removed
    if save_to_db && ff_repo&.feature_enabled?(:save_lazy_authentic_commits)
      # entries already in the DB are removed from maybe_valid inside process_authentic_commits above,
      # so using maybe_valid instead of requests here avoids re-inserting things already known to be in the DB
      save_authentic_commits(maybe_valid:)
    end

    requests
  end

  private

  # Processes authentic commits.
  # I.e. fetches authentic_commits rows from the database,
  # and for every commit that is in the database sets the request to be valid,
  # therefore our code won't send these valid requests for further backend verification.
  #
  # maybe_valid - An Array of request Hashes to be sent to the backend verification later.
  #
  # That's it, the method mutates `maybe_valid` object, and corresponding `req` items in it.
  # Returns nothing.
  def process_authentic_commits(maybe_valid:)
    network_ids = maybe_valid.map { |mv| mv[:network_id] }.uniq
    networks = Platform::Loaders::RepositoryNetworkById.load_many(network_ids).sync.index_by(&:id)

    # add family IDs to the maybe_valid objects
    maybe_valid.each do |mv|
      network_id = mv[:network_id]
      network = networks[network_id]
      mv[:family_network_ids] = if network
        network.family_ids
      else
        [network_id]
      end
    end

    # query the authentic_commits table for all matching rows. note that the generated query looks like
    # `WHERE network_id IN (3, 4) AND oid IN ("a", "b")`, so invalid matches may possibly be returned.
    # actual matches are verified below.
    authentic_commits_hash = AuthenticCommit.where(
      network_id: maybe_valid.flat_map { |x| x[:family_network_ids] },
      oid: maybe_valid.map { |x| x[:id] }
    ).to_h { |ac| ["#{ac.network_id}-#{ac.oid}", nil] }

    count_before = maybe_valid.count
    maybe_valid.select! do |req|
      # get all possible valid hash keys
      valid_hash_keys = req[:family_network_ids].map { |fid| "#{fid}-#{req[:id]}" }

      # check if anything in authentic_commits_hash matches
      if valid_hash_keys.any? { |k| authentic_commits_hash.key?(k) }
        req[:reason] = GitSigning::VALID
        req[:valid] = true
        false # don't keep this record for further verification
      else
        true # keep this record for further verification via corresponding backend
      end
    end

    count_after = maybe_valid.count
    GitHub.dogstats.count("git_signing.process_authentic_commits.already_verified", count_before - count_after)
    nil
  end

  # Saves verified commits to the DB.
  def save_authentic_commits(maybe_valid:)
    verified_at = Time.now.utc
    to_insert = maybe_valid.filter_map { |r| { network_id: r[:network_id], oid: r[:id], verified_at: } if r[:valid] }

    return unless to_insert.any?

    errored = false
    start_time = GitHub::Dogstats.monotonic_time

    begin
      ActiveRecord::Base.connected_to(role: :writing) do
        AuthenticCommit.bulk_insert(to_insert)
      end
    rescue ActiveRecord::ActiveRecordError => e
      # gracefully fail and move on
      errored = true
      Failbot.report e
      GitHub.dogstats.increment("git_signing.save_authentic_commits.error")
    end

    elapsed = GitHub::Dogstats.duration(start_time)
    GitHub.dogstats.distribution("git_signing.save_authentic_commits.insert_duration", elapsed, tags: ["errored:#{errored}"])
    GitHub.dogstats.count("git_signing.save_authentic_commits.inserted_count", to_insert.size) unless errored
  end

  extend self
end
