# typed: true
# frozen_string_literal: true

module GitAuth
  class Pipeline
    module Auth
      class SSH < AuthenticationMethod
        protected

        def weak_sigtype_check(key, member)
          member_obj = object_for_member(member)

          # DSA keys are weak.
          return :weak_sigtype_dsa if input.base_sigtype == "ssh-dss"

          # All remaining types other than ssh-rsa use SHA-2 and are secure.
          return nil unless input.base_sigtype == "ssh-rsa"

          # This is an RSA key using a SHA-1 signature.  SHA-2 signatures would have
          # had a sigtype of "rsa-sha2-256" or "rsa-sha2-512" and exited early
          # above.

          # Find the cut-off point, beyond which newly uploaded keys cannot use
          # SHA-1 signatures.  Employees have an earlier cut-off point so we can
          # staff-ship this.
          employee, pub = GitHub.git_weak_ssh_rsa_deadline
          user = member_obj.is_a?(User) ? member_obj : nil
          deadline = user&.employee? ? employee : pub

          # We haven't configured a deadline for this.  Let it through.
          return nil if deadline.nil?
          creation_time = if key.is_a?(GitAuth::SSHKey)
            key.created_at
          else
            SSHData::Certificate.parse_openssh(key).valid_after
          end

          # If this key was first uploaded after or valid after the deadline,
          # reject it; otherwise allow it.
          return :weak_sigtype_rsa if !creation_time.nil? && creation_time > deadline
          nil
        end

        def object_for_member(member)
          return User.find_by(id: member.split(":")[1].to_i) if member.start_with?("user:")
          if member.start_with?("repo:")
            if FeatureFlag.vexi.enabled?(:repos_by_id_lib, default: false)
              return Repositories.domain.by_id(member.split(":")[1].to_i)
            else
              return Repository.find_by(id: member.split(":")[1].to_i)
            end
          end
          nil
        end
      end
    end
  end
end
