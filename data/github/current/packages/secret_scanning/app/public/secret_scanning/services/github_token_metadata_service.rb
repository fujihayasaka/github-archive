# typed: true # rubocop:todo Sorbet/StrictSigil
# frozen_string_literal: true

module SecretScanning
  module Services
    class GitHubTokenMetadataService
      include SecretScanning::Constants
      include SecretScanning::Encryption::EncryptedSecretsHelper

      sig { params(token: GitHub::TokenScanning::Service::Token).returns(T.nilable(SecretScanning::Models::GitHubTokenMetadata)) }
      def get_github_token_metadata(token)
        case token.token_type
        when "GITHUB", "GITHUB_PERSONAL_ACCESS_TOKEN", "GITHUB_OAUTH_ACCESS_TOKEN", "GITHUB_USER_TO_SERVER_TOKEN"
          return get_oauth_access_metadata(token)
        when "GITHUB_REFRESH_TOKEN"
          return get_refresh_token_metadata(token)
        when "GITHUB_SERVER_TO_SERVER_TOKEN", "GITHUB_APP_TOKEN"
          return get_authentication_token_metadata(token)
        when "ARMORED_PEM_PRIVATE_KEY", "GITHUB_SSH_PRIVATE_KEY"
          return get_private_key_metadata(token)
        when "GITHUB_TOKEN_V2"
          return get_patv2_metadata(token)
        end
        nil
      end

      sig { params(token_type: String, access_id: Integer, org: Organization).returns(Symbol) }
      def get_org_access(token_type, access_id, org)
        case token_type
        when "GITHUB", "GITHUB_PERSONAL_ACCESS_TOKEN"
          return :NO_ACCESS if org.legacy_personal_access_tokens_restricted?
          access = OauthAccess.find(access_id)
          return :NO_ACCESS if access.nil?
          return get_patv1_org_access(access, org)
        when "GITHUB_OAUTH_ACCESS_TOKEN"
          access = OauthAccess.find(access_id)
          return :NO_ACCESS if access.nil?
          return get_oauth_org_access(access, org)
        when "GITHUB_USER_TO_SERVER_TOKEN", "GITHUB_REFRESH_TOKEN"
          access = OauthAccess.find(access_id)
          return :NO_ACCESS if access.nil?
          return get_user_to_server_org_access(access, org)
        when "GITHUB_SERVER_TO_SERVER_TOKEN", "GITHUB_APP_TOKEN"
          access = AuthenticationToken.find(access_id)
          return :NO_ACCESS if access.nil?
          return get_app_org_access(access, org)
        when "GITHUB_TOKEN_V2"
          return :NO_ACCESS if org.personal_access_tokens_restricted?
          access = UserProgrammaticAccess.find_by(id: access_id)
          return :NO_ACCESS if access.nil?
          return get_org_access_patv2(access, org)
        when "ARMORED_PEM_PRIVATE_KEY", "GITHUB_SSH_PRIVATE_KEY"
          public_key = PublicKey.find_by(id: access_id)
          return :NO_ACCESS if public_key.nil?
          return get_ssh_org_access(public_key, org)
        end
        :NO_ACCESS
      end

      sig { params(token: GitHub::TokenScanning::Service::Token, user: T.nilable(User)).returns(T::Array[String]) }
      def get_pat_recent_actions(token, user)
        return [] if user.nil?
        return [] unless token.is_classic_or_fine_grained_pat?

        set_raw_secret_from_encrypted_secret(token)
        raw_secret = token.raw_secret
        digest = OpenSSL::Digest::SHA256.new
        hashed_raw_secret = digest.digest(raw_secret)
        base64_hashed_raw_secret = Base64.strict_encode64(hashed_raw_secret)
        uri_escaped_b64_hashed_raw_secret = CGI.escape(base64_hashed_raw_secret)
        phrase = "hashed_token:\"#{uri_escaped_b64_hashed_raw_secret}\""

        if token.token_type == "GITHUB_TOKEN_V2"
          target = get_patv2_permissions_target(token)
          return [] if target.nil?
          query = get_driftwood_query(phrase, target, user)
        else
          target = token.repository.owner
          return [] if target.nil?
          query = get_driftwood_query(phrase, target, user)
        end

        results = query.execute
        return [] if results&.results&.nil?
        results.results
          .map { |r| r.action }
          # I added the filter below because personal_access_token.create has a key-value pair that contains the phrase
          # (hashed_token:<hashed_token_value>), but it's not an action taken by the token. The same KVP is added to the
          # audit log event upon token creation.
          .select { |a| a != "personal_access_token.create" }
      end

      sig { params(token: GitHub::TokenScanning::Service::Token, user: T.nilable(User)).returns(T::Array[SecretScanning::Models::Patv2Action]) }
      def get_patv2_recent_actions(token, user)
        return [] if user.nil?

        # this is done in get_patv2_permissions, but adding it here to make it explicit that we need a raw secret
        # in order to build the query to get a token's recent actions from the audit log
        set_raw_secret_from_encrypted_secret(token)

        # we should memoize get_patv2_permissions later
        permissions = get_patv2_permissions(token)

        raw_secret = token.raw_secret
        digest = OpenSSL::Digest::SHA256.new
        hashed_raw_secret = digest.digest(raw_secret)
        base64_hashed_raw_secret = Base64.strict_encode64(hashed_raw_secret)
        uri_escaped_b64_hashed_raw_secret = CGI.escape(base64_hashed_raw_secret)
        phrase = "hashed_token:\"#{uri_escaped_b64_hashed_raw_secret}\""

        actions = []
        permissions.each do |permission|
          if permission.target_type == :organization
            query = ::Audit::Driftwood::Query.new_org_business_query({
              current_user: user,
              phrase: phrase,
              org_id: permission.target_id
            })
            results = query.execute
            next if results&.results&.nil?
            results.results.each do |result|
              action = result.action
              target = result[:org]
              target_type = permission.target_type
              request_method = result.data[:request_method]
              patv2_action = SecretScanning::Models::Patv2Action.new(action, request_method, target, target_type)
              actions.append(patv2_action)
            end
          elsif permission.target_type == :user
            query = ::Audit::Driftwood::Query.new_org_business_query({
              current_user: user,
              phrase: phrase,
              user_id: permission.target_id
            })
            results = query.execute
            next if results&.results&.nil?
            results.results.each do |result|
              action = result.action
              target = result[:user]
              target_type = permission.target_type
              request_method = result.data[:request_method]
              patv2_action = SecretScanning::Models::Patv2Action.new(action, request_method, target, target_type)
              actions.append(patv2_action)
            end
          end
        end

        actions
      end

      sig { params(token: GitHub::TokenScanning::Service::Token).returns(T.nilable(SecretScanning::Models::Permissions::Classic)) }
      def get_patv1_permissions(token)
        patv1_types = %w(GITHUB GITHUB_PERSONAL_ACCESS_TOKEN).freeze
        return nil unless patv1_types.include?(token.token_type)
        set_raw_secret_from_encrypted_secret(token)
        hashed_token = Digest::SHA256.base64digest(token.raw_secret)

        access = OauthAccess.find_by(hashed_token: hashed_token)
        return nil if access.nil?

        all_scopes = []
        access.scopes.each do |scope|
          all_scopes.append(scope)
          get_child_scopes(scope).each { |s| all_scopes.append(s) }
        end

        scopes_with_parents = {}
        all_scopes.each do |scope|
          parent = get_scope_parent(scope)
          simplified_parent = parent&.split(":")&.last
          if scopes_with_parents.has_key?(simplified_parent)
            scopes_with_parents[simplified_parent].append(scope)
          else
            scopes_with_parents[simplified_parent] = [scope]
          end
        end

        SecretScanning::Models::Permissions::Classic.new(all_scopes: all_scopes, scopes_with_parents: scopes_with_parents)
      end

      # Rename this to get_patv2_permissions once the experiment code is removed
      sig { params(token: GitHub::TokenScanning::Service::Token).returns(T.nilable(SecretScanning::Models::Permissions::Fgp)) }
      def get_fgp_permissions(token)
        return nil if token.token_type != "GITHUB_TOKEN_V2"
        # get metadata, because we need the access id
        set_raw_secret_from_encrypted_secret(token)
        metadata = get_patv2_metadata(token)
        return nil if metadata.nil?

        access_id = metadata.access_id
        access = UserProgrammaticAccess.find(access_id)
        return nil if access.nil?

        has_org_grant = access.organization_programmatic_access_grant_ids.length > 0
        has_user_grant = access.user_programmatic_access_grant_ids.length > 0

        if has_org_grant
          org_grant_id = access.organization_programmatic_access_grant_ids.first
          org_grant = OrganizationProgrammaticAccessGrant.find(org_grant_id)
          return nil if org_grant.nil?
          permissions = org_grant.permissions
          return nil if permissions.nil?
          return SecretScanning::Models::Permissions::Fgp.new_from_permissions(permissions)
        end

        user_grant_id = access.user_programmatic_access_grant_ids.first
        user_grant = UserProgrammaticAccessGrant.find(user_grant_id)
        return nil if user_grant.nil?
        permissions = user_grant.permissions
        return nil if permissions.nil?
        SecretScanning::Models::Permissions::Fgp.new_from_permissions(permissions)
      end

      # Only used for our experiment, use get_fgp_permissions
      sig { params(token: GitHub::TokenScanning::Service::Token).returns(T::Array[SecretScanning::Models::Patv2Permissions]) }
      def get_patv2_permissions(token)
        if token.token_type != "GITHUB_TOKEN_V2"
          return []
        end

        # getting metadata requires that the raw secret is set on the token
        set_raw_secret_from_encrypted_secret(token)

        # get metadata, because we need the access id
        metadata = get_patv2_metadata(token)

        permissions = []
        if !metadata.nil?
          access_id = metadata.access_id
          access = UserProgrammaticAccess.find(access_id)
          org_programmatic_grant_ids = access.organization_programmatic_access_grant_ids
          org_programmatic_grant_ids.each do |grant_id|
            grant = OrganizationProgrammaticAccessGrant.find(grant_id)
            grant_permissions = grant.permissions
            next if grant_permissions.nil?
            org_perms = SecretScanning::Models::Patv2Permissions.new(grant.organization_id, :organization, grant_permissions)
            permissions.append(org_perms)
          end

          user_programmatic_grant_ids = access.user_programmatic_access_grant_ids
          user_programmatic_grant_ids.each do |grant_id|
            grant = UserProgrammaticAccessGrant.find(grant_id)
            grant_permissions = grant.permissions
            next if grant_permissions.nil?
            user_permissions = SecretScanning::Models::Patv2Permissions.new(grant.user_id, :user, grant_permissions)
            permissions.append(user_permissions)
          end
        end

        permissions
      end

      private

      sig { params(phrase: String, target: T.any(User, Organization), user: User).returns(T.any(Search::Queries::AuditLogQuery, ::Audit::Driftwood::Query)) }
      def get_driftwood_query(phrase, target, user)
        query = if target.organization?
          ::Audit::Driftwood::Query.new_org_business_query({
            current_user: user,
            phrase: phrase,
            org_id: target.id
          })
        else
          ::Audit::Driftwood::Query.new_user_query({
            current_user: user,
            phrase: phrase,
            user_id: target.id
          })
        end
      end

      sig { params(token: GitHub::TokenScanning::Service::Token).returns(T.nilable(T.any(User, Organization))) }
      def get_patv2_permissions_target(token)
        set_raw_secret_from_encrypted_secret(token)
        metadata = get_patv2_metadata(token)
        return nil if metadata.nil?

        access_id = metadata.access_id
        access = UserProgrammaticAccess.find(access_id)
        return nil if access.nil?

        has_org_grant = access.organization_programmatic_access_grant_ids.length > 0
        has_user_grant = access.user_programmatic_access_grant_ids.length > 0

        if has_org_grant
          org_grant_id = access.organization_programmatic_access_grant_ids.first
          org_grant = OrganizationProgrammaticAccessGrant.find(org_grant_id)
          return org_grant.target
        end

        user_grant_id = access.user_programmatic_access_grant_ids.first
        user_grant = UserProgrammaticAccessGrant.find(user_grant_id)
        user_grant.target
      end

      sig { params(scope: String).returns(T.nilable(String)) }
      def get_scope_parent(scope)
        access_control_scope = Api::AccessControl.scopes[scope]
        while !access_control_scope.parent.nil?
          access_control_scope = Api::AccessControl.scopes[access_control_scope.parent.name]
        end
        access_control_scope.name
      end

      sig { params(scope: String).returns(T::Array[String]) }
      def get_child_scopes(scope)
        ret = []

        children = Api::AccessControl.child_scopes(scope)
        while children.length > 0
          child = children.pop
          if !ret.include?(child)
            ret.append(child.name)
          end
          next_children = Api::AccessControl.child_scopes(child)
          next_children.each { |c| children.append(c) }
        end

        ret
      end

      sig { params(token: GitHub::TokenScanning::Service::Token).returns(T.nilable(SecretScanning::Models::GitHubTokenMetadata)) }
      def get_patv2_metadata(token)
        if token.raw_secret.nil?
          return
        end
        token_metadata = nil

        credential_manager = ::GitHub::Authnd.credential_manager_for("github/secret_scanning")

        verify_credentials_response = credential_manager.verify_credentials(
          [::Authnd::Proto::Credentials::access_token(token.raw_secret)],
        )

        verify_candidate = verify_credentials_response.responses.first
        access_id = verify_candidate.access_id
        access = UserProgrammaticAccess.find_by(id: access_id)
        if access.nil?
          return
        end
        created_at = Time.at(access.created_at)
        custom_expiry = verify_candidate.expires_at
        if custom_expiry.nil?
          expires_at = created_at + 30.days
        else
          expires_at = Time.at(custom_expiry.to_i)
        end

        last_accessed_at = get_last_accessed_at(access)
        owner_id = verify_candidate.actor_id
        owner_suspension_status = is_owner_suspended?(owner_id)
        name = access.name
        org = token.repository.organization
        link = if (org_grant = access.organization_programmatic_access_grants.find_by(target: org))
          link = UrlHelpers.settings_org_personal_access_token_path(org, org_grant.id)
        else
          link = UrlHelpers.settings_user_access_token_path(id: access.id)
        end
        token_metadata = SecretScanning::Models::GitHubTokenMetadata.new(created_at: created_at, expires_at: expires_at, last_accessed_at: last_accessed_at, org_access: nil, token_type: token.token_type, access_id: access_id, is_owner_suspended: owner_suspension_status, owner_id: owner_id, name: name, link: link)
        token_metadata
      end

      sig { params(token: GitHub::TokenScanning::Service::Token).returns(T.nilable(SecretScanning::Models::GitHubTokenMetadata)) }
      def get_oauth_access_metadata(token)
        if token.raw_secret.nil?
          return
        end
        token_type = token.token_type
        token_metadata = nil
        hashed_token = Digest::SHA256.base64digest(token.raw_secret)
        access = OauthAccess.find_by(hashed_token: hashed_token)
        token_org = token.repository.organization
        if access.nil?
          return
        end
        created_at = Time.at(access.created_at)
        expires_at = get_expiry_date(access)
        last_accessed_at = get_last_accessed_at(access)
        name = access.description
        owner_id = access.user_id
        owner_suspension_status = is_owner_suspended?(owner_id)
        link = get_token_link(token_type, token_number: access.id)
        token_metadata = SecretScanning::Models::GitHubTokenMetadata.new(created_at: created_at, expires_at: expires_at, last_accessed_at: last_accessed_at, org_access: nil, token_type: token_type, access_id: access.id, is_owner_suspended: owner_suspension_status, owner_id: owner_id, name: name, link: link)
        token_metadata
      end

      sig { params(token: GitHub::TokenScanning::Service::Token).returns(T.nilable(SecretScanning::Models::GitHubTokenMetadata)) }
      def get_private_key_metadata(token)
        if token.raw_secret.nil?
          return
        end

        token_metadata = nil
        begin
          fingerprint = SSHData::PrivateKey.parse(token.raw_secret).first.public_key.fingerprint
        rescue SSHData::Error => e
          Failbot.report(e, app: FAILBOT_APP_NAME)
          return token_metadata
        end

        # On Proxima, Public Keys are contextualized with the tenant shortcode
        # so we need to append the shortcode to fingerprints otherwise we won't find any matches
        if GitHub.multi_tenant_enterprise? && (current_tenant = GitHub::CurrentTenant.get)
          fingerprint += "_#{current_tenant.shortcode}"
        end

        public_key_match = PublicKey.
          includes(:user, :repository).
          where(fingerprint_sha256: fingerprint).first

        token_org = token.repository.organization
        unless public_key_match.nil?
          created_at = Time.at(public_key_match.created_at)
          expires_at = nil
          last_accessed_at = get_last_accessed_at(public_key_match)
          name = public_key_match.title
          owner_id = public_key_match.creator_id
          owner_suspension_status = is_owner_suspended?(owner_id)
          repository_id = public_key_match.repository_id
          link = get_token_link(token.token_type, deploy_key_repo: repository_id)
          token_metadata = SecretScanning::Models::GitHubTokenMetadata.new(created_at: created_at, expires_at: expires_at, last_accessed_at: last_accessed_at, org_access: nil, token_type: token.token_type, access_id: public_key_match.id, is_owner_suspended: owner_suspension_status, owner_id: owner_id, name: name, link: link)
        end
        token_metadata
      end

      sig { params(owner_id: T.nilable(Integer)).returns(T::Boolean) }
      def is_owner_suspended?(owner_id)
        return false unless owner_id
        owner = User.find_by(id: owner_id)
        owner.nil? ? false : owner.suspended?
      end

      sig { params(access: T.any(OauthAccess, PublicKey, UserProgrammaticAccess)).returns(T.nilable(Time)) }
      def get_last_accessed_at(access)
        if access.accessed_at?
          return Time.at(access.accessed_at)
        end
        nil
      end

      sig { params(access: T.untyped, org: Organization).returns(Symbol) }
      def get_user_to_server_org_access(access, org)
        installations = access.application.installations
        installations.each do |installation|
          if installation.target_id == org.id
            return :ORG_ACCESS
          end
        end
        :NO_ACCESS
      end

      sig { params(access: OauthAccess, org: Organization).returns(Symbol) }
      def get_oauth_org_access(access, org)
        if org.allows_oauth_application?(access.application)
          if access.scopes.empty?
            return :PUBLIC_ACCESS
          end
          return :ORG_ACCESS
        end
        :NO_ACCESS
      end

      sig { params(public_key: PublicKey, org: Organization).returns(Symbol) }
      def get_ssh_org_access(public_key, org)
        if public_key.repository_key?
          org.repositories.each do |repo|
            return :ORG_ACCESS if repo.id == public_key.repository_id
          end
          return :NO_ACCESS
        end
        if org.saml_sso_present?
          public_key.active_org_credential_authorizations.each do |credential_authorization|
            if credential_authorization.organization_id == org.id
              return :NO_ACCESS if credential_authorization.revoked?
              return :SSO_ACCESS
            end
          end
          return :NO_ACCESS
        end
        owner = public_key.owner
        org.repositories_associated_with(owner).each do |repo|
          if repo.organization_id == org.id
            return :ORG_ACCESS
          end
        end
        :NO_ACCESS
      end

      sig { params(access: UserProgrammaticAccess, org: Organization).returns(Symbol) }
      def get_org_access_patv2(access, org)
        access.organization_programmatic_access_grants.each do |org_access|
          if org_access.organization_id == org.id
            return :SSO_ACCESS if org.saml_sso_present?
            return :ORG_ACCESS
          end
        end
        :NO_ACCESS
      end

      sig { params(access: OauthAccess, org: Organization).returns(Symbol) }
      def get_patv1_org_access(access, org)
        if org.saml_sso_present?
          org_accesses = access.credential_authorizations.by_organization(organization: org)
          org_accesses.each do |org_access|
            if org_access.organization_id = org.id
              return :NO_ACCESS if org_access.revoked?
              return :SSO_ACCESS
            end
          end
          return :NO_ACCESS
        end
        owner = access.user_id
        actor = User.find(owner)
        actor.organizations.each do |user_org|
          if user_org.id == org.id
            return :ORG_ACCESS
          end
        end
        org.repositories_associated_with(actor).each do |repo|
          if repo.organization_id == org.id
            return :ORG_ACCESS
          end
        end
        :NO_ACCESS
      end

      sig { params(access: AuthenticationToken, org: Organization).returns(Symbol) }
      def get_app_org_access(access, org)
        if access.authenticatable.target.organization? && access.authenticatable.target_id == org.id
          return :ORG_ACCESS
        end
        :NO_ACCESS
      end

      sig { params(token_type: String, token_number: T.nilable(Integer), deploy_key_repo: T.nilable(Integer)).returns(T.nilable(String)) }
      def get_token_link(token_type, token_number: nil, deploy_key_repo: nil)
        case token_type
        when "GITHUB", "GITHUB_PERSONAL_ACCESS_TOKEN"
          UrlHelpers.settings_user_token_path(id: token_number)
        when "GITHUB_SSH_PRIVATE_KEY"
          if deploy_key_repo.nil?
            return "/settings/keys"
          end
          repo = Repository.find_by(id: deploy_key_repo)
          return nil if repo.nil? || repo.name_with_display_owner.nil?
          UrlHelpers.repository_keys_path(repo.owner, repo)
        end
      end

      sig { params(access: OauthAccess).returns(T.nilable(Time)) }
      def get_expiry_date(access)
        if access.expires_at_timestamp.nil?
          return nil
        end
        Time.at(access.expires_at_timestamp)
      end

      sig { params(token: GitHub::TokenScanning::Service::Token).returns(T.nilable(SecretScanning::Models::GitHubTokenMetadata)) }
      def get_refresh_token_metadata(token)
        token_metadata = nil
        hashed_token = Digest::SHA256.base64digest(token.raw_secret)
        refresh_access = RefreshToken.find_by(hashed_token: hashed_token)

        if refresh_access.nil?
          return
        end
        created_at = Time.at(refresh_access.created_at)
        expires_at = Time.at(refresh_access.expires_at.to_i)
        refreshable_id = refresh_access.refreshable_id
        oauth_access = OauthAccess.find_by(id: refreshable_id)

        if oauth_access.nil?
          return
        end
        last_accessed_at = get_last_accessed_at(oauth_access)
        owner_id = oauth_access.user_id
        owner_suspension_status = is_owner_suspended?(owner_id)
        token_metadata = SecretScanning::Models::GitHubTokenMetadata.new(created_at: created_at, expires_at: expires_at, last_accessed_at: last_accessed_at, org_access: nil, token_type: token.token_type, access_id: refreshable_id, is_owner_suspended: owner_suspension_status, owner_id: owner_id)
        token_metadata
      end

      sig { params(token: GitHub::TokenScanning::Service::Token).returns(T.nilable(SecretScanning::Models::GitHubTokenMetadata)) }
      def get_authentication_token_metadata(token)
        if token.raw_secret.nil?
          return
        end

        token_metadata = nil
        hashed_token = Digest::SHA256.base64digest(token.raw_secret)
        access = AuthenticationToken.find_by(hashed_value: hashed_token)
        if access.nil?
          return
        end
        created_at = Time.at(access.created_at)
        expires_at = Time.at(access.expires_at_timestamp.to_i)
        token_metadata = SecretScanning::Models::GitHubTokenMetadata.new(created_at: created_at, expires_at: expires_at, last_accessed_at: nil, token_type: token.token_type, access_id: access.id, org_access: nil)
        token_metadata
      end
    end
  end
end
