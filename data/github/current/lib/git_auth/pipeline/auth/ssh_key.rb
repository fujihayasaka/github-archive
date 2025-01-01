# typed: true
# frozen_string_literal: true

module GitAuth
  class Pipeline
    module Auth
      # Personal key or deploy key.
      class SSHKey < SSH
        def applicable?
          input.protocol == "ssh"
        end

        def process
          pubkey = GitAuth::SSHKey.with_fingerprint_sha256(fingerprint_sha256)
          result.public_key = pubkey

          return result.fail_with :unknown_public_key if pubkey.nil?
          return result.fail_with :unverified_key unless pubkey.verified?

          if input.member.start_with?("user:") && !valid_user_member?(pubkey.user)
            return result.fail_with :invalid_personal_ssh_key
          end

          if input.member.start_with?("repo:") && !valid_repo_member?(pubkey.repository)
            return result.fail_with :invalid_deploy_key
          end

          return result.fail_with :read_only_key if pubkey.read_only? && input.action == :write

          if GitHub.private_mode_enabled? && pubkey.repository
            return result.fail_with :invalid_deploy_key if input.repository.nil?
            return result.fail_with :invalid_deploy_key if input.repository.is_a?(Gist)
            return result.fail_with :invalid_deploy_key if input.repository.is_a?(Repository) && pubkey.repository.id != input.repository.id
          end

          resp = weak_sigtype_check(pubkey, input.member)
          return result.fail_with resp unless resp.nil?

          result.user = pubkey.user
          result.credential = "public-key:simple:#{fingerprint_sha256}"
          result.success!

        rescue SSHData::Error => e
          Failbot.report(e)
          result.fail_with :ssh_error
        end

        private

        def fingerprint_sha256
          SSHData::PublicKey.parse_openssh(input.key).fingerprint
        end

        def valid_user_member?(user)
          return false if user.nil?
          return true if input.member == "user:#{user.id}"

          input.member == "user:#{user.id}:#{user.display_login}"
        end

        def valid_repo_member?(repo)
          return false if repo.nil?
          return true if input.member == "repo:#{repo.id}"

          input.member == "repo:#{repo.id}:#{repo.name_with_display_owner}"
        end
      end
    end
  end
end
