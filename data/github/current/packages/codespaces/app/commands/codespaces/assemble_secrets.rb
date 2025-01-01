# typed: true
# frozen_string_literal: true

require "aws-sdk-ecr"

module Codespaces
  class AssembleSecrets < Command
    CONTAINER_REGISTRY_SECRET_PATTERN = /(?:(.+)_)?CONTAINER_REGISTRY_(SERVER|USER|PASSWORD)/
    CONTAINER_REGISTRY_SERVER_SECRET_PATTERN = /(?:(.+)_)?CONTAINER_REGISTRY_SERVER/
    ECR_CONTAINER_REGISTRY_PATTERN = /.+\.dkr\.ecr\.(.+)\.amazonaws.com/ # <aws_account_id>.dkr.ecr.<region>.amazonaws.com

    attr_reader :user, :vscs_target

    def initialize(user:, github_token:, codespace_token:, repository:, user_secrets: [], vscs_target_url: "", vscs_target: :production)
      @user = user
      @github_token = github_token
      @codespace_token = codespace_token
      @user_secrets = user_secrets
      @repository = repository
      @vscs_target_url = vscs_target_url
      @vscs_target = vscs_target
    end

    def perform
      ensure_dockerhub_secret([
        *assemble_default_secret_hashes,
        *assemble_user_secret_hashes,
      ])
    end

    private

    def assemble_default_secret_hashes
      target_config = Codespaces::Vscs.config_for_target(@vscs_target)

      port_forwarding_domain = Vscs.dev_tunnels_domain_for_target(vscs_target)
      secrets = T.let([
        {
          "type": Codespaces::Secret::TYPE_ENV_VAR,
          "name": "GITHUB_SERVER_URL",
          "value": GitHub.url,
        },
        {
          "type": Codespaces::Secret::TYPE_ENV_VAR,
          "name": "GITHUB_API_URL",
          "value": GitHub.api_url,
        },
        {
          "type": Codespaces::Secret::TYPE_ENV_VAR,
          "name": "GITHUB_GRAPHQL_URL",
          "value": GitHub.graphql_api_url,
        },
        {
          "type": Codespaces::Secret::TYPE_ENV_VAR,
          "name": "GITHUB_REPOSITORY",
          "value": @repository&.name_with_display_owner || Codespaces::Secret::VSCS_EMPTY_SECRET_VALUE,
        },
        {
          "type": Codespaces::Secret::TYPE_ENV_VAR,
          "name": "INTERNAL_VSCS_TARGET_URL",
          "value": @vscs_target_url,
        },
        {
          "type": Codespaces::Secret::TYPE_ENV_VAR,
          "name": "GITHUB_CODESPACES_PORT_FORWARDING_DOMAIN",
          "value": port_forwarding_domain,
        },
      ], T::Array[Hash])

      if @codespace_token.present?
        secrets.push({
          "type": Codespaces::Secret::TYPE_ENV_VAR,
          "name": "GITHUB_CODESPACE_TOKEN",
          "value": @codespace_token,
        })
      end

      if @github_token.present?
        secrets.push({
          "type": Codespaces::Secret::TYPE_ENV_VAR,
          "name": "GITHUB_TOKEN",
          "value": @github_token,
        })

        secrets.push({
          "type": Codespaces::Secret::TYPE_CONTAINER_REGISTRY,
          "name": "docker.pkg.github.com",
          "value": @github_token,
        })

        ghcr_domain = GitHub.urls.registry_host_name(:containers)
        secrets.push(
          container_registry_secret_hash(server: ghcr_domain, username: @user&.display_login, password: @github_token)
        )
      end

      if @user
        secrets.push({
          "type": Codespaces::Secret::TYPE_ENV_VAR,
          "name": "GITHUB_USER",
          "value": @user.display_login,
        })
      end

      if gpg_enabled?
        secrets.push(
          {
            "type": Codespaces::Secret::TYPE_ENV_VAR,
            "name": "GIT_COMMITTER_NAME",
            "value": GitHub.web_committer_name,
          },
          {
            "type": Codespaces::Secret::TYPE_ENV_VAR,
            "name": "GIT_COMMITTER_EMAIL",
            "value": GitHub.web_committer_email,
          }
        )
      end

      secrets
    end

    def assemble_user_secret_hashes
      GitHub.dogstats.gauge("codespaces.secrets.count", @user_secrets.length)
      user_secret_hashes = []

      @user_secrets.each do |s|
        if CONTAINER_REGISTRY_SECRET_PATTERN.match(s.name)
          # Only process the server secrets here and skip the user/password ones.
          # User and password are processed inside the container_registry_secret_hash_for_prefix method.
          container_reg_match = CONTAINER_REGISTRY_SERVER_SECRET_PATTERN.match(s.name)
          if container_reg_match
            prefix = container_reg_match[1]
            container_reg_hash = container_registry_secret_hash_for_prefix(prefix)
            user_secret_hashes << container_reg_hash if container_reg_hash
          end
        else
          user_secret_hashes << s.to_decrypted_h.tap do |h|
            GitHub.dogstats.gauge("codespaces.secrets.key.length", h[:name].length)
            GitHub.dogstats.gauge("codespaces.secrets.value.length", h[:value].length)
          end
        end
      end

      user_secret_hashes
    end

    def container_registry_secret_hash_for_prefix(prefix)
      name_prefix = prefix.present? ? "#{prefix}_" : ""
      server_secret = @user_secrets.find { |s| s.name == "#{name_prefix}CONTAINER_REGISTRY_SERVER" }
      username_secret = @user_secrets.find { |s| s.name == "#{name_prefix}CONTAINER_REGISTRY_USER" }
      password_secret = @user_secrets.find { |s| s.name == "#{name_prefix}CONTAINER_REGISTRY_PASSWORD" }

      if server_secret && password_secret # username is optional
        server = server_secret.decrypt
        username = username_secret&.decrypt
        password = password_secret.decrypt
        # If the username is AWS and it's an ECR registry, we assume the token
        # is already exchanged, so we just pass it directly.
        if ecr?(server) && username != nil && username.upcase != "AWS"
          begin
            region = aws_region_from_server(server)
            credentials = Aws::Credentials.new(username, password)
            ecr_client = Aws::ECR::Client.new(region: region, credentials: credentials)
            resp = ecr_client.get_authorization_token
            auth_data = resp.authorization_data[0]
            basic_auth = Base64.decode64(auth_data.authorization_token)
            password = basic_auth.split(":")[1]
            username = "AWS"
          rescue Aws::ECR::Errors::ServiceError => e
            Failbot.report(e, "catalog_service" => "github/codespaces", "gh.user.id" => @user.id)
            GitHub.dogstats.count("codespaces.secrets.ecr.failure", 1)
            # continue attempting to create a container
          end
        end

        container_registry_secret_hash(
          server: server,
          username: username,
          password: password
        ).tap do |h|
          GitHub.dogstats.gauge("codespaces.secrets.key.length", h[:name].length)
          GitHub.dogstats.gauge("codespaces.secrets.value.length", h[:value].length)
        end
      end
    end

    def ecr?(server)
      ECR_CONTAINER_REGISTRY_PATTERN.match(server)
    end

    def aws_region_from_server(server)
      region = ECR_CONTAINER_REGISTRY_PATTERN.match(server)

      region[1] if region
    end

    def container_registry_secret_hash(server:, username:, password:)
      name = username.present? ? "#{username}@#{server}" : server
      {
        "type": Codespaces::Secret::TYPE_CONTAINER_REGISTRY,
        "name": name,
        "value": password.presence || Codespaces::Secret::VSCS_EMPTY_SECRET_VALUE,
      }
    end

    def ensure_dockerhub_secret(secrets)
      user_provided_dockerhub_login = secrets.any? { |s| s[:type] == Codespaces::Secret::TYPE_CONTAINER_REGISTRY && s[:name].ends_with?(GitHub.codespaces_dockerhub_registry[:url]) }

      if !user_provided_dockerhub_login && !GitHub.flipper[:codespaces_no_default_dockerhub_credentials].enabled?(user)
        dockerhub_credentials = container_registry_secret_hash(
          server: GitHub.codespaces_dockerhub_registry[:url],
          username: GitHub.codespaces_dockerhub_registry[:username],
          password: GitHub.codespaces_dockerhub_registry[:password],
        )
        secrets.concat([dockerhub_credentials])
      else
        secrets
      end
    end

    def gpg_enabled?
      return false unless @user
      return false if @user.gpg_authorization == Configurable::GpgAuthorization::DISABLED
      return true if @user.gpg_authorization == Configurable::GpgAuthorization::ALL_REPOSITORIES
      if @user.gpg_authorization == Configurable::GpgAuthorization::SELECTED_REPOSITORIES
        @user.trusted_repository_authorizations.find_by(repository: @repository)
      elsif @user.gpg_authorization == Configurable::GpgAuthorization::ENABLED
        return true if @user.codespaces_repository_authorization == Configurable::CodespacesRepositoryAuthorization::ALL_REPOSITORIES
        @user.trusted_repository_authorizations.find_by(repository: @repository)
      end
    end
  end
end
