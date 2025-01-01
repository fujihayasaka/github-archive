# typed: true
# frozen_string_literal: true

module Audit
  module AuthData

    def self.git_credential_type(credential, token = "")
      # These descriptions were derived from this doc:
      # https://github.com/github/ops/blob/b17da535a420a147b9280aa559d7e5fd1ebf829a/docs/playbooks/gitauth.md?plain=1#L94

      case
      when credential.blank? || credential == "none"
        # No valid authentication was provided and the user is anonymous.
        "No valid authentication was provided (anonymous)"
      when credential == "password"
        # The user provided a password.  This should not be seen on dotcom, and for security reasons no further information is provided.
        "User provided password"
      when credential == "port:svnbridge"
        # The svnbridge service is implicitly authenticated to babeld, and hence Gitauth, by virtue of an internal port.
        "Svnbridge service"
      when credential.start_with?("public-key:ssh-ca:")
        # An SSH certificate with the given fingerprint was used.
        "SSH certificate"
      when credential.start_with?("public-key:simple:")
        # `An SSH public key was used; this could be a user's key or deploy key.
        "Public Key (User/Deploy)"
      when credential.start_with?("token:gitauth-full-trust:")
        # A Gitauth full trust token for the given service and with the given hash was used.  They are typically scoped to a repository.
        "GitAuth full-trust service token"
      when credential.start_with?("token:temp-clone:")
        # These tokens are SignedAuthTokens issued on behalf of a user and scoped to a given repository.
        "Signed auth token (repo scoped)"
      else
        # if we fail then try the token
        GitHub::Authentication::Attempt.prog_access_type(token)
      end
    end
  end
end
