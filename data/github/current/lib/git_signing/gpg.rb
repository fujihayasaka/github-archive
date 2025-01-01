# typed: true
# frozen_string_literal: true

module GitSigning
  module GPG
    SIGNATURE_PREFIX = "-----BEGIN PGP SIGNATURE-----"
    SIGNATURE_SUFFIX = "-----END PGP SIGNATURE-----"

    # Fingerprint of a previous GitHub signing key used by GPG Verify to sign web based commits
    # The GPG Verify private key was rotated from this key as part of the security 6209 cred roll
    EXPIRED_GITHUB_SIGNING_KEY_FINGERPRINT = "4AEE18F83AFDEB23"

    # Is this a GPG signature?
    #
    # sig - A String that might be a GPG signature.
    #
    # Returns boolean.
    def signature?(sig)
      return false unless sig
      sig = sig.strip
      sig.start_with?(SIGNATURE_PREFIX) && sig.include?(SIGNATURE_SUFFIX)
    end

    # Verify a set of messages/signatures.
    #
    # requests - An Array of request Hashes.
    #            :message   - The String message.
    #            :signature - The String signature.
    #            :email     - The email of the User that allegedly signed the
    #                         message.
    #            :user      - The User associated with the email address.
    #            :id        - A unique String to identify this Hash.
    #
    # Returns request Hashes, updated to include :valid and :reason keys, plus
    # other metadata.
    def verify_signatures(requests)
      return requests if requests.empty?
      maybe_valid = requests.dup

      verified_commits_extra_logging = GitHub.flipper[:verified_commits_logging].enabled?

      # Load key-ids
      signatures = maybe_valid.map { |r| r[:signature] }

      key_ids = begin
        GitHub.gpg.signature_issuer_key_ids(signatures)
      rescue GpgVerify::Error => e
        handle_gpgverify_error(maybe_valid, e)
        return requests
      end

      signature_to_key_id = signatures.zip(key_ids).to_h

      # Weed out requests whose signatures can't be parsed. Also remove requests already marked as valid; just need
      # their key IDs added to the request.
      maybe_valid.select! do |req|
        if key_id = signature_to_key_id[req[:signature]]
          req[:key_id] = key_id

          if verified_commits_extra_logging
            GitHub.logger.info("verified_commits: already verified", {
              "gh.commit.oid": req[:id],
              "gh.commit.committed_date": req[:commit_date],
              "gh.owner.login": req[:owner],
              "gh.repo.id": req[:repository_id],
              "gh.repo.name_with_owner": req[:repository_nwo]
            })
          end

          next false if req[:already_verified]
          true
        else
          req[:reason] = GitSigning::MALFORMED_SIG
          req[:valid] = false
        end
      end

      # might be empty after previous block, return if so
      return requests if maybe_valid.empty?

      # Load keys and associated emails.
      user_ids = maybe_valid.map { |r| r[:user].id }
      key_ids = maybe_valid.map { |r| r[:key_id] }
      keys = GpgKey.with_emails.where(
        user_id: user_ids,
        key_id: key_ids,
      )

      # Because multiple users can have the same key, we index by user_id *and*
      # key_id. This ensures that we grab the correct key for the given request.
      key_by_uid_kid = keys.index_by do |key|
        [key.user_id, key.key_id]
      end

      # Weed out requests with missing key or mismatch between user/key emails.
      maybe_valid.select! do |req|
        req[:key] = key_by_uid_kid[[req[:user].id, req[:key_id]]]

        if req[:key].nil?
          req[:reason] = GitSigning::UNKNOWN_KEY
          req[:valid] = false
        elsif !req[:key].allowed_email?(req[:email], business: req[:business])
          req[:reason] = GitSigning::BAD_EMAIL
          req[:valid] = false
        elsif !req[:key].can_sign?
          req[:reason] = GitSigning::NOT_SIGNING_KEY
          req[:valid] = false
        else
          true
        end
      end

      # For commits signed by an old or expired GitHub web commit signing key,
      # ensure the commit exists in the VerifiedCommit table. If it is not present in the
      # table then we cannot trust the commit.
      if !GitHub.multi_tenant_enterprise? && !GitHub.enterprise? && GitHub.flipper[:gpg_verify_old_github_signed_commits_read].enabled?
        GitHub.dogstats.distribution_time("gpg.verified_commits_check") do
          # In all prod calls, `req[:id]` is the commit SHA
          github_signed_oids = maybe_valid.filter_map do |req|
            req[:id] if req[:key].hex_key_id == EXPIRED_GITHUB_SIGNING_KEY_FINGERPRINT
          end
          valid_oids = VerifiedCommit.where(oid: github_signed_oids).pluck(:oid)
          maybe_valid.select! do |req|
            if !github_signed_oids.include?(req[:id]) # Not signed by the expired GitHub key
              true
            elsif valid_oids.include?(req[:id]) # Signed by the expired GitHub key and is in the VerifiedCommit table
              GitHub.dogstats.increment("gpg.verified_commits_check_result", tags: ["result:in_table"])
              if verified_commits_extra_logging
                GitHub.logger.info("verified_commits: result in table", {
                  "gh.commit.oid": req[:id],
                  "gh.commit.committed_date": req[:commit_date],
                  "gh.owner.login": req[:owner],
                  "gh.repo.id": req[:repository_id],
                  "gh.repo.name_with_owner": req[:repository_nwo]
                })
              end
              true
            else # Signed by the expired GitHub key and is NOT in the VerifiedCommit table
              GitHub.logger.info("GPG verification failed with questionable commit date", {
                "gh.commit.oid": req[:id],
                "gh.commit.committed_date": req[:commit_date],
                "gh.owner.login": req[:owner],
                "gh.repo.id": req[:repository_id],
                "gh.repo.name_with_owner": req[:repository_nwo]
              })

              GitHub.dogstats.increment("gpg.verified_commits_check_result", tags: ["result:not_in_table"])

              if GitHub.flipper[:gpg_verify_old_github_signed_commits_enforce].enabled?
                # For the commits that are signed by the expired GitHub key and are NOT in the VerifiedCommit table
                # We set `valid` to `false` explicitly, and don't delegate verification to the GpgVerify service at all
                req[:reason] = GitSigning::EXPIRED_KEY
                req[:valid] = false
              else
                true
              end
            end
          end
        end
      end

      # Do actual verification of remaining requests.
      gpg_requests = maybe_valid.map do |req|
        {
          signature: req[:signature],
          message: req[:message],
          key_id: req[:key_id],
          public_key: req[:key].public_key,
          id: req[:id],
        }
      end

      gpg_results = begin
        GitHub.gpg.batch_verify(gpg_requests)
      rescue GpgVerify::Error => e
        handle_gpgverify_error(maybe_valid, e)
        return requests
      end

      maybe_valid.select! do |req|
        if gpg_results[req[:id]] == GpgVerify::VALID
          if req[:key].expired? || req[:key].revoked?
            GitHub.dogstats.increment("gpg.commits_verified",
              tags: ["verified:true", "key_expired:#{req[:key].expired?}", "key_revoked:#{req[:key].revoked?}"]
            )
          end
          req[:reason] = GitSigning::VALID
          req[:valid] = true
        else
          req[:reason] = GitSigning::INVALID
          req[:valid] = false
        end
      end

      requests
    end

    # Mark a set of requests invalid with the appropriate reason based on the
    # type of gpgverify error.
    #
    # maybe_valid - An Array of request Hashes.
    # e           - A GpgVerify::Error or subclass instnace.
    #
    # Returns nothing.
    def handle_gpgverify_error(maybe_valid, e)
      reason = if e.is_a?(GpgVerify::Unavailable)
        GitSigning::GPGVERIFY_UNAVAILABLE
      else
        # Previously we sent the array of requests to failbot. We have no record of needing it
        # for investigations, so removing the sensitive data. We can add it back if we find that
        # it would be valuable in the future.
        Failbot.report(e, app: GitSigning::FAILBOT_APP)

        GitSigning::GPGVERIFY_ERROR
      end

      maybe_valid.select! do |req|
        req[:reason] = reason
        req[:valid] = false
      end
    end

    extend self
  end
end
