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

        return :missing if anonymous?(member) && (repository.nil? || repository.deleted?)

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
        when unknown_origin_key_blocked_by_oauth_app_policy?
          # The repository's OAuth application policy blocks access to some
          # apps, and we don't know who created the key that is being used to
          # access the repository (e.g., was it created by a blocked app?).
          :oap_denied_key_unknown_origin
        when app_blocked_by_oauth_app_policy?
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

        when repository.ip_restricted_private_fork?
          # If we get here, we know the following:
          # 1. repo is a private fork of an Intel-owned repo
          # 2. user_cannot_read_repository_contents? is false. So the user has some level of read access
          # 3. member_can?(repository) is false, so the user may not be able to read the repo (possibly due to IP restrictions)

          # We now need to do some special evaluations on the network root, special for Intel
          intel_repo = repository.root

          # Return OK (without any CAP checks) if:
          # 1. the actor is a bot, and
          # 2. the caller's IP address matches an Intel IpAllowlistEntry
          if intel_pass_through?(intel_repo)
            GitHub.logger.info(
              "Intel pass through",
              "code.function" => "check",
              "gh.gitauth.repo.id" => repository.id,
              "gh.gitauth.root.repo.id" => intel_repo&.id,
            )
            return :ok
          end

          # Call Authzd to perform another IP Allowlist check, special for Intel
          # Return the outcome if it fails. The only outcomes are :ok or :not_ip_allowlisted
          outcome = perform_conditional_access_checks(resource: intel_repo, policies: [:ip_allowlist], intel_fix: true)
          if outcome != :ok
            GitHub.logger.info(
              "Intel CAP failed",
              "code.function" => "check",
              "gh.gitauth.repo.id" => repository.id,
              "gh.gitauth.root.repo.id" => intel_repo&.id,
              "gh.gitauth.outcome" => outcome,
            )
            return outcome
          end

          # If we get here, the IP Allowlist check failed in GitAuth, but passed in Authzd. How does that happen?

          # We know that user_cannot_read_repository_contents? is false, which means the user has read access
          # but we also know that member_can?(repository) is false, which means the user does not have the access they requested.
          # If the action is :read, this suggests that the user should have access, but were denied by the IP Allowlist policy.
          if action == :read
            GitHub.logger.info(
              "Intel read denied",
              "code.function" => "check",
              "gh.gitauth.repo.id" => repository.id,
              "gh.gitauth.root.repo.id" => intel_repo&.id,
            )

            return :not_ip_allowlisted
          end

          GitHub.logger.info(
            "Intel write denied",
            "code.function" => "check",
            "gh.gitauth.repo.id" => repository.id,
            "gh.gitauth.root.repo.id" => intel_repo&.id,
          )
          :unauthorized_write_access_to_private_repository
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

    def unknown_origin_key_blocked_by_oauth_app_policy?
      if use_authzd_oap_and_saml?
        oap_status_code_authzd_cap == :oap_denied_key_unknown_origin
      elsif run_gitauth_oap_saml_cap_experiment?
        science_class = GitHub.multi_tenant_enterprise? && !Rails.env.test? ? ConditionalAccess::ProximaScientist : Scientist # rubocop:disable GitHub/DoNotBranchOnRailsEnv
        # this experiment should be 100%
        science_class.run "gitauth_oap_saml_cap_experiment_oap" do |e|
          e.use { GitHub.oauth_application_policies_enabled? && public_key&.created_by_unknown? && repository.policymaker.restricts_oauth_applications? }
          e.try { oap_status_code_authzd_cap == :oap_denied_key_unknown_origin }
          e.compare do |control, experiment|
            matched = oap_experiment_comparison(control, experiment)
            # if we're using the custom ProximaScientist class, we won't have
            # the Scientist UI tooling with all of the context about mismatches
            # so for now we'll just log as much as we can here
            # the log automatically has the request ID, which can help us diagnose further if needed
            # Exception handling is part of the custom ProximaScientist class
            if !matched && GitHub.multi_tenant_enterprise?
              GitHub.logger.info(
                "Mismatch in authzd cap experiment",
                "code.function" => "unknown_origin_key_blocked_by_oauth_app_policy?",
                "authzd.cap.experiment_name" => "gitauth_oap_saml_cap_experiment_oap",
                "authzd.cap.location" => "GitAuth",
                "authzd.cap.policies" => "oap",
                "authzd.cap.control" => "#{control}",
                "authzd.cap.candidate" => "#{experiment}",
                "authzd.cap.resource.id" => repository&.try(:id) || 0,
                "authzd.cap.resource.type" => repository&.class&.name,
                "authzd.cap.oap.created_by_unknown?" => public_key&.created_by_unknown?,
              )
            end
            matched
          end
        end
      else
        GitHub.oauth_application_policies_enabled? && public_key&.created_by_unknown? && repository.policymaker.restricts_oauth_applications?
      end
    end

    def app_blocked_by_oauth_app_policy?
      if use_authzd_oap_and_saml?
        oap_status_code_authzd_cap == :oap_denied_app
      elsif run_gitauth_oap_saml_cap_experiment?
        science_class = GitHub.multi_tenant_enterprise? && !Rails.env.test? ? ConditionalAccess::ProximaScientist : Scientist # rubocop:disable GitHub/DoNotBranchOnRailsEnv
        # this experiment should be 100%
        science_class.run "gitauth_oap_saml_cap_experiment_oap" do |e|
          e.use { public_key_app_blocked_by_oauth_app_policy? || member_app_blocked_by_oauth_app_policy? }
          e.try { oap_status_code_authzd_cap == :oap_denied_app }
          e.compare do |control, experiment|
            matched = oap_experiment_comparison(control, experiment)
            # if we're using the custom ProximaScientist class, we won't have
            # the Scientist UI tooling with all of the context about mismatches
            # so for now we'll just log as much as we can here
            # the log automatically has the request ID, which can help us diagnose further if needed
            # Exception handling is part of the custom ProximaScientist class
            if !matched && GitHub.multi_tenant_enterprise?
              GitHub.logger.info(
                "Mismatch in authzd cap experiment",
                "code.function" => "app_blocked_by_oauth_app_policy?",
                "authzd.cap.experiment_name" => "gitauth_oap_saml_cap_experiment_oap",
                "authzd.cap.location" => "GitAuth",
                "authzd.cap.policies" => "oap",
                "authzd.cap.control" => "#{control}",
                "authzd.cap.control.public_key_blocked" => public_key_app_blocked_by_oauth_app_policy?,
                "authzd.cap.control.member_app_blocked" => member_app_blocked_by_oauth_app_policy?,
                "authzd.cap.candidate" => "#{experiment}",
              )
            end
            matched
          end
        end
      else
        public_key_app_blocked_by_oauth_app_policy? || member_app_blocked_by_oauth_app_policy?
      end
    end

    def oap_experiment_comparison(control, experiment)
      matched = !!control == !!experiment
      tags = ["match:#{matched}", "enforcer:GitAuth::Authorization"]

      begin
        tags << "oap:#{matched ? "match" : "mismatch"}"
        tags << "oap_control:#{control}"
        tags << "oap_candidate:#{experiment}"

        GitHub.dogstats.count("cap_extraction_experiment_result", 1, tags: tags)
      rescue StandardError => ex # rubocop:todo Lint/RescueException
        GitHub.dogstats.count("cap_extraction_experiment_result", 1, tags: tags)
      end
      matched
    end

    def oap_status_code_authzd_cap(resource: repository)
      return :allowed unless GitHub.oauth_application_policies_enabled?
      cap_result, message, code = oap_result_authzd_cap(resource)
      return :allowed unless cap_result == :unsatisfied

      if FeatureFlag.vexi.enabled?(:oap_status_authzd_cap_based_on_code, default: false)
        oap_status_authzd_cap_based_on_code(code)
      else
        Scientist.run "oap_status_authzd_cap_based_on_code" do |e|
          e.use do
            message.include?("Sorry, but @") ? :oap_denied_key_unknown_origin : :oap_denied_app
          end
          e.try do
            oap_status_authzd_cap_based_on_code(code)
          end
        end
      end
    end

    def oap_status_authzd_cap_based_on_code(code)
      code == :OAUTH_APP_KEY_UNKNOWN_ORIGIN ? :oap_denied_key_unknown_origin : :oap_denied_app
    end

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
      return false unless repo.owner.organization?

      org = repo.organization
      return false unless org

      provider_owner = org.external_identity_session_owner
      enforcement_policy = case provider_owner
      when ::Organization
        Organization::SamlEnforcementPolicy.new(organization: org, user: user)
      when ::Business
        Business::SamlEnforcementPolicy.new(business: provider_owner, organization: org, user: user)
      end

      T.must(enforcement_policy).enforced?
    end

    def saml_credential_present?(repo)
      # GHES with SCIM enabled user's PAT and SSH keys are scoped to the enterprise and do not have the concept of organization authorization.
      # If a user's PAT or SSH key is valid on the enterprise, then it is valid for any non private repo in the enterprise.
      return true if GitHub.global_business&.enterprise_server_scim_enabled?

      # At this point, either SAML is enforced or the user has opted into SAML
      # before enforcement. They must have an authorized PAT or PublicKey now.
      org = repo.organization
      provider_owner = org.external_identity_session_owner
      evaluate_git_auth_saml_debug_logging("SAML Provider owner: #{provider_owner.class.name}")

      # For private repos, if feature flag is enabled for the user associated with the credential,
      # then treat as internal repo and allow access. This is to allow repo migrations to for multiple
      # organizations work without needing an authorized PAT for each org.
      allow_private_repo = user.present? && FeatureFlag.vexi.enabled_or_raise?(:sso_same_business_cred_authz_private_repos, user) && org.business.present? && repo.private? # rubocop:disable GitHub/FeatureManagement/NoVexiEnabledOrRaiseUsage
      evaluate_git_auth_saml_debug_logging("Allow private repo: #{allow_private_repo}")

      # For internal repos or forks of internal repos, we check
      # for SAML credentials against all business member orgs.
      internal_repo = (repository.internal? || repository.internal_fork? || allow_private_repo)
      evaluate_git_auth_saml_debug_logging("Internal repo: #{internal_repo}")
      treat_as_internal = provider_owner.is_a?(::Business) && internal_repo
      evaluate_git_auth_saml_debug_logging("Treat as internal: #{treat_as_internal}")

      orgs = if treat_as_internal
        provider_owner.organizations.to_a
      else
        [org]
      end
      evaluate_git_auth_saml_debug_logging("SAML orgs found", { "orgs.count" => orgs.size, "orgs" => orgs.map(&:display_login) })

      if token.present?
        evaluate_git_auth_saml_debug_logging("Token is present and oauth access is nil?: #{user&.oauth_access.nil?}")
        return false if user&.oauth_access.nil?

        has_credential = !!Organization::CredentialAuthorization.authorization(organization: orgs, credential: user.oauth_access)
        evaluate_git_auth_saml_debug_logging("Token has SAML credential: #{has_credential}")
        has_credential
      elsif public_key
        is_active = public_key.authorization_active_for_any_orgs?(orgs)
        evaluate_git_auth_saml_debug_logging("Public key is active for any orgs: #{is_active}")
        is_active
      else
        evaluate_git_auth_saml_debug_logging("Neither token nor public key present")
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
      if use_authzd_oap_and_saml?
        passes_saml_check_authzd_cap(resource)
      elsif run_gitauth_oap_saml_cap_experiment?
        passes_saml_check_with_experiment(resource:)
      else
        passes_saml_check_control(resource:)
      end
    end

    def passes_saml_check_with_experiment(resource:)
      # we are breaking the passes_saml_check_control apart

      # the first part, is returning true if any of them apply
      # meaning that the satisfied part won't be executed
      # this matches to :inapplicable of a CAP policy
      inapplicable = control_inapplicable_experiment(resource: resource)

      # if inapplicable is false, we know that the policy applies to the user,
      # so we are going to compute satisfied
      satisfied = !!saml_credential_present?(resource) unless inapplicable

      # this experiment is enabled 100% of the time - we use the FF in run_gitauth_oap_saml_cap_experiment? to control participation
      # we need to use ProximaScientist for Proxima, to enable testing on Proxima
      science_class = GitHub.multi_tenant_enterprise? && !Rails.env.test? ? ConditionalAccess::ProximaScientist : Scientist # rubocop:disable GitHub/DoNotBranchOnRailsEnv
      science_class.run "gitauth_oap_saml_cap_experiment_saml" do |e|
        e.use do
          next :inapplicable if inapplicable
          next :satisfied if satisfied
          :unsatisfied
        end
        e.try do
          saml_result_authzd_cap(resource)
        end
        e.compare do |control, experiment|
          matched = control == experiment
          tags = ["match:#{matched}", "enforcer:GitAuth::Authorization"]

          begin
            tags << "saml:#{matched ? "match" : "mismatch"}"
            tags << "saml_control:#{control}"
            tags << "saml_candidate:#{experiment}"

            GitHub.dogstats.count("cap_extraction_experiment_result", 1, tags: tags)
            # if we're using the custom ProximaScientist class, we won't have
            # the Scientist UI tooling with all of the context about mismatches
            # so for now we'll just log as much as we can here
            # the log automatically has the request ID, which can help us diagnose further if needed
            # Exception handling is part of the custom ProximaScientist class
            if !matched && GitHub.multi_tenant_enterprise?
              GitHub.logger.info(
                "Mismatch in authzd cap experiment",
                "code.function" => "passes_saml_check_with_experiment",
                "authzd.cap.experiment_name" => "gitauth_oap_saml_cap_experiment_saml",
                "authzd.cap.location" => "GitAuth",
                "authzd.cap.policies" => "saml",
                "authzd.cap.control" => "#{control}",
                "authzd.cap.candidate" => "#{experiment}",
                "authzd.cap.resource.id" => resource&.try(:id) || 0,
                "authzd.cap.resource.type" => resource&.class&.name,
              )
            end
            matched
          rescue StandardError => ex # rubocop:todo Lint/RescueException
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

    # Checks if the repository is in an enterprise/organization that has disabled deploy keys usage
    def deploy_key_policy_disabled?
      # These checks might not be necessary, but they're here to be safe.
      return false unless member.start_with?("repo:")
      return false if repository.nil?

      # check if this deploy key is allowed to bypass the policy
      if public_key&.bypasses_policy? && public_key&.created_at > 7.days.ago
        GitHub.dogstats.increment("gitauth.deploy_key_policy.override")
        return false
      end

      deploy_keys_disabled, _ = repository.deploy_keys_disabled_by_policy_with_policy_source
      GitHub.dogstats.increment("gitauth.deploy_key_policy.check", tags: ["result:#{deploy_keys_disabled}", "repository_mismatch:#{public_key.repository_id != repository.id}"])
      deploy_keys_disabled
    end

    def evaluate_git_auth_saml_debug_logging(msg, options = {})
      return unless run_gitauth_oap_saml_cap_experiment?

      GitHub.logger.info(
        msg,
        {
          "code.function": "evaluate_git_auth_saml_experiment",
          "gh.request_id": GitHub.context[:request_id],
           **options
        }
      )
    end

    def check_ssh_certificate_repo_access
      # if it's not a cert, don't do anything here
      return :ok unless ssh_ca

      # If the repo is in and owned by an organization linked to the SSH CA, do nothing here
      if FeatureFlag.vexi.enabled_or_raise?(:ssh_ca_repo_forks, user) # rubocop:disable GitHub/FeatureManagement/NoVexiEnabledOrRaiseUsage
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
      if FeatureFlag.vexi.enabled_or_raise?(:ssh_ca_emu_check, user) # rubocop:disable GitHub/FeatureManagement/NoVexiEnabledOrRaiseUsage
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
        return :bad_ssh_ca if !FeatureFlag.vexi.enabled_or_raise?(:ssh_ca_repo_forks, user) && repository.in_organization? && !ssh_ca.owned_by_repo_owner?(repository) # rubocop:disable GitHub/FeatureManagement/NoVexiEnabledOrRaiseUsage
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

      # To enable the Experiment on Proxima, we need to use the ProximaScientist class
      science_class = GitHub.multi_tenant_enterprise? && !Rails.env.test? ? ConditionalAccess::ProximaScientist : Scientist # rubocop:disable GitHub/DoNotBranchOnRailsEnv

      if GitHub.oauth_application_policies_enabled? && public_key&.created_by_unknown?
        GitHub.dogstats.increment("gitauth.maintainer_via_app", tags: ["type:pubkey_unknown_origin"])
        # The repository's OAuth application policy blocks access to some
        # apps, and we don't know who created the key that is being used to
        # access the repository (e.g., was it created by a blocked app?).

        is_restricted = if use_authzd_oap_and_saml?
          oap_status_code_authzd_cap(resource: repository.parent) == :oap_denied_key_unknown_origin
        elsif run_gitauth_oap_saml_cap_experiment?
          science_class.run "gitauth_oap_saml_cap_experiment_oap" do |e|
            e.use { repository.parent.policymaker.restricts_oauth_applications? }
            e.try { oap_status_code_authzd_cap(resource: repository.parent) == :oap_denied_key_unknown_origin }
            e.compare do |control, experiment|
              matched = oap_experiment_comparison(control, experiment)

              # if we're using the custom ProximaScientist class, we won't have
              # the Scientist UI tooling with all of the context about mismatches
              # so for now we'll just log as much as we can here
              # the log automatically has the request ID, which can help us diagnose further if needed
              # Exception handling is part of the custom ProximaScientist class
              if !matched && GitHub.multi_tenant_enterprise?
                GitHub.logger.info(
                  "Mismatch in authzd cap experiment - public key",
                  "code.function" => "check_fork_maintainer",
                  "authzd.cap.experiment_name" => "gitauth_oap_saml_cap_experiment_oap",
                  "authzd.cap.location" => "GitAuth",
                  "authzd.cap.policies" => "oap",
                  "authzd.cap.control" => "#{control}",
                  "authzd.cap.candidate" => "#{experiment}",
                  "authzd.cap.resource.id" => repository&.try(:id) || 0,
                  "authzd.cap.resource.type" => repository&.class&.name,
                )
              end
              matched
            end
          end
        else
          repository.parent.policymaker.restricts_oauth_applications?
        end

        return :oap_denied_key_unknown_origin if is_restricted
      end

      if GitHub.oauth_application_policies_enabled? && oauth_application
        is_denied = if use_authzd_oap_and_saml?
          oap_status_code_authzd_cap(resource: repository.parent) == :oap_denied_app
        elsif run_gitauth_oap_saml_cap_experiment?
          science_class.run "gitauth_oap_saml_cap_experiment_oap" do |e|
            e.use { OauthApplicationPolicy::Application.new(repository.parent, oauth_application).violated? }
            e.try { oap_status_code_authzd_cap(resource: repository.parent) == :oap_denied_app }
            e.compare do |control, experiment|
              matched = oap_experiment_comparison(control, experiment)
              # if we're using the custom ProximaScientist class, we won't have
              # the Scientist UI tooling with all of the context about mismatches
              # so for now we'll just log as much as we can here
              # the log automatically has the request ID, which can help us diagnose further if needed
              # Exception handling is part of the custom ProximaScientist class
              if !matched && GitHub.multi_tenant_enterprise?
                GitHub.logger.info(
                  "Mismatch in authzd cap experiment - oauth application",
                  "code.function" => "check_fork_maintainer",
                  "authzd.cap.experiment_name" => "gitauth_oap_saml_cap_experiment_oap",
                  "authzd.cap.location" => "GitAuth",
                  "authzd.cap.policies" => "oap",
                  "authzd.cap.control" => "#{control}",
                  "authzd.cap.candidate" => "#{experiment}",
                  "authzd.cap.resource.id" => repository&.parent&.try(:id) || 0,
                  "authzd.cap.resource.type" => repository&.parent&.class&.name,
                  "authzd.cap.oap.id" => oauth_application&.id,
                  "authzd.cap.oap.name" => oauth_application&.name || "unknown",
                )
              end
              matched
            end
          end
        else
          OauthApplicationPolicy::Application.new(repository.parent, oauth_application).violated?
        end

        return :oap_denied_app if is_denied
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
