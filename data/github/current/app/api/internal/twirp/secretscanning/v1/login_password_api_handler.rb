# typed: true
# frozen_string_literal: true

require "secret_scanning_proto"

class Api::Internal::Twirp
  module Secretscanning
    module V1
      class LoginPasswordAPIHandler < SecretScanningAPIHandler
        handles_service(GitHub::Proto::SecretScanning::Api::V1::LoginPasswordAPIService)

        allow_access_for :client
        connected_to_writing_for :revoke_login_password

        include SecretScanning::Encryption::LoginCredentialsCryptoHelper
        include GitHub::TokenScanning::TokenScanningPostProcessingHelper

        CANDIDATE_LIMIT = 1000
        VERIFY_BATCH_SIZE = 1000

        resolve_tenant_context only: %i[revoke_login_password] do |req, _env|
          ::Repositories::Public.resolve_tenant(id: req.repository_id)
        rescue ActiveRecord::RecordNotFound => err
          Twirp::Error.not_found(err.message)
        end

        exempt_from_tenant_context_requirement(only: %i[verify_login_password])

        # Public: Handles the revocation of a batch of users with compromised login/password credentials.
        sig { params(req: GitHub::Proto::SecretScanning::Api::V1::RevokeLoginPasswordRequest, env: T::Hash[String, T.untyped]).returns(T.any(GitHub::Proto::SecretScanning::Api::V1::RevokeLoginPasswordResponse, Twirp::Error)) }
        def revoke_login_password(req, env)
          candidates = req.candidates.to_a

          unless candidates.present?
            return Twirp::Error.invalid_argument("must be non-empty", argument: "candidates")
          end

          if candidates.size > CANDIDATE_LIMIT
            return Twirp::Error.invalid_argument("must have a length <= #{CANDIDATE_LIMIT}", argument: "candidates")
          end

          repo = with_read { get_repo_from_request(req.repository_type, req.repository_id) }

          tags = ["action:revoke_login_password"]
          GitHub.dogstats.increment("secretscanning_loginpassword.revoke.calls", tags: tags)

          verify_results = with_read { verify_candidates(candidates, tags: tags) }
          revoke_results = revoke_candidates(verify_results, repo, tags: tags)

          results = revoke_results[:candidates].map do |c|
            { revoke_result: c[:revoke_result] }
          end

          GitHub::Proto::SecretScanning::Api::V1::RevokeLoginPasswordResponse.new({ results: results, revoked_count: revoke_results[:revoked_count] })
        end

        # Public: Verifies if a batch of users are authenticated by the provided login/email and password.
        sig { params(req: GitHub::Proto::SecretScanning::Api::V1::VerifyLoginPasswordRequest, env: T::Hash[String, T.untyped]).returns(T.any(GitHub::Proto::SecretScanning::Api::V1::VerifyLoginPasswordResponse, Twirp::Error)) }
        def verify_login_password(req, env)
          candidates = req.candidates.to_a

          unless candidates.present?
            return Twirp::Error.invalid_argument("must be non-empty", argument: "candidates")
          end

          if candidates.size > CANDIDATE_LIMIT
            return Twirp::Error.invalid_argument("must have a length <= #{CANDIDATE_LIMIT}", argument: "candidates")
          end

          tags = ["action:verify_login_password"]
          GitHub.dogstats.increment("secretscanning_loginpassword.verify.calls", tags: tags)

          verify_results = verify_candidates(candidates, tags: tags)

          results = verify_results.map do |c|
            { is_verified: c[:is_verified] }
          end

          GitHub::Proto::SecretScanning::Api::V1::VerifyLoginPasswordResponse.new({ results: results })
        end

        private

        def revoke_candidates(candidates, repo, tags:)
          GitHub.dogstats.distribution_time("secretscanning_loginpassword.revoke.dist.duration", tags: tags) do
            revoked_count = 0
            false_positive_count = 0
            fail_count = 0

            revoke_results = candidates.map do |c|
              if c[:is_verified]
                revoke_result = :UNKNOWN_RESULT
                begin
                  user_already_marked_as_compromised = c[:user].password_check_metadata.exact_match?

                  if !user_already_marked_as_compromised
                    c[:user].mark_compromised_via_secret_scanning

                    # only send emails to users who have verified an email
                    if !c[:user].should_verify_email?
                      repo_readable = false
                      repo_readable = repo.readable_by?(c[:user]) if repo
                      SecretScanningMailer.username_and_password_compromised_detected_by_secret_scanning(user: c[:user], repo_readable_by_user: repo_readable, token_source: c[:candidate]&.credential_source, url: c[:candidate]&.url).deliver_later
                    end

                    revoke_result = :REVOKED
                    revoked_count += 1
                  else
                    revoke_result = :NO_OAUTH_ACCESS
                  end

                rescue ActiveRecord::ActiveRecordError => e
                  fail_count += 1
                  # cloning tags to avoid modifying the original
                  error_tags = tags.map(&:clone).push("error:#{e.message}")
                  GitHub.dogstats.increment("secretscanning_loginpassword.revoke.failure", tags: error_tags)
                end

                { candidate: c, user: c[:user], revoke_result: revoke_result }
              else
                false_positive_count += 1
                { candidate: c, user: c[:user], revoke_result: :FALSE_POSITIVE }
              end
            end

            GitHub.dogstats.count("secretscanning_loginpassword.revoked", revoked_count, tags: tags)
            GitHub.dogstats.count("secretscanning_loginpassword.false_positives", false_positive_count, tags: tags)
            GitHub.dogstats.count("secretscanning_loginpassword.failed", fail_count, tags: tags)

            { candidates: revoke_results, revoked_count: revoked_count }
          end
        end

        def verify_candidates(candidates, tags:)
          GitHub.dogstats.distribution_time("secretscanning_loginpassword.verify.dist.duration", tags: tags) do
            # pre-filter to only query valid logins and passwords
            logins = []
            emails = []
            verified_count = 0

            candidates.each do |candidate|
              next unless valid_candidate?(candidate)

              if candidate.user.include?("@")
                emails << candidate.user
              else
                logins << candidate.user
              end
            end

            valid_emails = User.select("users.*, user_emails.email as user_email").
              joins(:emails).
              where(user_emails: { email: emails })

            valid_logins = User.select("users.*, NULL as user_email").
              where(login: logins)

            valid_users = User.find_by_sql("SELECT * FROM (#{valid_emails.to_sql} UNION #{valid_logins.to_sql}) AS users")

            verify_results = candidates.map do |c|
              if !valid_candidate?(c)
                { candidate: c, user: nil, is_verified: false }
              else
                is_verified = false
                user = valid_users.find { |u| !u.bot? && (u.login&.downcase == c.user.downcase || u.user_email&.downcase == c.user.downcase) }
                if user.present?
                  begin
                    password = decrypt_password(c.password_encrypted)
                    is_verified = user.authenticated_by_password?(password)
                  rescue ArgumentError => e
                    # cloning tags to avoid modifying the original
                    error_tags = tags.map(&:clone).push("error:#{e.message}")
                    GitHub.dogstats.increment("secretscanning_loginpassword.decrypt.fail", tags: error_tags)
                  end
                end

                if is_verified
                  verified_count += 1
                end
                { candidate: c, user: user, is_verified: is_verified }
              end
            end

            query_count = logins.length + emails.length
            GitHub.dogstats.count("secretscanning_loginpassword.queried", query_count, tags: tags)
            GitHub.dogstats.count("secretscanning_loginpassword.found", valid_users.length, tags: tags)
            GitHub.dogstats.count("secretscanning_loginpassword.verified", verified_count, tags: tags)

            verify_results
          end
        end

        def valid_candidate?(candidate)
          !candidate.user.blank? && !candidate.password_encrypted.blank?
        end
      end
    end
  end
end
