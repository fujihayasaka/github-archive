# typed: true
# frozen_string_literal: true

module GitAuth
  class Pipeline
    module Auth
      class SSHCertificate < SSH
        def applicable?
          input.protocol == "ssh" && certificate?
        end

        def process
          status, _, user_login, _, ssh_ca = GitAuth::SSHCertificateAuthority.validate_certificate(
            input.key,
            ip: input.ip,
            max_lifetime_checks: true
          )

          result.ssh_ca = ssh_ca # Used in error messages.

          return result.fail_with status if status == :invalid_validity_period || status == :invalid_due_to_user_activity
          return result.fail_with :ssh_error if status != :ok
          return result.fail_with :ssh_error if ssh_ca.nil?

          resp = weak_sigtype_check(input.key, input.member)
          return result.fail_with resp unless resp.nil?

          # this is intentionally `user_login` and _not_ display login so that the
          # user can be looked up in result.rb using login as the lookup key
          result.member = user_login
          result.credential = "public-key:ssh-ca:#{fingerprint_sha256}"

          result.success!
        end

        private

        def certificate?
          algo, _, _ = SSHData.key_parts(input.key)
          SSHData::Certificate::ALGOS.include?(algo)
        rescue SSHData::Error => e
          Failbot.report(e)
          false
        end

        def fingerprint_sha256
          SSHData::Certificate.parse_openssh(input.key).public_key.fingerprint
        rescue SSHData::Error => e
          Failbot.report(e)
          nil
        end
      end
    end
  end
end
