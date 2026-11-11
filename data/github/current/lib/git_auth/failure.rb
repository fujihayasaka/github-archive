# typed: true
# frozen_string_literal: true

module GitAuth
  class Failure
    extend Forwardable
    include ::ConditionalAccess::Helpers::PersonalAccessTokensExpirationLimit

    attr_reader :authentication, :authorization, :status, :country

    def_delegators :authentication, :member, :public_key, :ssh_ca, :user

    def_delegators :authorization, :maintainer?, :target

    def initialize(status:, authentication:, authorization:, ssh_enabled:, country:)
      @status         = status
      @authentication = authentication
      @authorization  = authorization
      @ssh_enabled    = ssh_enabled
      @country        = country
    end

    def message
      case status
      when :maintenance
        if GitHub.enterprise?
          "GitHub Enterprise is offline for maintenance."
        else
          "GitHub is offline for maintenance. See https://githubstatus.com for more info."
        end
      when :invalid, :missing, :unauthorized_access_to_private_repository, :no_access_to_spammy_repository, :unauthorized_access_to_secret_gist, :invalid_protocol_for_secret_gist, :gotauth_redirect
        "Repository not found."
      when :unauthorized_write_access_to_private_repository
        "Write access to repository not granted."
      when :unknown_public_key
        "Unknown public SSH key."
      when :unverified_key
        prefix = public_key.repository ? "/#{public_key.repository.name_with_display_owner}" : ""
        url = "#{GitHub.url}#{prefix}/settings/keys/#{public_key.id}"
        reason = PublicKey.unverification_explanation(public_key.unverification_reason)

        message = <<~MSG
        We're doing an SSH key audit.
        Reason: %{reason}
        Please visit %{url} to approve this key so we know it's safe.

        Fingerprint:
        %{fingerprint}
        MSG
        message % { reason: reason, url: url, fingerprint: public_key.fingerprint }
      when :read_only_key
        "The key you are authenticating with has been marked as read only."
      when :verified_email_required
        message = <<~MSG
        You must verify your email address.
        See %{url}.
        MSG
        message % { url: "#{GitHub.url}/settings/emails" }
      when :weak_password
        message = <<~MSG
        Weak credentials. Please Update your password to continue using GitHub.
        See %{url}.
        MSG
        message % { url: "#{GitHub.help_url}/articles/creating-a-strong-password/" }
      when :weak_sigtype_dsa
        message = <<~MSG
        You're using a DSA key, which is no longer allowed.
        Please generate and upload a new SSH key.
        Please see %{url} for more information.
        MSG
        message % { url: "#{GitHub.blog_url}/2021-09-01-improving-git-protocol-security-github/" }
      when :weak_sigtype_rsa
        message = <<~MSG
        You're using an RSA key with SHA-1, which is no longer allowed.
        Please use a newer client or a different key type.
        Please see %{url} for more information.
        MSG
        message % { url: "#{GitHub.blog_url}/2021-09-01-improving-git-protocol-security-github/" }
      when :no_git_protocol
        message = <<~MSG
        The unauthenticated git protocol on port 9418 is no longer supported.
        Please see %{url} for more information.
        MSG
        message % { url: "#{GitHub.blog_url}/2021-09-01-improving-git-protocol-security-github/" }
      when :external_auth_token_required
        or_ssh_key = ""
        or_ssh_url = ""
        message = <<~MSG
          Password authentication is not available for Git operations.
          You must use a personal access token%{or_ssh_key}.
          See #{GitHub.url}/settings/tokens%{or_ssh_url}
          MSG
        if ssh_enabled?
          or_ssh_key = " or SSH key"
          or_ssh_url = " or #{GitHub.url}/settings/ssh"
        end
        message % { or_ssh_key: or_ssh_key, or_ssh_url: or_ssh_url }
      when :no_writes_with_clone_token
        "Temporary clone tokens are read-only."
      when :temp_clone_token_expired
        "The token in this link has expired. Please request another temporary clone link."
      when :auth_error
        if GitHub.git_password_auth_supported?
          "Invalid username or password."
        else
          "Invalid username or token. Password authentication is not supported for Git operations."
        end
      when :ldap_timeout
        message = <<~MSG
        The external authentication server failed to respond within %{timeout} seconds.
        Please try again or contact your GitHub Enterprise administrator if the problem persists.
        MSG
        message % { timeout: GitHub.ldap_auth_timeout }
      when :invalid_full_trust_token, :invalid_full_trust_protocol
        "Invalid signed token."
      when :invalid_personal_ssh_key
        "Permission to %{path} denied to key" % { path: target.path }
      when :invalid_deploy_key
        "Permission to %{path} denied to deploy key" % { path: target.path }
      when :anonymous_access_denied
        "Anonymous access denied"
      when :no_anonymous_writes
        "No anonymous write access."
      when :unauthorized_write_to_gist
        "Permission to write to gist denied."
      when :access_denied_to_user
        "Permission to %{path} denied to %{login}." % { path: target.path, login: user.display_login }
      when :two_factor_noncompliant
        "You must set up two-factor authentication (2FA) on your account, with only the methods allowed by this repository's owner."
      when :external_conditional_access_policy_failed
        "Access has been blocked by Conditional Access Policies defined in your identity provider"
      when :legacy_personal_access_tokens_forbidden
        "Personal access tokens (classic) are forbidden from accessing this repository."
      when :personal_access_tokens_forbidden
        "Fine-grained personal access tokens are forbidden from accessing this repository."
      when :personal_access_tokens_expiration_limit_exceeded
        if authorization.maintainer?
          owner = repository.parent.owner
        else
          owner = repository.owner
        end
        enforcer = ProgrammaticAccessTokenLifetimeConfiguration.limit_enforcer_for(owner)

        if enforcer
          expiration_limit_exceeded_error_message(enforcer, user)
        else
          "Something went wrong. Please contact GitHub support."
        end
      when :oap_denied_app
        if user
          "Permission to %{path} denied to %{login}." % { path: target.path, login: user.display_login }
        else
          "Permission to %{path} denied to deploy key." % { path: target.path }
        end
      when :suspended_integration
        "This integration was suspended. #{GitHub.contact_support_url} for more information."
      when :suspended
        if GitHub.enterprise?
          if GitHub.reactivate_suspended_user?
            "Your account is suspended. Please login to reactivate your account."
          else
            "Your account is suspended. Please check with your installation administrator."
          end
        elsif user&.is_enterprise_managed?
          "Your account is suspended. Please contact an owner of the Enterprise Account."
        else
          "Your account is suspended. %{url} for more information." % { url: GitHub.support_link_text }
        end
      when :dmca
        message = <<~MSG
        Repository unavailable due to DMCA takedown.
        See the takedown notice for more details:
          %{url}.
        MSG
        message % { url: repository.access.dmca_url }
      when :country_block
        message = <<~MSG
        Repository has been blocked in your country.
        See the notice for more details:
          %{url}.
        MSG
        message % { url: repository.access.country_block_url(country) }
      when :sensitive_data_violation, :tos_violation, :trademark_violation
        message = <<~MSG
        Access to this repository has been disabled by GitHub staff.
        If you are the repository owner, you can contact support via %{support_url}/contact for more information.
        MSG
        message % { support_url: GitHub.support_url }
      when :broken
        message = <<~MSG
        There is a problem with this repository on disk.
        Please contact support via %{support_url}/contact for more information.
        MSG
        message % { support_url: GitHub.support_url }
      when :abusive
        if GitHub.enterprise?
          <<~MSG
          Access to this repository has been disabled by your site administrator.
          Please contact them to restore access to this repository.
          MSG
        else
          message = <<~MSG
          Access to this repository has been disabled by GitHub staff due to excessive resource use.
          Please contact support via %{support_url}/contact to restore access to this repository.
          Read about how to decrease the size of your repository:
            %{url}
          MSG
          message % {
            url: "#{GitHub.help_url}/articles/what-is-my-disk-quota",
            support_url: GitHub.support_url,
          }
        end
      when :credential_authorization_missing
        if authentication.token
          if authorization.maintainer?
            org = repository.parent.organization
            owner = repository.parent.owner
          else
            org = repository.organization
            owner = repository.owner
          end
          target = org.external_identity_session_owner
          credential = user.try(:oauth_access)

          if credential.nil?
            fail "Credential not found"
          end

          if credential.personal_access_token?
            request = Organization::CredentialAuthorization.generate_request \
              organization: org, target: target, credential: credential, actor: user
            resource = target.is_a?(::Organization) ? "orgs" : "enterprises"
            url = "#{GitHub.url}/#{resource}/#{target}/sso?authorization_request=#{request}"

            message = <<~MSG
            The '%{owner}' organization has enabled or enforced SAML SSO.
            To access this repository, visit %{url} and try your request again.
            MSG
            message % { url: url, owner: owner&.display_login || "owner" }
          else
            # In the event the user is using an OAuth token
            # or a GitHub App user-to-server token, the user
            # needs to go through the authorization web flow
            # again.
            message = <<~MSG
            The '%{owner}' organization has enabled or enforced SAML SSO.
            To access this repository, you must re-authorize the %{application_type} '%{application_name}'.
            MSG

            application_type = credential.oauth_application_type? ? "OAuth Application" : "GitHub App"
            application_name = credential.application.name

            message % { application_type: application_type, application_name: application_name, owner: owner&.display_login || "owner" }
          end
        else
          if authorization.maintainer?
            owner = repository.parent.owner
          else
            owner = repository.owner
          end

          message = <<~MSG
          The '%{owner}' organization has enabled or enforced SAML SSO.
          To access this repository, you must use the HTTPS remote with a personal access token or SSH with an SSH key and passphrase that has been authorized for this organization.
          Visit %{url} for more information.
          MSG
          message % { owner: owner&.display_login || "owner", url: GitHub.sso_credential_authorization_help_url }
        end
      when :oap_denied_key_unknown_origin
        login = repository.policymaker.display_login
        approve_url = "#{GitHub.url}/settings/ssh/audit/#{public_key.id}/policy"
        if member.start_with?("repo:")
          upload_url = "http://git.io/KM0rtw"
        else
          upload_url = "#{GitHub.url}/settings/keys"
        end

        message = <<~MSG
        Sorry, but @%{login} has blocked access to SSH keys created by some third-party applications.
        Your key was created before GitHub tracked keys created by applications, so we need your help.

        If you personally created this key, you can approve it at:

          %{approve_url}

        Otherwise, please upload a new key:

          %{upload_url}

        Fingerprint:
        %{fingerprint}

        [EPOLICYKEYAGE]
        MSG
        message % { login: login, approve_url: approve_url, upload_url: upload_url, fingerprint: public_key.fingerprint }
      when :disabled
        "Account '%{owner}' is disabled. Please ask the owner to check their account." % { owner: repository.plan_owner&.display_login || "owner" }
      when :locked
        if member.to_s == repository.owner.to_s
          message = <<~MSG
          Your repository is disabled.
          Please see %{url} for more information.
          MSG
          message % { url: "#{GitHub.url}/#{repository.name_with_display_owner}" }
        else
          message = <<~MSG
          Repository '%{repo}' is disabled.
          Please ask the owner to check their account.
          MSG
          message % { repo: repository.name_with_display_owner }
        end
      when :license
        message = <<~MSG
        The GitHub Enterprise license has expired.
        Please visit %{url} to obtain a license.
        MSG
        message % { url: GitHub.enterprise_web_url }
      when :ssh_disabled
        message = <<~MSG
        SSH Access to this repository has been disabled.
        %{url} for more information.
        MSG
        message % { url: GitHub.support_link_text }
      when :too_early
        "This SSH certificate is not yet valid."
      when :too_late
        "This SSH certificate has expired."
      when :ssh_error
        "We encountered an error parsing your SSH key."
      when :bad_ssh_ca
        "This SSH certificate may only be used with repositories owned by the %{owner}" % { owner: ssh_ca.owner_name_and_type }
      when :ssh_certificate_required
        "This repository requires SSH certificate authentication. Contact the owner to receive a certificate."
      when :not_ip_allowlisted
        "The repository owner has an IP allow list enabled, and %{ip} is not permitted to access this repository." % { ip: authentication.ip }
      when :archived
        "This repository was archived so it is read-only."
      when :read_only
        message = <<~MSG
        This repository is currently in read-only mode.
        %{url} if this repository remains read-only for an extended period of time.
        MSG
        message % { url: GitHub.support_link_text }
      when :ofac_sanctioned_user
        TradeControls::Notices.notice_as_plaintext(:repo_disabled)
      when :admin_of_ofac_sanctioned_organization
        TradeControls::Notices.notice_as_plaintext(:org_restricted_repo_for_admins)
      when :collaborator_in_ofac_sanctioned_organization
        TradeControls::Notices.notice_as_plaintext(:org_restricted_repo_for_collaborators)
      when :ofac_sanctioned_repository, :collaborator_on_ofac_sanctioned_repository
        "This repository has been disabled. Please contact %{owner}, to resolve the issue." % { owner: repository.network_owner.display_login }
      when :no_writes_to_cache_server
        "This cache server is read-only."
      when :invalid_validity_period
        message = <<~MSG
        The SSH certificate used has longer expiration than allowed (%{ssh_certificate_lifetime_days} days).
        Contact the enterprise or organization owner to receive a certificate that is valid.
        Please see %{url} for information on max certificate lifetime.
        MSG
        message % {
          ssh_certificate_lifetime_days: (SSHCertificateAuthority::DEFAULT_MAX_SSH_CERT_LIFETIME_IN_HOURS / 24).round,
          url: "https://docs.github.com/organizations/managing-git-access-to-your-organizations-repositories/about-ssh-certificate-authorities"
        }
      when :invalid_due_to_user_activity
        message = <<~MSG
        The account associated with the SSH certificate was created or renamed after the certificate was issued.
        Contact the enterprise or organization owner to receive a new certificate.
        MSG
        message % { url: "https://docs.github.com/organizations/managing-git-access-to-your-organizations-repositories/about-ssh-certificate-authorities" }
      else
        fail "unexpected #{status.inspect} from permission check"
      end
    end

    private

    def repository
      target.repository
    end

    def ssh_enabled?
      @ssh_enabled
    end
  end
end
