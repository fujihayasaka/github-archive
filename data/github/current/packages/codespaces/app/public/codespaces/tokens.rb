# typed: true # rubocop:todo Sorbet/StrictSigil
# frozen_string_literal: true

module Codespaces
  class Tokens
    extend T::Sig

    GPG_AUTHORIZATION_SCOPE = "codespaces::gpgauthorization"
    WEB_EDITOR_SCOPE = %w[read:user repo user:email workflow codespace]
    CODEPATH_CODESPACES_MINT_GITHUB_TOKEN = "codespaces/mint_prebuild_github_token"

    class Error < StandardError; end

    class << self
      private

      def with_metrics(name:, &block)
        GitHub.tracer.in_span("codespaces##{name}", kind: :internal) do |span|
          GitHub.dogstats.distribution_time("codespaces.tokens.latency", tags: ["action:#{name}"]) do
            yield(span)
          end
        end
      end

      def build_entry_point(target, integration, entry_point)
        return entry_point unless entry_point.is_a?(Symbol)

        Permissions::Service::EntryPoint.build(
          entry_point,
          target: target,
          actor_owner: integration,
        )
      end
    end

    def self.grant_repository_access(user, codespace,
      dc: nil,
      entry_point: nil
    )
      with_metrics(name: "grant_repository_access") do |span|
        integration = ::Apps::Internal.integration(:codespaces_production)

        mint_method = "via pre-validated access"
        span.add_attributes("gh.codespaces.token_mint_method" => mint_method)
        GitHub.logger.info("codespaces_mint_github_token", "gh.integration.id" => integration.id, "gh.codespaces.token_mint_method" => mint_method)

        u2s_entry_point = build_entry_point(user, integration, entry_point)
        new_access = integration.grant(user, { entry_point: u2s_entry_point })

        ActiveRecord::Base.connected_to(role: :writing) do
          # There are two cases in which there might be an operative org:
          #  1. User-owned, org-billed codespaces (e.g., user forks an org-owned repository)
          #  2. Org-owned, user-billed codespaces (e.g., user creates a codespace from an org-owned repository when
          #     the org doesn't have Codespaces billing enabled)
          # In both cases we need to copy over the credential authorization.
          org = if codespace.billable_owner.organization?
            codespace.billable_owner
          else
            codespace.repository.organization
          end

          # Check if SAML would be enforced for this codespace owner and if so creates a credential authorization grant for them.
          # This should be safe to do because all mechanisms that allow token minting already go through appropriate SAML CAP filtering
          # either in the API or in the Rails controllers.
          if org && Organization::SamlEnforcementPolicy.new(organization: org, user:).enforced?
            if !Organization::CredentialAuthorization.by_organization_credential(organization: org, credential: new_access).active.exists?
              authorization = Organization::CredentialAuthorization.grant(organization: org, credential: new_access, actor: user)
              raise Codespaces::Tokens::Error, "Could not create credential authorization grant. Org: #{org.login}, user: #{user.login}" if authorization.nil? # rubocop:disable GitHub/DoNotAllowLogin
            end
          end

          devcontainer = T.let(dc, T.nilable(Codespaces::DevContainer))
          begin
            devcontainer ||= Codespaces::DevContainer.new(repository: codespace.repository, oid: codespace.oid, filepath: codespace.devcontainer_path, user: user)
          rescue Codespaces::DevContainer::ReadError => e
            # DevContainer can no longer be found on this codespace's OID likely due to a force push or other destructive action.
            # Ignore multi-repo access in this case and continue with token minting so the user doesn't lose access to their
            # codespace completely.
            GitHub.logger.error(
              "Unable to locate codespace's devcontainer at its path. history has been rewritten.",
              :exception => e,
              "gh.user.login" => user&.login, # rubocop:disable GitHub/DoNotAllowLogin
              "gh.codespaces.devcontainer_path" => codespace.devcontainer_path,
              "gh.catalog_service" => "github/codespaces",
            )
          end

          result = SiteScopedIntegrationInstallation::Creators::CodespaceWithOauthAccess.perform(
            codespace: codespace,
            oauth_access: new_access,
            entry_point: entry_point,
            devcontainer: devcontainer
          )

          if result.failed?
            GitHub.logger.warn(
              "gh.request_id" => GitHub.context[:request_id],
              "gh.scoped_token_result.error" => result.error,
              "gh.codespaces.token_mint_method" => mint_method,
              "gh.repository_id" => codespace.repository.id,
              "gh.installation.target.id" => codespace.repository.owner.id,
              "gh.codespaces.token_mint_new_access_grant_ids" => new_access.credential_authorizations.active.map(&:organization_id),
            )
            raise Codespaces::Tokens::Error, "Could not create repository scoped grant: #{result.error}"
          end

          [result.credential, result.installation]
        end
      end
    end

    def self.mint_github_token(user, codespace, entry_point: nil)
      with_metrics(name: "mint_github_token") do |_span|
        token, _ = grant_repository_access(user, codespace, entry_point: entry_point)
        token
      end
    end

    # Alongside the token, returns a Float value for when we expect (Unix seconds since epoch) that token to be fully
    # valid, accounting for replication lag in the primary/permissions clusters.
    sig { params(user: User, codespace: Codespace, entry_point: T.nilable(T.any(String, Symbol))).returns([String, Float]) }
    def self.mint_github_token_with_estimated_validity(user, codespace, entry_point: nil)
      with_metrics(name: "mint_github_token_with_estimated_validity") do |_span|
        token, installation = grant_repository_access(user, codespace, entry_point: entry_point)

        # The associated installation will have already been fetched for this OauthAccess instance
        # within the call to #grant_repository_access above.
        valid_after = TokenValidAfterManager.new(installation).valid_after

        [token, valid_after]
      end
    end

    def self.mint_web_editor_oauth_token(user:, session:, entry_point: nil)
      fail ArgumentError, "user required" unless user
      fail ArgumentError, "session required" unless session

      with_metrics(name: "mint_web_editor_oauth_token") do |_span|
        application = Apps::Internal.oauth_application(:lightweight_web_editor) \
          or fail "missing :lightweight_web_editor internal app, configuration error?"
        access = application.grant(user, user_session: session, scope: WEB_EDITOR_SCOPE, requested_scope: WEB_EDITOR_SCOPE, entry_point: entry_point)
        token = access.redeem
        token
      end
    end

    def self.mint_encrypted_github_token(user, codespace, session: nil, cap_filter: nil, entry_point: nil)
      with_metrics(name: "mint_encrypted_github_token") do |_span|
        github_token = Codespaces::Tokens.mint_github_token(user, codespace, entry_point: entry_point)
        return github_token if GitHub.enterprise? # encryption is not supposed by enterprise

        encrypt_github_token(github_token, user)
      end
    end

    def self.encrypt_github_token(token, user)
      return token if GitHub.enterprise? # encryption is not supported by enterprise
      # Following instructions found here: https://thehub.github.com/engineering/development-and-ops/secure-coding/secure-coding-general/encryption/symmetric-encryption/#encryption
      aes = OpenSSL::Cipher::AES128.new(:GCM)
      aes.encrypt # put the cipher instance in to encrypt mode

      encryption_config = Codespaces::EncryptionConfig.new(Codespaces::EncryptionConfig::TOKEN_ENCRYPTION)
      aes.key = encryption_config.symmetric_key

      nonce = OpenSSL::Random.random_bytes(aes.iv_len)
      aes.iv = nonce
      aes.auth_data = ""

      encrypted = aes.update(token) + aes.final
      tag = aes.auth_tag

      encrypted_token = nonce + encrypted + tag
      encoded_token = Base64.strict_encode64(encrypted_token)
      [encoded_token, encryption_config.version]
    end

    def self.decrypt_github_token(encoded_token, key_version: nil)
      return encoded_token if GitHub.enterprise? # encryption is not supported by enterprise
      # Following instructions found here: https://thehub.github.com/engineering/development-and-ops/secure-coding/secure-coding-general/encryption/symmetric-encryption/#decryption
      # Note: GCM stores an output authentication tag which is 16 bytes long
      aes = OpenSSL::Cipher::AES128.new(:GCM)
      auth_tag_size = 16
      encrypted_token = Base64.strict_decode64(encoded_token)
      nonce = encrypted_token.byteslice(0, aes.iv_len)
      ciphertext = encrypted_token.byteslice(aes.iv_len, encrypted_token.bytesize - auth_tag_size - aes.iv_len)
      tag = encrypted_token.byteslice(-auth_tag_size, auth_tag_size)

      aes.decrypt # put the cipher instance in to decrypt mode
      encryption_config = Codespaces::EncryptionConfig.new(Codespaces::EncryptionConfig::TOKEN_ENCRYPTION, key_version:)
      aes.key = encryption_config.symmetric_key

      aes.iv = nonce
      aes.auth_data = ""
      aes.auth_tag = tag

      decrypted = aes.update(ciphertext) + aes.final
    end

    def self.mint_codespace_token(scope:, user:, codespace:)
      GitHub::Authentication::SignedAuthToken.generate(
        user:    user,
        scope:   scope,
        expires: ::Apps::Internal::Codespaces::PRODUCTION[:properties][:oauth_access_expiry].from_now,
        data:    {
          id: codespace.id,
        }
      )
    end

    # Note that this is NOT a check on whether the codespaces *repository* is trusted, which
    # is checked later when we scope the installation's repository access.
    #
    # This determines whether the owner of a codespace, created for a trusted repository, is also
    # trusted for that access. We use billability as a proxy for permission for org-owned repos;
    # an individual user will always trust themselves.
    def self.request_elevated_read_access?(codespace)
      codespace.repository.owner_id == codespace.billable_owner_id
    end

    def self.mint_read_access_token(repository)
      return nil if repository.nil?
      with_metrics(name: "mint_read_access_token") do |_span|
        integration = ::Apps::Internal.integration(:codespaces_production)
        permissions = {
          "contents" => :read,
        }

        result = ActiveRecord::Base.connected_to(role: :writing) do
          SiteScopedIntegrationInstallation::Creator.perform(
            integration,
            repository.owner,
            repositories: [repository],
            permissions: permissions,
          )
        end
        raise Codespaces::Tokens::Error, "Could not create repository site scoped installation, reason: #{result.error}" if result.failed?
        _, token = AuthenticationToken.create_for(result.installation)
        token
      end
    end

    class PrebuildTokens < Tokens
      # mint_prebuild_github_token is used to mint a token for a prebuild using the repository
      # and the existing installation from the codespaces integration. This is used to grant
      # access to the prebuild repository.
      def self.mint_prebuild_github_token(repository, branch, entry_point: nil)
        with_metrics(name: "mint_prebuild_github_token") do |_span|
          integration = ::Apps::Internal.integration(:codespaces_production)

          GitHub.logger.info(
            "code.namespace" => "Codespaces::Tokens",
            "code.function" => "mint_prebuild_github_token",
            "gh.repo.id" => repository.id,
            "gh.codespaces.prebuild_token_mint_branch_present" => branch.present?,
          )

          result = SiteScopedIntegrationInstallation::Creators::PrebuildCodespace.perform(
            integration: integration,
            repository: repository,
            code_path: CODEPATH_CODESPACES_MINT_GITHUB_TOKEN,
            branch: branch,
            entry_point: entry_point
          )

          [result.credential, result.installation]
        end
      end
    end
  end
end
