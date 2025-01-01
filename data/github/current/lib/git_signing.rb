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

  VerificationRequest = T.type_alias do
    T::any(
      {
        message: String,
        signature: String,
        email: String,
        id: String,
        network_id: Integer,
      },
      {
        message: String,
        signature: String,
        email: String,
        id: String,
        network_id: Integer,
        business: Integer,
      }
    )
  end

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
  # push_id - The id of the push where the commits were introduced to be saved in authentic_commits.
  # save_to_db - If true, verified statuses will be saved to the authentic_commits table. This should only be
  #              false if it's possible the commits may not ultimately be accepted by our servers after this
  #              check runs.
  #
  # Returns request Hashes, updated to include :valid and :reason keys, plus
  # other metadata.
  sig do
    params(
      requests: T::Array[VerificationRequest],
      push_id: T.nilable(Integer),
      save_to_db: T::Boolean,
    ).returns(T.untyped)
  end
  def verify_signatures(requests, push_id: nil, save_to_db: true)
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

    return requests if maybe_valid.empty?

    # Please note that requests without `network_id` in theory shouldn't reach this stage,
    # because requests without `repo` are marked as `nil_signing_data` in `prefill_signing_data`,
    # and filtered out above.

    # This will add `already_verified: true` and verification data to the requests that have verification
    # recorded in authentic_commits.
    process_authentic_commits(maybe_valid:)

    to_group = maybe_valid.filter_map do |req|
      [req[:business], req[:email].to_s.downcase] unless req[:email].nil?
    end

    # Create a hash of emails for each business
    emails = to_group.group_by { |b| b.shift }.transform_values { |v| v.flatten.uniq.compact }

    # no need to add business here since it will be part of the hash and resolved
    # in the User.find_by_emails
    users = User.find_by_emails_with_business(emails)

    # For commits that aren't already verified, weed out requests with missing/spammy users or unverified email.
    maybe_valid.select! do |req|
      email = req[:email].to_s.downcase
      user = users[email]

      if req[:already_verified]
        # Even for previously verified commits, we want the user here when possible
        # so we can retrieve and return the signing cert's fingerprint.
        req[:user] = user
      elsif user.nil? || user.spammy?
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

    requests.each do |req|
      req[:verified_at] = Time.now.utc if req[:valid] && req[:reason] == GitSigning::VALID && req[:verified_at].nil?
    end

    if GitHub.persistent_commit_signature_verification_enabled? && save_to_db
      # strip entries from maybe_valid that are already verified
      maybe_valid.select! { |req| req[:already_verified] != true }

      save_authentic_commits(maybe_valid:, push_id:) if maybe_valid.any?
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
    # We need the list of all the network IDs for the requested commits no matter what.
    network_ids = maybe_valid.map { |mv| mv[:network_id] }.uniq

    # For consistent behavior when this is enabled on a percentage of requests without actor, look it up just once, here.
    @check_network_families_on_second_pass = FeatureFlag.vexi.enabled?(:ac_current_network_lookup_first, default: false)
    @cte_repo_network_traversal_enabled = FeatureFlag.vexi.enabled?(:cte_repo_network_traversal, default: false)

    # When we're checking network families in the second pass AND the CTE lookup is enabled, we won't need this.
    # So we look it up only as needed in the FF-gated blocks below and declare it nil here so we know when it
    # still needs retrieving.
    networks = nil

    # If we're only doing one pass, add family IDs to the maybe_valid objects for use in that first pass.
    unless @check_network_families_on_second_pass
      if @cte_repo_network_traversal_enabled
        # cte family lookup for requested network_ids
        get_repo_network_family_ids(maybe_valid, network_ids)
      else
        # old batch loader family lookup for requested network_ids
        networks = Platform::Loaders::RepositoryNetworkById.load_many(network_ids).sync.index_by(&:id)
        maybe_valid.each do |mv|
          network_id = mv[:network_id]
          network = networks[network_id]
          mv[:family_network_ids] = if network
            network.family_ids
          else
            [network_id]
          end
        end
      end
    end

    # First pass. If FF is enabled, check networks only. If disabled, check networks and families.
    queried_network_ids = query_for_authentic_commits(maybe_valid:, use_network_families: !@check_network_families_on_second_pass)

    # If FF is enabled, make a second pass to check family networks for any commits that weren't found in their network.
    if @check_network_families_on_second_pass
      # add family IDs to the maybe_valid objects that didn't find a match on their network_id
      if @cte_repo_network_traversal_enabled
        # remove any network_ids for commits that were already verified
        network_ids = maybe_valid.reject { |mv| mv[:already_verified] }.map { |mv| mv[:network_id] }.uniq

        # cte family lookup for remaining network_ids
        get_repo_network_family_ids(maybe_valid, network_ids)
      else
        networks = Platform::Loaders::RepositoryNetworkById.load_many(network_ids).sync.index_by(&:id) if networks.nil?
        maybe_valid.each do |mv|
          next if mv[:already_verified]
          network_id = mv[:network_id]
          network = networks[network_id]

          # add family ids. the commit's network was already checked above, so remove that.
          mv[:family_network_ids] = network.family_ids - [network_id] if network
        end
      end

      # Second pass. Always checks network families. Provide the list of network IDs we've already checked so we can skip them.
      query_for_authentic_commits(maybe_valid:, use_network_families: true, previously_queried_network_ids: queried_network_ids)
    end
  end

  private def query_for_authentic_commits(maybe_valid:, use_network_families:, previously_queried_network_ids: [])
    already_verified = 0
    not_already_verified = 0

    network_id_query_prop = if use_network_families
      :family_network_ids
    else
      :network_id
    end

    # query the authentic_commits table for all matching rows. note that the generated query looks like
    # `WHERE network_id IN (3, 4) AND oid IN ("a", "b")`, so invalid matches may possibly be returned.
    # actual matches are verified below.
    query_network_ids = maybe_valid.flat_map { |x| x[network_id_query_prop] }.uniq

    # if we're on the second pass and the family lookup hasn't added any networks to check, there's nothing new to check
    if query_network_ids - previously_queried_network_ids == []
      # we're skipping all the checks because we can, but still count the "not already verified" commits for stats below
      not_already_verified += maybe_valid.count { |x| x[:already_verified] != true }
    else
      authentic_commits_hash = AuthenticCommit.where(
        network_id: query_network_ids,
        oid: maybe_valid.map { |x| x[:id] }.uniq
      ).to_h { |ac| ["#{ac.network_id}-#{ac.oid}", ac] }

      # only add verification data, as individual verification classes still need to be called to add metadata to the
      # requests (like GPG key ID and SSH key hex)
      maybe_valid.each do |req|
        # if we're on the second pass, skip requests that were already verified
        next if @check_network_families_on_second_pass && use_network_families && req[:already_verified]

        # get all possible valid hash keys
        valid_hash_keys = if use_network_families
          req[:family_network_ids].map { |fid| "#{fid}-#{req[:id]}" }
        else
          ["#{req[:network_id]}-#{req[:id]}"]
        end

        # check if anything in authentic_commits_hash matches
        if found_key = valid_hash_keys.find { |k| authentic_commits_hash.key?(k) }
          ac = T.must(authentic_commits_hash[found_key])
          if ac.verified_at.present?
            req[:reason] = GitSigning::VALID
            req[:valid] = true
            req[:verified_at] = ac.verified_at
            req[:already_verified] = true
            already_verified += 1
          else
            not_already_verified += 1
          end
        else
          not_already_verified += 1
        end
      end
    end

    # Checking already_verified > 0 doesn't affect instrumentation but enables useful invocation counting in tests.
    GitHub.dogstats.count("git_signing.process_authentic_commits.already_verified", already_verified) if already_verified > 0

    # Count how many requests were NOT already verified, but if we're checking network families on the second pass,
    # we have to wait until that second pass to count it as not already verified.
    unless @check_network_families_on_second_pass
      GitHub.dogstats.count("git_signing.process_authentic_commits.not_already_verified", not_already_verified) if not_already_verified > 0
    end

    # Only for requests where the feature flag is enabled, record count found in network vs. family.
    # This will give an accurate ratio regardless of the FF setting.
    if @check_network_families_on_second_pass
      GitHub.dogstats.count("git_signing.authentic_commits.found_in_network", already_verified, tags: ["found_in_family:#{use_network_families}"]) if already_verified > 0

      # On the second, network family pass, we can count these as NOT already verified.
      if use_network_families
        GitHub.dogstats.count("git_signing.process_authentic_commits.not_already_verified", not_already_verified) if not_already_verified > 0
      end
    end

    query_network_ids # return the network_ids we've already queried so we can skip them on second pass
  end

  private def get_repo_network_family_ids(maybe_valid, network_ids)
    family_network_map = begin
      RepositoryNetwork::NetworkFamilies.new(network_ids)
    rescue RepositoryNetwork::InvalidNetworkError
      # This happens if a network family is too large or has circular references.
      # In this case we only check the commit's network.
      GitHub.logger.error("Network family retrieval failed for network_ids: #{network_ids}")
      GitHub.dogstats.increment("git_signing.network_family_retrieval_failed", tags: ["network_ids:#{network_ids.join(",")}"])
      nil
    end

    maybe_valid.each do |mv|
      family_ids = if family_network_map
        begin
          family_network_map.family_ids(mv[:network_id])
        rescue RepositoryNetwork::InvalidNetworkError
          # This happens if a network family is too large or has circular references.
          # In this case we only check the commit's network.
          GitHub.logger.error("RepositoryNetwork::NetworkFamilies#family_ids failed for network id: #{mv[:network_id]}")
          GitHub.dogstats.increment("git_signing.family_ids_lookup_failed", tags: ["network_id:#{mv[:network_id]}"])
          [mv[:network_id]]
        end
      else
        [mv[:network_id]]
      end

      mv[:family_network_ids] = family_ids
    end
  end

  # Saves verified commits to the DB.
  def save_authentic_commits(maybe_valid:, push_id:)
    to_upsert = maybe_valid.filter_map { |r| { network_id: r[:network_id], oid: r[:id], push_id:, verified_at: r[:verified_at] } if r[:valid] && r[:reason] == GitSigning::VALID && r[:verified_at] }

    return unless to_upsert.any?

    errored = false
    start_time = GitHub::Dogstats.monotonic_time

    begin
      ActiveRecord::Base.connected_to(role: :writing) do
        AuthenticCommit.bulk_upsert(to_upsert)
      end
    rescue ActiveRecord::ActiveRecordError => e
      # gracefully fail and move on
      errored = true
      Failbot.report e
      GitHub.dogstats.increment("git_signing.save_authentic_commits.error")
    end

    elapsed = GitHub::Dogstats.duration(start_time)
    GitHub.dogstats.distribution("git_signing.save_authentic_commits.insert_duration", elapsed, tags: ["errored:#{errored}"])
    GitHub.dogstats.count("git_signing.save_authentic_commits.inserted_count", to_upsert.size) unless errored
  end

  extend self
end
