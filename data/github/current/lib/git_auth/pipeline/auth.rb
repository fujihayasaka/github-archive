# typed: true
# frozen_string_literal: true

module GitAuth
  class Pipeline
    module Auth
      autoload :Anonymous, "git_auth/pipeline/auth/anonymous"
      autoload :RequestCredentials, "git_auth/pipeline/auth/request_credentials"
      autoload :SignedToken, "git_auth/pipeline/auth/signed_token"
      autoload :Slumlord, "git_auth/pipeline/auth/slumlord"
      autoload :SSH, "git_auth/pipeline/auth/ssh"
      autoload :SSHCertificate, "git_auth/pipeline/auth/ssh_certificate"
      autoload :SSHKey, "git_auth/pipeline/auth/ssh_key"
      autoload :TempCloneToken, "git_auth/pipeline/auth/temp_clone_token"
    end
  end
end
