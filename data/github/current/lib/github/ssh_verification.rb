# typed: true
# frozen_string_literal: true

require "openssl"
require "base64"

module GitHub
  module SshVerification
    extend ActionView::Helpers::DateHelper

    SSH_VERIFICATION_TOKEN_SCOPE = "SSHVerificationToken"

    # Generates a verification token.
    #
    # member - The user login to make the token for. Uses repo_permissions format of
    #          "user:<id>" or "repo:<id>" (for deploy keys).
    #
    # fingerprint - The fingerprint of the SSH used to obtain the token.
    #
    # Returns a verification token (base64 encoded string).
    def self.generate_token(member, fingerprint_sha256)
      user = if member.starts_with?("user:")
        User.find_by(id: member.split(":")[1].to_i)
      elsif member.starts_with?("repo:")
        # XXX - we don't verify deploy keys right now
        nil
      else
        raise "bogus member param for ssh verification: #{member.inspect}"
      end
      return unless user

      fingerprint = fingerprint_sha256
      if GitHub.multi_tenant_enterprise? && (current_tenant = GitHub::CurrentTenant.get)
        fingerprint = fingerprint << "_#{current_tenant.shortcode}"
      end
      public_key = user.public_keys.find_by(fingerprint_sha256: fingerprint)
      return unless public_key

      user.signed_auth_token(
        scope: SSH_VERIFICATION_TOKEN_SCOPE,
        expires: 1.week.from_now,
        data: {
          created_at: Time.now.to_i,
          public_key: public_key.id,
        },
      )
    end

    # Validates the provided token.
    #
    # unverified_token - The whitespace insensitive token to be validated.
    # user - The User we are validating the token for.
    #
    # Returns the validation result (bool), and message(s) (string array).
    def self.validate(unverified_token, user)
      token = GitHub::Authentication::SignedAuthToken.verify_for_stafftools(
        token: unverified_token.gsub(/[[:space:]]+/, ""),
        scope: SSH_VERIFICATION_TOKEN_SCOPE,
      )

      unless token.valid?
        if token.expired?
          return false, ["That token was created over 1 week ago and has expired. Ask the user to try again."]
        elsif token.bad_login?
          return false, ["That token was created for an invalid user. Ask the user to try again."]
        else
          return false, ["That token is malformed or has been tampered with. Ask the user to try again."]
        end
      end

      if token.data["public_key"].blank? || token.data["created_at"].blank?
        return false, ["That token is missing data. Don't use that token for verification!"]
      end

      unless token.user == user
        return false, ["That token was created by '#{token.user}', not '#{user}'. Don't use that token for verification!"]
      end

      unless public_key = user.public_keys.find_by_id(token.data["public_key"])
        return false, ["That token was created by '#{token.user}' using a SSH key that is no longer authorized for their account. Don't use that token for verification!"]
      end

      # Keys that are unverified can only be used for verification if the reason
      # they were unverified is due to lack of use ("stale").
      unless public_key.verified? || public_key.unverification_reason == "stale"
        return false, ["That token was created by '#{token.user}' using an unverified SSH key. Don't use that token for verification!"]
      end

      authorization = public_key.oauth_authorization
      unless permitted_to_create_keys_for_verification?(authorization)
        return false, ["That token was created for an SSH key created by an OAuth application. Don't use that token for verification!"]
      end

      # Mention if it was created by Desktop
      created_at = Time.at token.data["created_at"]
      messages = if authorization && Apps::Privileged.capable?(:create_tokens_for_ssh_key_verification, app: authorization.application)
        ["That token is valid for user '#{token.user}'. It was created #{time_ago_in_words created_at} ago by GitHub Desktop using a SSH key with the fingerprint '#{public_key.fingerprint}'."]
      else
        ["That token is valid for user '#{token.user}'. It was created #{time_ago_in_words created_at} ago using a SSH key with the fingerprint '#{public_key.fingerprint}'."]
      end

      # Add a note to the message if the user is in a suspended state
      # It can technically still be used for verification
      if token.user.suspended?
        messages.push "Note: The token belongs to a suspended user."
      end

      [true, messages]
    end

    # Internal: Based on the current authorization, are we permitted to create
    # a key for verification purposes?
    # Only keys created by capable apps can be used for verification.
    #
    # authorization - OauthAuthorization: The authorization record associated
    # with this public key.
    #
    # Returns a Boolean.
    def self.permitted_to_create_keys_for_verification?(authorization)
      return true if authorization.nil? # Permitted when not associated with an OAuth app.
      Apps::Privileged.capable?(:create_tokens_for_ssh_key_verification, app: authorization.application)
    end
  end
end
