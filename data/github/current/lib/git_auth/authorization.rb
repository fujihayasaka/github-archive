# typed: true
# frozen_string_literal: true

require "forwardable"

module GitAuth
  class Authorization
    extend Forwardable
    include GitAuth::ConditionalAccessDependency
    include GitHub::Memoizer
    include GitHub::Tracing
    include Scientist

    attr_reader :target, :authentication

    def_delegators :authentication, :member, :protocol, :action, :ip, :ssh_ca, :user, :public_key, :token, :request_access_security_header

    def initialize(target:, authentication:)
      @target         = target
      @authentication = authentication
    end

    def maintainer?
      !!@maintainer
    end

    def running_on_cache_server?
      !!ENV["ENTERPRISE_CLUSTER_CACHE_LOCATION"]
    end

    def check
      GitAuth::Metrics.time("authorization.check") do
        return :no_git_protocol if protocol == "git" && !GitHub.git_protocol_enabled?

        if anonymous?(member) && GitHub.private_mode_enabled?
          return :anonymous_access_denied if repository.nil?
          return :anonymous_access_denied if target.gist? || target.wiki?
          return :ok if action == :read && repository.anonymous_git_access_enabled?
          return :anonymous_access_denied
        end

        return :missing if anonymous?(member) && repository.nil?

        if anonymous?(member) && action == :write
          # Private
          return :unauthorized_access_to_private_repository if repository.private?

          # Public
          return :no_access_to_spammy_repository if repository.spammy?
          return :no_anonymous_writes
        end

        if running_on_cache_server?
          if action == :write
            return :no_writes_to_cache_server
          elsif action == :read
            # Cache servers don't reveal existence of repos which aren't in the local cache location.
            return :missing if !repository.nil? && repository.dgit_read_routes(cache_servers_ok: true).empty?
          end
        end

        # Reads
        if anonymous?(member)
          return :unauthorized_access_to_private_repository if !target.gist? && repository.private?
          return :unauthorized_access_to_private_repository if target.gist? && repository.private? && protocol == "git"
          return :no_access_to_spammy_repository if repository.spammy?
          return :tos_violation if repository_access.tos_violation?
          return :sensitive_data_violation if repository_access.sensitive_data_violation?
          return :broken if repository_access.broken?
          return :abusive if repository_access.disabled?
          return :locked if repository.locked?
          return :ok
        end

        if member == :slumlord
          return :missing if repository.nil?

          return :no_access_to_spammy_repository if repository.spammy?

          return :tos_violation if repository_access.tos_violation?
          return :sensitive_data_violation if repository_access.sensitive_data_violation?
          return :broken if repository_access.broken?
          return :abusive if repository_access.disabled?
          return :locked if repository.locked?
          return :disabled if repository.disabled_private?
        end

        if member == :slumlord && action == :write
          return :read_only if repository.read_only?
          return :ok
        end

        # The full-trust service is a special case.
        # It only has to take into account the repo-specific
        # errors. Once we're passed that, we're good to go.
        if member.to_s.start_with?("gitauth-full-trust:")
          return :missing if repository.nil?
          return :missing if repository.spammy?
          return :tos_violation if repository_access.tos_violation?
          return :sensitive_data_violation if repository_access.sensitive_data_violation?
          return :broken if repository_access.broken?
          return :abusive if repository_access.disabled?
          return :locked if repository.locked?
          return :archived if repository.archived? && action == :write
          return :disabled if repository.disabled_private?
          return :ok
        end

        unless member.is_a?(String)
          raise TypeError, "Invalid member: #{member.inspect}"
        end

        # If we're still here we should either have a user, or this is a valid deploy key.
        if user.nil? && public_key&.repository.nil?
          raise ArgumentError, "auth must be either a user or a deploy key"
        end

        # We've completed the authentication checks, so by this point we either
        # have a user, or this action is being taken by a deploy key.
        # If there is a user, then we can check for things that are
        # unrelated to the repository first.
        return :suspended if user&.suspended?
        return :ofac_sanctioned_user if is_ofac_sanctioned?(check_user: true)
        return :verified_email_required if action == :write && user&.must_verify_email?

        if member.start_with?("repo:") && GitHub.private_mode_enabled?
          return :invalid_deploy_key if repository.nil?
          return :invalid_deploy_key if repository.is_a?(Repository) && public_key.repository.id != repository.id
        end

        if target.gist?
          return :missing if repository.nil?

          # If you're authenticating with an SSH certificate, then
          # you can't access user-owned gists.
          return :bad_ssh_ca if ssh_ca

          # In private mode, you cannot access gists with deploy keys at all.
          if member.start_with?("repo:") && GitHub.private_mode_enabled?
            return :invalid_deploy_key
          end

          if action == :read
            # Private gists are readable except over unencrypted git://
            return :invalid_protocol_for_secret_gist if repository.private? && protocol == "git"
            return :ok
          end

          # All gists are writable when the user is an actual User and has the
          # `update_gist` Egress role on the Gist
          return :ok if user && AccessControl.new(viewer: user).can_update_gist?(repository)
          return :unauthorized_access_to_secret_gist if repository.private?
          return :unauthorized_write_to_gist
        end

        prefill_organization

        # run the check gamut
        case
        when repository.nil?
          # no repository found matching the given path
          :missing
        when repository.spammy? && !repository.resources.contents.writable_by?(user)
          # spammy repos should appear as missing for non-members
          :no_access_to_spammy_repository
        when user_cannot_read_repository_contents?
          # when a user cannot read the repository, regardless of action, return a not found error
          :unauthorized_access_to_private_repository

        # The following group of error statuses are "no matter what" statuses.
        # However, the error message depends on whether or not you're allowed
        # to know about the repo or not, so it must come after the check for 'unpullable'.
        when repository_access.tos_violation?
          # TOS-violating are neither writable nor readable no matter what
          :tos_violation
        when repository_access.sensitive_data_violation?
          # Repos disabled for sensitive data policy violations are neither writable nor readable no matter what
          :sensitive_data_violation
        when repository_access.trademark_violation?
          # Repos disabled for trademark policy violations are neither writable nor readable no matter what
          :trademark_violation
        when repository_access.broken?
          # broken repos have missing objects and therefore cannot fully cloned anymore
          :broken
        when repository_access.disabled?
          # abusive repos are neither writable nor readable no matter what
          :abusive
        when repository.locked?
          :locked
        when action == :write && repository.archived?
          # archived repositories aren't writable by anyone
          :archived
        when repository.disabled_private?
          :disabled
        when is_ofac_sanctioned?
          if member.start_with?("repo:") # is this a deploy key?
            :ofac_sanctioned_repository
          elsif repository.network_owner.organization? && repository.network_owner.adminable_by?(user)
            :admin_of_ofac_sanctioned_organization
          elsif repository.network_owner.organization?
            :collaborator_in_ofac_sanctioned_organization
          else
            :collaborator_on_ofac_sanctioned_repository
          end
        when action == :read && repository.public?
          # public repositories are world readable
          :ok

        # This is a very long condition, but until I get the entire :check method
        # refactored I do not want to extract it into a helper method.
        # I promise it will be worth it. -kytrinyx
        when GitHub.oauth_application_policies_enabled? && public_key&.created_by_unknown? && repository.policymaker.restricts_oauth_applications?
          # The repository's OAuth application policy blocks access to some
          # apps, and we don't know who created the key that is being used to
          # access the repository (e.g., was it created by a blocked app?).
          :oap_denied_key_unknown_origin
        when public_key_app_blocked_by_oauth_app_policy?
          if repository.private?
            :unauthorized_access_to_private_repository
          else
            # The repository's OAuth application policy blocks access to the app
            # that created the key or OAuth token that is being used to access the
            # repository.
            :oap_denied_app
          end
        when member_app_blocked_by_oauth_app_policy?
          if repository.private?
            :unauthorized_access_to_private_repository
          else
            # The repository's OAuth application policy blocks access to the app
            # that created the key or OAuth token that is being used to access the
            # repository.
            :oap_denied_app
          end
        when deploy_key_policy_disabled?
          # If an enterprise/org has disabled deploy key usage,
          # they should not be allowed to write to any repository.
          #
          if repository.private?
            :unauthorized_access_to_private_repository
          else
            :invalid_deploy_key
          end
        when member.start_with?("repo:")
          # If we reach this branch, we're either performing a read on a private repository, or a write.
          #
          # We have previously verified that the deploy key is internally consistent
          # with the 'member' value passed: the repo in the member matches the deploy
          # key's repo.
          #
          # Now we have to check that this deploy key is actually allowed to access
          # the target repository.
          if public_key.repository.id == repository.id
            perform_conditional_access_checks
          elsif repository.private?
            :unauthorized_access_to_private_repository
          else
            :invalid_deploy_key
          end
        when action == :write && repository.read_only?
          :read_only
        # writing to public repos and reading/writing from private repos
        # requires a real access check.
        when member_can?(repository)
          check_writing_to_public_and_reading_or_writing_from_private
        when repository.parent && target.normal_repo? && repository.public? && !repository.in_organization? && member_can?(repository.parent)
          @maintainer = true
          check_fork_maintainer
        # Deny access to fork when root repository owner IP allowlist condition not met
        # Temporary for Intel. See https://github.com/github/reponauts/issues/53.
        when repository.ip_restricted_private_fork?
          # If the FF :intel_fork_ip_allowlist_org is enabled for a non-intel repo owner and non-ip-allowlisted org
          # this case doesnt return anything and the result from the function will be nil.
          # It seems like this may have been coded in a way that it expected the case statement to fall through
          # which Ruby does not do. This shouldn't be a gap in whether or not correct access is granted,
          # but it makes testing a bit more difficult due to the all feature flag test CI.
          return :ok if intel_pass_through?(repository.root)
          failed_policy = perform_conditional_access_checks(
            resource: repository.root, policies: [:ip_allowlist]
          )
          return failed_policy if failed_policy != :ok
        when repository.private?
          # At this point, we have verified that the user has read access, but not write access to the target repo. Fail with a no-write access error.
          :unauthorized_write_access_to_private_repository
        else
          :access_denied_to_user
        end
      end
    end
    trace_method :check

    private

    def intel_pass_through?(repository)
      if user.bot? && repository.owner.ip_allowlist_enabled?
        IpAllowlistEntry.usable_for(repository.owner).active.matching_ip(ip).any?
      end
    end

    def repository
      target.repository
    end

    def anonymous?(member)
      member == :anonymous
    end

    def is_ofac_sanctioned?(check_user: false)
      return false unless GitHub.billing_enabled?
      return false if repository.nil?
      return false unless repository.is_a?(Repository)
      return false unless repository.private?
      return false if user_cannot_read_repository_contents?

      return user_and_repo_trade_restrictions[0] if check_user
      user_and_repo_trade_restrictions[1]
    end

    # Ensures we only need to load from the trade_controls_restrictions table once
    memoize def user_and_repo_trade_restrictions
      repository.async_plan_owner.then do |plan_owner|
        Promise.all([user&.async_has_any_trade_restrictions?, plan_owner.async_has_any_trade_restrictions?]).then do
          [user&.has_any_trade_restrictions?, repository.has_any_trade_restrictions?]
        end
      end.sync
    end

    memoize def user_cannot_read_repository_contents?
      user && !repository.resources.contents.readable_by?(user)
    end

    def repository_access
      @repository_access ||= repository.access
    end

    def oauth_application
      if public_key && public_key.created_by_oauth_application?
        public_key.oauth_application
      elsif (access = user.try(:oauth_access))
        access.application
      else
        nil
      end
    end

    def public_key_app_blocked_by_oauth_app_policy?
      return false unless GitHub.oauth_application_policies_enabled?
      return false unless public_key&.created_by_oauth_application?

      OauthApplicationPolicy::Application.new(repository, public_key.oauth_application).violated?
    end

    def member_app_blocked_by_oauth_app_policy?
      return false unless GitHub.oauth_application_policies_enabled?
      return false unless user&.oauth_access&.application

      OauthApplicationPolicy::Application.new(repository, user.oauth_access.application).violated?
    end

    def saml_enforced?(repo)
      evaluate_git_auth_saml_debug_logging("Start evaluating SAML enforced?")
      return false unless repo.owner.organization?

      org = repo.organization
      return false unless org
      evaluate_git_auth_saml_debug_logging("Repo owner is Org")

      provider_owner = org.external_identity_session_owner
      evaluate_git_auth_saml_debug_logging("Provider owner is #{provider_owner}")

      enforcement_policy = case provider_owner
      when ::Organization
        Organization::SamlEnforcementPolicy.new(organization: org, user: user)
      when ::Business
        Business::SamlEnforcementPolicy.new(business: provider_owner, organization: org, user: user)
      end

      enforced = T.must(enforcement_policy).enforced?

      evaluate_git_auth_saml_debug_logging("SAML enforced? #{enforced}")
      enforced
    end

    def saml_credential_present?(repo)
      evaluate_git_auth_saml_debug_logging("Start evaluating SAML credential present?")
      # GHES with SCIM enabled user's PAT and SSH keys are scoped to the enterprise and do not have the concept of organization authorization.
      # If a user's PAT or SSH key is valid on the enterprise, then it is valid for any non private repo in the enterprise.
      return true if GitHub.global_business&.enterprise_server_scim_enabled?
      evaluate_git_auth_saml_debug_logging("Not a GHES with SCIM enabled")
      # At this point, either SAML is enforced or the user has opted into SAML
      # before enforcement. They must have an authorized PAT or PublicKey now.
      org = repo.organization
      provider_owner = org.external_identity_session_owner

      # For private repos, if feature flag is enabled for the user associated with the credential,
      # then treat as internal repo and allow access. This is to allow repo migrations to for multiple
      # organizations work without needing an authorized PAT for each org.
      allow_private_repo = user.present? && GitHub.flipper[:sso_same_business_cred_authz_private_repos].enabled?(user) && org.business.present? && repo.private?
      log_context = {
        "gh.cap_experiment.user.is_present": user.present?,
        "gh.cap_experiment.sso_same_cred.is_enabled": GitHub.flipper[:sso_same_business_cred_authz_private_repos].enabled?(user),
        "gh_cap_experiment.org.business.is_present": org.business.present?,
        "gh_cap_experiment.repo.is_private": repo.private?
      }
      evaluate_git_auth_saml_debug_logging("Allow private repo? #{allow_private_repo}", options: log_context)

      # For internal repos or forks of internal repos, we check
      # for SAML credentials against all business member orgs.
      internal_repo = (repository.internal? || repository.internal_fork? || allow_private_repo)
      treat_as_internal = provider_owner.is_a?(::Business) && internal_repo
      internal_context = {
        "gh.cap_experiment.business.is_provider": provider_owner.is_a?(::Business),
        "gh.cap_experiment.repo.is_internal": internal_repo
      }
      evaluate_git_auth_saml_debug_logging("Treat as internal? #{treat_as_internal}", options: internal_context)

      orgs = if treat_as_internal
        provider_owner.organizations.to_a
      else
        [org]
      end

      if token.present?
        evaluate_git_auth_saml_debug_logging("Start evaluating Oauth Credential")
        return false if user&.oauth_access.nil?

        evaluate_git_auth_saml_debug_logging("User has Oauth Access")
        has_credential = !!Organization::CredentialAuthorization.authorization(organization: orgs, credential: user.oauth_access)
        evaluate_git_auth_saml_debug_logging("SAML credential present? #{has_credential}")
        has_credential
      elsif public_key
        is_active = public_key.authorization_active_for_any_orgs?(orgs)
        evaluate_git_auth_saml_debug_logging("PublicKey is active? #{is_active}")
        is_active
      else
        evaluate_git_auth_saml_debug_logging("Defaulting to false")
        false
      end
    end

    # Allows internal integrations to be configured to bypass SSH CA verification. Primary use-case is for
    # codespaces to be used on repositories that are configured to require SSH CA.
    def skip_ssh_ca_verification?
      return false unless oauth_access = user.oauth_access
      return false unless oauth_access.installation
      Apps::Privileged.capable?(:skip_ssh_ca_verification, app: oauth_access.installation.integration)
    end

    # returns false if the request does not meet the SSH CA requirement check
    def passes_ssh_certificate_requirement_check(resource:)
      # short circuit if the resource doesn't require SSH CA
      return true unless resource.ssh_certificate_requirement_enabled?

      # a GitHub App server to server authorization is exlcuded from the requirement
      return true if user&.bot?

      # an Oauth application generated public key is excluded from the requirement
      return true if public_key&.created_by_oauth_application?

      # a programmatic access token request is excluded from the requirement
      return true if user&.using_auth_via_user_programmatic_access?

      # a GitHub App user to server authorization is excluded from the requirement
      if user&.oauth_access&.integration_application_type?
        GitHub.dogstats.increment("gitauth.passes_ssh_certificate_requirement_check", tags: ["type:user_to_server", "result:true"])
        return true
      end

      !!ssh_ca
    end

    # returns false if the request does not meet the SAML requirement check
    def passes_saml_check(resource:)
      if git_auth_saml_experiment_enabled?
        passes_saml_check_with_experiment(resource:)
      else
        passes_saml_check_control(resource:)
      end
    end

    def passes_saml_check_with_experiment(resource:)
      # we are breaking the passes_saml_check_control appart

      # the first part, is returning true if any of them apply
      # meaning that the satisfied part won't be executed
      # this matches to :inapplicable of a CAP policy
      inapplicable = control_inapplicable_experiment(resource: resource)

      # if inapplicable is false, we know that the policy applies to the user,
      # so we are going to compute satisfied
      satisfied = !!saml_credential_present?(resource) unless inapplicable

      Scientist.run "authzd_cap_git_auth" do |e|
        e.use do
          if inapplicable
            { saml: :inapplicable }
          else
            { saml: satisfied ? :satisfied : :unsatisfied }
          end
        end
        e.try do
          cap_enforcer.authzd_evaluate_conditional_access_policies(resource, policies: [:saml])
        end
        e.compare do |control, experiment|
          matched = control == experiment
          tags = ["match:#{matched}", "enforcer:GitAuth::Authorization"]

          begin
            tags << "saml:#{matched ? "match" : "mismatch"}"
            tags << "saml_control:#{control[:saml]}" if !control.nil? && control[:saml]
            tags << "saml_candidate:#{experiment[:saml]}" if !experiment.nil? && experiment[:saml]

            GitHub.dogstats.count("cap_extraction_experiment_result", 1, tags: tags)
          rescue StandardError => ex # rubocop:todo Lint/GenericRescue
            # we can still stat the match and enforcer tags here in the case where
            # we may have caused an exception in the block above calculating the more detailed tags
            GitHub.dogstats.count("cap_extraction_experiment_result", 1, tags: tags)
          end
          matched

        end
      end

      return true if inapplicable
      satisfied
    end

    def control_inapplicable_experiment(resource:)
      # SAML requirements don't apply for GitHub App server to server authorization
      return true if user&.bot?
      evaluate_git_auth_saml_debug_logging("GitAuth User is not a bot")

      # SAML requirements don't apply to programmatic access token requests. SAML is enforced in the UI when granting access to repositories.
      return true if user&.using_auth_via_user_programmatic_access?
      evaluate_git_auth_saml_debug_logging("GitAuth User is not using programmatic access")
      # As of November 2019 we changed the rules about SAML
      # enforcement.
      #
      # Before this date all OAuth Apps and GitHub App
      # user to server authorizations ignored all SAML
      # requirements. They forcibly bypassed the SAML
      # protections on Organizations.
      #
      # Any OAuth App tokens and GitHub App user to
      # server authorizations created after that date
      # need to be authorized explicitly by the organization,
      # thereby respecting the SAML requirements.
      #
      # This makes this _way_ more complicated but is necessary
      # for security purposes and to not break existing credentials.

      if (oauth_access = user&.oauth_access)
        evaluate_git_auth_saml_debug_logging("Start evaluating Oauth Access Enforceable")
        return true unless oauth_access.saml_enforceable?

        evaluate_git_auth_saml_debug_logging("Oauth Access is enforceable")
      end
      !saml_enforced?(resource)
    end

    def passes_saml_check_control(resource:)
      # SAML requirements don't apply for GitHub App server to server authorization
      return true if user&.bot?

      # SAML requirements don't apply to programmatic access token requests. SAML is enforced in the UI when granting access to repositories.
      return true if user&.using_auth_via_user_programmatic_access?

      # As of November 2019 we changed the rules about SAML
      # enforcement.
      #
      # Before this date all OAuth Apps and GitHub App
      # user to server authorizations ignored all SAML
      # requirements. They forcibly bypassed the SAML
      # protections on Organizations.
      #
      # Any OAuth App tokens and GitHub App user to
      # server authorizations created after that date
      # need to be authorized explicitly by the organization,
      # thereby respecting the SAML requirements.
      #
      # This makes this _way_ more complicated but is necessary
      # for security purposes and to not break existing credentials.
      if (oauth_access = user&.oauth_access)
        return true unless oauth_access.saml_enforceable?
      end
      return true unless saml_enforced?(resource)
      !!saml_credential_present?(resource)
    end

    memoize def git_auth_saml_experiment_enabled?
      GitHub.flipper[:run_authzd_cap_experiment].enabled? && GitHub.flipper[:run_authzd_cap_experiment_git_auth_saml].enabled?
    end

    def evaluate_git_auth_saml_debug_logging(msg, options = {})
      return unless git_auth_saml_experiment_enabled?

      GitHub.logger.info(
        msg,
        {
          "code.function": "evaluate_git_auth_saml_applicable",
          "gh.request_id": GitHub.context[:request_id],
           **options
        }
      )
    end

    # Checks if the repository is in an enterprise/organization that has disabled deploy keys usage
    def deploy_key_policy_disabled?
      # These checks might not be necessary, but they're here to be safe.
      return false unless member.start_with?("repo:")
      return false if repository.nil?

      # Is an override in place? (example: a repository migration)
      if GitHub::Authentication::KV.store.get("#{Configurable::DeployKeyPolicy::BYPASS_KV_KEY}:#{public_key.id}").value { nil } == "true"
        GitHub.dogstats.increment("gitauth.deploy_key_policy.override")
        return false
      end

      deploy_keys_disabled, _ = repository.deploy_keys_disabled_by_policy_with_policy_source
      GitHub.dogstats.increment("gitauth.deploy_key_policy.check", tags: ["result:#{deploy_keys_disabled}", "repository_mismatch:#{public_key.repository_id != repository.id}"])
      deploy_keys_disabled
    end

    def check_ssh_certificate_repo_access
      # if it's not a cert, don't do anything here
      return :ok unless ssh_ca

      # If the repo is in and owned by an organization linked to the SSH CA, do nothing here
      if GitHub.flipper[:ssh_ca_repo_forks].enabled?(user)
        return :ok if repository.in_organization? && ssh_ca.owned_by_repo_owner?(repository)
      else
        return :ok if repository.in_organization?
      end
      # Note: private forks of organization repositories will continue since they're 'in_organization?' but
      # still user owned, so the user owned access checks still apply to them

      # check that the owner of the CA (the enterprise) has enabled user owned repo access for SSH certificates
      # this check ensures the CA belongs to a EMU business or if we're in GHES
      return :bad_ssh_ca unless ssh_ca.can_access_user_owned_repositories?

      # in GHES, other users in the enterprise may have created
      # "public" repos. We should allow SSH certs to access those
      # the "member_can?" check would have failed if it was a private repo
      return :ok if GitHub.enterprise?

      # for EMUs (GHEC and Proxima), users can _only_ create "private" personal repos
      # however, rather than a simple return :ok, we should double check
      # that the repo is owned by the user of the SSH certificate just in case
      # there's some change to personal repo types in these environments in the future
      # NOTE: user is determined by the login_extension of the certificate
      return :bad_ssh_ca unless repository.owner == user

      # User owned repositories should be scoped within the EMU enterprise
      # This check ensures the SSH CA is associated to the EMU and the SSH CA is owned by the business
      if GitHub.flipper[:ssh_ca_emu_check].enabled?(user)
        return :bad_ssh_ca unless ssh_ca.owned_by_business?(user&.enterprise_managed_business&.id)
      end
      :ok
    end

    def check_writing_to_public_and_reading_or_writing_from_private
      return :bad_ssh_ca if check_ssh_certificate_repo_access != :ok

      failed_policy = perform_conditional_access_checks
      return failed_policy if failed_policy != :ok

      return :ssh_certificate_required unless passes_ssh_certificate_requirement_check(resource: repository)

      # We never perform SAML checks if accessing via a SSH certificate.
      if ssh_ca
        return :bad_ssh_ca if !GitHub.flipper[:ssh_ca_repo_forks].enabled?(user) && repository.in_organization? && !ssh_ca.owned_by_repo_owner?(repository)
        # repository checks happen above if applicable
        return :ok
      end

      return :credential_authorization_missing unless passes_saml_check(resource: repository)
      :ok
    end

    def check_fork_maintainer
      if !repository.parent.in_organization?
        # If you're authenticating with an SSH certificate, then
        # you can't access user-owned repos.
        return :bad_ssh_ca if ssh_ca

        # We can short circuit :ok here becuase it's a public repo and not in an org
        return :ok
      end

      failed_policy = perform_conditional_access_checks(resource: repository.parent)
      return failed_policy if failed_policy != :ok

      if GitHub.oauth_application_policies_enabled? && public_key&.created_by_unknown?
        GitHub.dogstats.increment("gitauth.maintainer_via_app", tags: ["type:pubkey_unknown_origin"])
        # The repository's OAuth application policy blocks access to some
        # apps, and we don't know who created the key that is being used to
        # access the repository (e.g., was it created by a blocked app?).
        return :oap_denied_key_unknown_origin if repository.parent.policymaker.restricts_oauth_applications?
      end

      if GitHub.oauth_application_policies_enabled? && oauth_application
        return :oap_denied_app if OauthApplicationPolicy::Application.new(repository.parent, oauth_application).violated?
      end

      return :ssh_certificate_required unless passes_ssh_certificate_requirement_check(resource: repository.parent)

      # We never perform SAML checks if accessing via a SSH certificate.
      if ssh_ca
        # Check that the SSH CA is valid for the repo
        return :bad_ssh_ca if !ssh_ca.owned_by_repo_owner?(repository.parent)
        return :ok
      end

      return :credential_authorization_missing unless passes_saml_check(resource: repository.parent)

      log_check_fork_maintainer_request_type
      :ok
    end

    # Log to Splunk for troubleshooting.
    def log_check_fork_maintainer_request_type
      if user&.bot?
        payload = {
          "code.namespace" => self.class.name,
          "code.function" => __method__,
          "gh.gitauth.code_path" => "maintainer_via_app",
          "gh.gitauth.type" => "server-to-server",
          "gh.integration.id" => user&.integration&.id,
          "gh.repo.id" => repository.id
        }
        ::GitHub.logger.info("GitAuth fork maintainer request", payload)
      elsif user&.using_auth_via_user_programmatic_access?
        payload = {
          "code.namespace" => self.class.name,
          "code.function" => __method__,
          "gh.gitauth.code_path" => "maintainer_via_pat",
          "gh.gitauth.type" => "user_programmatic_access",
          "gh.user_programmatic_access.id" => user.programmatic_access.id,
          "gh.repo.id" => repository.id
        }
        ::GitHub.logger.info("GitAuth fork maintainer request", payload)
      elsif oauth_application
        payload = {
          "code.namespace" => self.class.name,
          "code.function" => __method__,
          "gh.gitauth.code_path" => "maintainer_via_app",
          "gh.gitauth.type" => oauth_application.is_a?(Integration) ? "user-to-server" : "oauth",
          "gh.oauth.app.id" => oauth_application.id,
          "gh.repo.id" => repository.id
        }
        ::GitHub.logger.info("GitAuth fork maintainer request", payload)
      end
    end

    class AccessControl < Platform::Authorization::Permission
      attr_reader :env
      def initialize(context)
        context[:origin] = Platform::ORIGIN_API
        @env = {}
        super
      end

      def graphql_request?
        false
      end

      def repository_accessible?(action, repository)
        action =
          case action
          when :read  then :pull
          when :write then :push
          else
            return false
          end
        # cap_bypass:to_fix disabling was done because of reverting a PR that introduced an bug - ref https://github.com/github/github/pull/171790
        access_allowed?(action,
          resource: repository,
          current_repo: repository,
          current_org: nil,
          disable_conditional_access_policies: true, # rubocop:disable GitHub/DoNotSkipCapAccessAllowed
          allow_integrations: true,
          allow_user_via_granular_actor: true,
          raise_on_error: false,
          enforce_oauth_app_policy: false,
        )
      end

      def can_update_gist?(gist)
        access_allowed?(:update_gist,
          resource: gist,
          current_repo: nil,
          current_org: nil,
          allow_integrations: false,
          allow_user_via_granular_actor: false,
          raise_on_error: false,
          enforce_oauth_app_policy: false,
        )
      end
    end

    # Optimization to reduce the need to query for the organization when we already have the owner (which is almost always the organization)
    def prefill_organization
      return if repository.nil?

      if repository.association(:owner).loaded? && repository.organization_id.present?
        GitHub::PrefillAssociations.prefill_associations(repository, :organization, available_records: [repository.owner])
      end
    end

    def member_can?(repo)
      Platform::Security::RepositoryAccess.with_viewer(user) do
        AccessControl.new(viewer: user).repository_accessible?(action, repo)
      end
    end
  end
end
