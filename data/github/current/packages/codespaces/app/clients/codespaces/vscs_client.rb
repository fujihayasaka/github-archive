# typed: true
# frozen_string_literal: true

require "net/http"
require "uri"
require "json"

module Codespaces
  # Public: Interface to the VSCS backend.
  class VscsClient < Client

    class InvalidExportStateError < StandardError; end
    class InvalidUpdatingStateError < StandardError; end
    class InvalidSecretUpdatingStateError < StandardError; end
    class PayloadTooLargeError < StandardError; end
    class SecretDataTooLarge < StandardError; end
    class TierCapacityUnavailableError < StandardError; end
    class MissingHMACKeyError < StandardError; end
    class PlanNameMissingError < StandardError; end
    class TimeoutError < Client::TimeoutError; end
    class ConnectionFailed < Client::ConnectionFailed; end
    class BadResponseError < Client::BadResponseError; end
    class EncryptionKeyError < Client::EncryptionKeyError; end
    class VNetInjectionNotAvailableForRegionError < StandardError; end

    DOTFILES_REPOSITORY_NAME = "dotfiles"

    AUTO_SHUTDOWN_MINUTES = 30
    ENVIRONMENT_TYPE = "cloudEnvironment"

    ENVIRONMENT_NOT_SHUTDOWN_ERROR_CODE = 7
    ACTION_NOT_ALLOWED_IN_THIS_STATE_ERROR_CODE = 31
    INVALID_EXPORT_STATE_ERROR_CODE = 32
    PREBUILD_TEMPLATE_DELETION_DISALLOWED_ERROR_CODE = 36
    TIER_CAPACITY_UNAVAILABLE_ERROR_CODE = 37

    # There is a message size limit downstream, including some VSCS-side added content we can't control
    PAYLOAD_SIZE_LIMIT = 50_000

    # Cascade tokens
    CASCADE_TOKEN_EXPIRATION = 24.hours
    WRITE_SCOPE = "write:environments"
    PRIVATE_SCOPE = "connect:private-ports"
    ORG_SCOPE = "connect:org-ports"
    STORAGE_ACCOUNTS_AND_TOKENS_CACHE_KEY = "codespaces:storage_accounts_and_tokens"
    STORAGE_ACCOUNTS_AND_TOKENS_CACHE_KEY_V2 = "codespaces:storage_accounts_and_tokens_v2"
    SAS_TOKEN_PATH = "/api/v1/sas"
    BILLING_SAS_PATH = "/api/v1/billing"
    FETCH_CASCADE_TOKEN_TIMEOUTS = { open_timeout: 2, timeout: 4 }.freeze
    FETCH_CASCADE_TOKEN_RETRY_OPTIONS = {
      max: 5,
      interval: 0.05,
      backoff_factor: 2,
      exceptions: [Faraday::ConnectionFailed, Faraday::TimeoutError],
      methods: %i[get post],
    }

    HMAC_KEYS = {
      production: GitHub.api_internal_codespaces_vscs_production_hmac_key,
      latestprod: GitHub.api_internal_codespaces_vscs_production_hmac_key,
      ppe: GitHub.api_internal_codespaces_vscs_ppe_hmac_key,
      latestppe: GitHub.api_internal_codespaces_vscs_ppe_hmac_key,
      development: GitHub.api_internal_codespaces_vscs_development_hmac_key,
      latestdev: GitHub.api_internal_codespaces_vscs_development_hmac_key,
      local: GitHub.api_internal_codespaces_vscs_development_hmac_key
    }

    attr_reader :vscs_target, :plan_id, :plan, :user, :scope, :api_url, :for_unscoped_deletion_or_suspension, :oid, :branch, :location, :clean_up_vscs_id_enabled, :monolith_url_builder

    def self.for_codespace(codespace, plan: codespace.plan, user: codespace.owner, **kwargs)
      new(
        **T.unsafe({
          vscs_target: codespace.vscs_target,
          plan: plan,
          user: user,
          resource_provider: plan.resource_provider,
          api_url: VscsApiUrl.for_codespace(codespace),
          oid: codespace.oid,
          branch: codespace.branch,
          location: codespace.location,
          **kwargs
        })
      )
    end

    def self.for_prebuild(location:, oid: nil, branch: nil, vscs_target: Codespaces::Vscs.default_target, vscs_target_url: nil, plan: nil, **kwargs)
      plan = plan || Codespaces::Plan.for!(location: location, vscs_target: vscs_target)

      api_url = nil
      if vscs_target_url.present? && vscs_target == :local
        api_url = vscs_target_url
      else
        api_url = VscsApiUrl.new(location: location, vscs_target: vscs_target).url
      end

      new(
        **T.unsafe({
          vscs_target: vscs_target,
          plan: plan,
          user: nil,
          resource_provider: plan.resource_provider,
          api_url: api_url,
          for_prebuild: true,
          branch: branch,
          oid: oid,
          location: location,
          **kwargs
        })
      )
    end

    def self.for_unscoped_deletion_or_suspension(plan, vscs_target, **kwargs)
      if plan.vscs_target != vscs_target
        GitHub.logger.info(
          "codespaces.vscs_client.for_unscoped_deletion_or_suspension.mismatched_vscs_target",
          "codespaces.vscs_client.for_unscoped_deletion_or_suspension.plan.vscs_target" => plan.vscs_target,
          "codespaces.vscs_client.for_unscoped_deletion_or_suspension.vscs_target" => vscs_target,
        )
      end

      new(
        **T.unsafe({
          vscs_target: vscs_target,
          plan: plan,
          resource_provider: plan.resource_provider,
          api_url: VscsApiUrl.for_plan(plan),
          for_unscoped_deletion_or_suspension: true,
          location: plan.location,
          **kwargs
        })
      )
    end

    def self.fetch_storage_accounts_and_tokens(vscs_target: Codespaces::Vscs.default_target, bypass_cache: false)
      client = new(resource_provider: Codespaces::Plan::DEFAULT_RESOURCE_PROVIDER, vscs_target: vscs_target, for_storage_tokens: true)

      client.fetch_storage_accounts_and_tokens(bypass_cache:)
    end

    def self.for_cascade_fetching(resource_provider:, timeouts: FETCH_CASCADE_TOKEN_TIMEOUTS, retry_config: FETCH_CASCADE_TOKEN_RETRY_OPTIONS, plan:, vscs_target: Codespaces::Vscs.default_target, user:)
      new(plan: plan, vscs_target: vscs_target, resource_provider: resource_provider, timeouts: timeouts, retry_config: retry_config, user: user)
    end

    # Public: Constructor
    #
    # vscs_target                         - The Symbol VSCS target (e.g. :production, :ppe, etc) to direct API calls at.
    # plan                                - Codespaces::Plan object related to the request. Required unless this client will be used for storage only.
    # user                                - (Optional) The User to make client requests on behalf of. Required unless for_unscoped_deletion_or_suspension
    # timeouts                            - (Optional) The timeouts to be used for API calls. Defaults to the 15 secs.
    # for_unscoped_deletion_or_suspension - (Optional) A boolean specifying whether this vscs client will be able to
    #                                       delete or suspend any environment within a plan. Required unless user or for_prebuild.
    # for_prebuild                        - (Optional) A boolean specifying whether this vscs client will be used for
    #                                       prebuilds management. Required unless user or for_unscoped_deletion_or_suspension.
    #
    # Returns nothing.
    def initialize(
      vscs_target:,
      plan: nil,
      user: nil,
      resource_provider:,
      oid: nil,
      branch: nil,
      api_url: nil,
      for_unscoped_deletion_or_suspension: false,
      for_prebuild: false,
      location: nil,
      for_storage_tokens: false,
      monolith_url_builder: Codespaces.monolith_url_builder,
      **kwargs
    )
      raise ArgumentError if plan && !(user || for_unscoped_deletion_or_suspension || for_prebuild)
      if plan.nil?
        raise ArgumentError if !for_storage_tokens

        plan = Codespaces::Plan.for_current_tenant!(vscs_target: vscs_target)
      end

      @vscs_target = vscs_target
      @plan = plan
      @plan_id = vscs_plan_url_path(plan.name)

      @user = user
      @resource_provider = resource_provider
      @scope = scope
      @api_url = api_url.presence || VscsApiUrl.for_target(vscs_target)
      @for_unscoped_deletion_or_suspension = for_unscoped_deletion_or_suspension
      @oid = oid
      @branch = branch
      @location = location
      @monolith_url_builder = monolith_url_builder
      super **kwargs
    end

    def logger
      super do |l|
        l.sensitive_keys(:connection)
        l.sensitive_keys(:accessToken)
        l.log_context = stats_tagger.all_semconv_tags.merge("gh.user.id" => user&.id)
      end
    end

    sig do
      params(
        location: String,
        repo: Repository,
        sku_name: T.any(Symbol, String),
        name: String,
        moniker: String,
        billable_owner: User,
        create_type: T.nilable(String),
        github_token: String,
        codespace_token: String,
        environment_options: Hash,
        secrets: Array,
        request_cascade_token: T::Boolean,
        prebuild_allowed: T::Boolean,
      ).returns(T.nilable(::Codespaces::Environment))
    end
    def create_environment(location, repo, sku_name:, name:, moniker:, billable_owner:, create_type:, github_token:, codespace_token: "", environment_options: {}, secrets: [], request_cascade_token: false, prebuild_allowed: false)
      with_sensitive_log_keys :github_token, :codespace_token, :secrets do
        environment_options[:billableOwner] = {
          type: billable_owner.class.name,
          id: billable_owner.id,
          login: billable_owner.login, # rubocop:disable GitHub/DoNotAllowLogin FE expects login to be unique
        }

        if skip_requesting_access_token?
          request_cascade_token = false
        end

        body = build_environment_body_with_raw_secrets(
          environment_options: environment_options,
          moniker: moniker,
          name: name,
          billable_owner: billable_owner,
          repo: repo,
          sku_name: sku_name,
          github_token: github_token,
          codespace_token: codespace_token,
          secrets: secrets,
          # We are always using an unscoped token when requesting a cascade token in create request
          use_unscoped_management_token: request_cascade_token,
          prebuild_allowed: prebuild_allowed,
          create_type:,
          location:,
        )

        body[:runTimeConstraints] = {
          allowedPortPrivacySettings: Codespaces::PortPrivacyPolicy.get_allowed_port_privacy_settings(repository: repo, billable_owner: billable_owner)
        }

        if billable_owner.feature_enabled?(:codespaces_enforce_image_allow_list_in_agent)
          body[:runTimeConstraints].merge!({ imageAllowList: Codespaces::ImagePolicy.merged_allowlists(billable_owner:, repository: repo) })
        end


        if billable_owner.in_codespaces_salus_beta? && billable_owner.feature_enabled?(:codespaces_host_setup_policy)
          body[:runTimeConstraints].merge!({ hostSetupConfig: get_host_setup(repo, billable_owner) })
        end

        body[:netmonCorrelationData] = build_netmon_correlation_data(
          repo: repo,
          billable_owner: billable_owner,
          user: user,
        )

        add_user_tier_to_body(body: body, user: user)

        body_json = body.to_json
        GitHub.dogstats.gauge("codespaces.create_environment.payload_size", body_json.size)
        GitHub.dogstats.gauge("codespaces.devcontainerjson.size", body[:devcontainerJson].size) if body[:devcontainerJson]
        if body_json.size > PAYLOAD_SIZE_LIMIT
          if body[:devcontainerJson] && (body_json.size - body[:devcontainerJson].size) < PAYLOAD_SIZE_LIMIT
            GitHub.dogstats.increment("codespaces.devcontainerjson.overflow")
            body[:devcontainerJson] = nil
            body_json = body.to_json
          elsif body[:secrets] && (body_json.size - body[:secrets].to_json.size) < PAYLOAD_SIZE_LIMIT
            raise SecretDataTooLarge, secret_data_exceeds_limit_error_message(body_json.size)
          else
            raise PayloadTooLargeError, "request payload to create environment exceeds our limit of #{PAYLOAD_SIZE_LIMIT / 1000} kilobytes"
          end
        end

        url = Addressable::URI.new(path: "api/v1/environments", query_values: { access: false }.compact).to_s
        env = vscs_api \
          :post,
          url,
          body: body_json,
          caller: "create_environment",
          tags: ["location:#{location}"]

        return unless env
        ::Codespaces::Environment.from_json(env)
      end
    rescue BadResponseError => e
      if e.error_codes.include? TIER_CAPACITY_UNAVAILABLE_ERROR_CODE
        raise TierCapacityUnavailableError, tier_capacity_unavailable_error_message
      else
        raise
      end
    end

    # Returns configuration for a "host setup script" which runs on the host machine before a container is created,
    # and before the codespace owner has access to the codespace.
    def get_host_setup(repo, billable_owner)
      host_setup_config = Codespaces::HostSetupPolicy.get_host_setup_config(repository: repo, billable_owner: billable_owner)
      return nil unless host_setup_config.present?

      repository = Repository.nwo(host_setup_config["repo"])
      return nil unless repository.present?

      {
        cloneUrl: repository.clone_url,
        branch: host_setup_config["branch"],
        path: host_setup_config["path"],
        token: Codespaces::Tokens.mint_read_access_token(repository)
      }
    end

    def update_recent_folders(id, recent_folders)
      raise ArgumentError, "recent_folders cannot be blank" if recent_folders.nil?
      raise ArgumentError, "recent_folders must be an array" if !recent_folders.is_a?(Array)
      raise ArgumentError, "recent_folders must be an array of non-empty strings" if !recent_folders.all? { |f| f.is_a?(String) && !f.empty? }

      body = {
        recentFolderPaths: recent_folders
      }
      vscs_api(:patch, "api/v1/environments/#{id}/folder", body: body.to_json, caller: "update_recent_folders").tap do |env|
        Codespaces::CacheEnvironmentData.call(env)
      end
    end

    def archive_environment(id)
      raise ArgumentError, "empty environment id" if id.blank?

      vscs_api(:post, "api/v1/environments/#{id}/archive", body: nil, caller: "archive_environment").tap do |env|
        Codespaces::CacheEnvironmentData.call(env)
      end
    rescue BadResponseError => e
      raise e unless e.status == 404
    end

    def get_archive_environment_status(id)
      raise ArgumentError, "empty environment id" if id.blank?

      vscs_api(:get, "api/v1/environments/#{id}/archive", body: nil, caller: "get_archive_environment_status").tap do |env|
        Codespaces::CacheEnvironmentData.call(env)
      end
    rescue BadResponseError => e
      raise e unless e.status == 404
    end

    def secret_data_exceeds_limit_error_message(payload_size)
      "secret data caused the payload for creating a codespace to exceed the"\
      " maximum size of #{PAYLOAD_SIZE_LIMIT / 1000} kilobytes; attempted"\
      " payload size: #{payload_size / 1000} kilobytes"
    end

    def tier_capacity_unavailable_error_message
      "The codespace service is temporarily unavailable, please try again later."
    end

    def update_environment(id, body:)
      raise ArgumentError, "body cannot be blank" if body.blank?

      vscs_api(:patch, "api/v1/environments/#{EscapeUtils.escape_uri_component(id)}", body: body.to_json, caller: "update_environment")
    rescue BadResponseError => e
      if e.error_codes.include? ENVIRONMENT_NOT_SHUTDOWN_ERROR_CODE
        raise InvalidUpdatingStateError
      else
        raise
      end
    end

    # Sends notification to the user in VS Code clients while using the codespace
    # id           - string; the environment id, which is stored in codespace.guid
    # message      - string; the message to be displayed to the user
    # display_mode - string; one of "information", "warning", "error"
    # modal        - boolean; whether the message should be displayed in a modal or toast
    def notify_environment(id:, message:, display_mode:, modal:)
      body = {
        message: message,
        displayMode: display_mode,
        modal: modal
      }

      body_json = body.to_json

      url = Addressable::URI.new(path: "api/v1/environments/#{EscapeUtils.escape_uri_component(id)}/notify").to_s
      vscs_api(
        :post,
        url,
        body: body_json,
        caller: "notify_environment",
        tags: ["location:#{location}"],
      )
    end

    def export_environment(id, branch_name:, repository_name:, token:, new_repository_origin: nil, failover_details: nil)
      body = {
        type: "GitPush",
        branchName: branch_name,
        repositoryName: repository_name,
        secrets: [
          {
            type: Codespaces::Secret::TYPE_ENV_VAR,
            name: "GIT_PAT",
            value: token
          }
        ]
      }
      if new_repository_origin.present?
        body[:newRepositoryOrigin] = new_repository_origin
      end
      if failover_details.present? && GitHub.flipper[:codespaces_failover_exports].enabled?(user)
        body[:failoverDetails] = failover_details
      end

      with_sensitive_log_keys :secrets do
        vscs_api(:post, "api/v1/environments/#{EscapeUtils.escape_uri_component(id)}/export", body: body.to_json, caller: "export_environment")
      end

    rescue BadResponseError => e
      if e.error_codes.include? INVALID_EXPORT_STATE_ERROR_CODE
        raise InvalidExportStateError
      else
        raise
      end
    end

    def delete_environment!(id)
      vscs_api(:delete, "api/v1/environments/#{EscapeUtils.escape_uri_component(id)}", body: {}.to_json, caller: "delete_environment!")
    end

    def delete_environment(codespace_guid)
      delete_environment!(codespace_guid)
    rescue BadResponseError => e
      raise e unless e.status == 404
    end

    def hard_delete_environment!(codespace_guid)
      vscs_api(:delete, "api/v1/environments/#{EscapeUtils.escape_uri_component(codespace_guid)}?hard_delete=1", body: {}.to_json, caller: "hard_delete_environment!")
    end

    def hard_delete_environment(codespace_guid)
      hard_delete_environment!(codespace_guid)
    rescue BadResponseError => e
      raise e unless e.status == 404
    end

    def restore_environment(id)
      body = {}
      body[:identity] = {
        id: "#{user.id}",
        username: "#{user.login}", # rubocop:disable GitHub/DoNotAllowLogin FE expects login to be unique
        displayName: "#{user.name}",
      }

      url = Addressable::URI.new(path: "api/v1/environments/#{EscapeUtils.escape_uri_component(id)}/restore", query_values: { access: false }.compact).to_s
      env = vscs_api \
        :patch,
        url,
        body: body.to_json,
        caller: "restore_environment"

      return unless env
      ::Codespaces::Environment.from_json(env)
    rescue BadResponseError => e
      raise e unless e.status == 404
    end

    def list_environments(name: nil)
      url = Addressable::URI.new(path: "api/v1/environments", query_values: { name: name }.compact).to_s
      vscs_api(:get, url, caller: "list_environments").map do |env|
        Codespaces::CacheEnvironmentDataJob.perform_later(env)
        ::Codespaces::Environment.from_json(env)
      end
    end

    def fetch_prebuild_template(id)
      raise ArgumentError, "empty environment id" if id.blank?

      vscs_api(:get, "api/v2/prebuilds/template/#{EscapeUtils.escape_uri_component(id)}", caller: "fetch_prebuild_template")
    end

    def fetch_prebuild_available_skus!(repo:, branch_name:, prebuild_hash:, devcontainer_path:, codespace_owner:, fast_path_enabled: false)
      url = "/api/v2/prebuilds/templates/skus/repo/#{EscapeUtils.escape_uri_component(repo.id.to_s)}/" +
            "branch/#{EscapeUtils.escape_uri_component(branch_name)}/" +
            "hash/#{EscapeUtils.escape_uri_component(prebuild_hash)}/" +
            "location/#{EscapeUtils.escape_uri_component(location)}/" +
            "devcontainerpath/#{devcontainer_path}"

      storage_v2_enabled = Codespaces::Vscs.use_storage_v2?(repo: repo, current_user: codespace_owner, sku_name: nil, billable_owner: nil)
      query_parameters = []

      if fast_path_enabled
        query_parameters.push("fastPathEnabled=true")
      end

      if storage_v2_enabled
        query_parameters.push("storageType=V2")
      end

      unless query_parameters.empty?
        url += "?#{query_parameters.join('&')}"
      end

      vscs_api(:get, url, caller: "fetch_prebuild_available_skus!")
    end

    def fetch_environment!(id, body: {}, include_deleted: false)
      raise ArgumentError, "empty environment id" if id.blank?

      path = "api/v1/environments/#{EscapeUtils.escape_uri_component(id)}"
      path += "?deleted=true" if include_deleted

      vscs_api(:get, path, body: body, caller: "fetch_environment!").tap do |env|
        Codespaces::CacheEnvironmentData.call(env)
      end
    end

    def fetch_environment(codespace_guid)
      fetch_environment!(codespace_guid)
    rescue BadResponseError => e
      raise e unless e.status == 404
    end

    sig do
      params(
        id: String,
        billable_owner: User,
        github_token: String,
        codespace_token: String,
        sku_name: T.nilable(T.any(Symbol, String)),
        secrets: Array,
        request_cascade_token: T::Boolean,
        repository: T.nilable(Repository),
        auto_shutdown_delay_minutes: T.nilable(Integer),
        failover_details: T.nilable(Hash),
        uses_storage_v2: T::Boolean,
      ).returns(Array)
    end
    def start_environment(id, billable_owner:, github_token:, codespace_token: "", sku_name: nil, secrets: [], request_cascade_token: false, repository: nil, auto_shutdown_delay_minutes: nil, failover_details: nil, uses_storage_v2: false)
      raise ArgumentError, "empty environment id" if id.blank?

      if skip_requesting_access_token?
        request_cascade_token = false
      end

      body = {
        skuName: sku_name,
        secrets: Codespaces::AssembleSecrets.call(
          user: user,
          github_token: github_token,
          codespace_token: codespace_token,
          user_secrets: secrets,
          repository: repository,
          vscs_target_url: api_url,
          vscs_target:,
        ),
        testAccount: GitHub.flipper[:codespaces_automated_testing].enabled?(user),
        runTimeConstraints: {
          allowedPortPrivacySettings: Codespaces::PortPrivacyPolicy.get_allowed_port_privacy_settings(repository: repository, billable_owner: billable_owner)
        },
        netmonCorrelationData: build_netmon_correlation_data(
          repo: repository,
          billable_owner: billable_owner,
          user: user,
        ),
        failoverDetails: failover_details,
        preferredComputeImageChannel: get_compute_image_channel
      }

      body[:autoShutdownDelayMinutes] = auto_shutdown_delay_minutes if auto_shutdown_delay_minutes

      if billable_owner.feature_enabled?(:codespaces_enforce_image_allow_list_in_agent)
        body[:runTimeConstraints].merge!({ imageAllowList: Codespaces::ImagePolicy.merged_allowlists(billable_owner:, repository:) })
      end

      if billable_owner.in_codespaces_salus_beta? && billable_owner.feature_enabled?(:codespaces_host_setup_policy)
        body[:runTimeConstraints].merge!({ hostSetupConfig: get_host_setup(repository, billable_owner) })
      end

      url = Addressable::URI.new(path: "api/v1/environments/#{EscapeUtils.escape_uri_component(id)}/start", query_values: { access: false }.compact).to_s

      if GitHub.flipper[:codespaces_enable_analytics_id].enabled?(user)
        body[:gitHubAnalyticsId] = user.analytics_tracking_id
      else
        body[:gitHubAnalyticsId] = nil
      end

      if user.present?
        body[:identity] = {
          id: "#{user.id}",
          username: "#{user.login}", # rubocop:disable GitHub/DoNotAllowLogin FE expects login to be unique
          displayName: "#{user.name}",
        }
      end

      features = {}

      # should be based on value from create environment
      features[:useStorageV2] = uses_storage_v2
      add_features_to_body(body, billable_owner, features, repo: repository)

      add_user_tier_to_body(body: body, user: user)

      add_vnet_injected_subnet_id_to_body(body: body, repo: repository, user:, billable_owner:, location:)

      with_sensitive_log_keys :secrets do
        result = T.let(nil, T.untyped)
        vscs_api(:post, url, body: body.to_json, caller: "start_environment") do |response|
          result = response
        end
        [result, nil]
      end
    rescue BadResponseError => e
      if e.error_codes.include? TIER_CAPACITY_UNAVAILABLE_ERROR_CODE
        raise TierCapacityUnavailableError, tier_capacity_unavailable_error_message
      else
        raise
      end
    end

    sig do
      params(
        id: String,
        billable_owner: T.nilable(User),
        repository: T.nilable(Repository),
      ).returns(T.untyped)
    end
    def shutdown_environment(id, billable_owner:, repository: nil)
      raise ArgumentError, "empty environment id" if id.blank?

      body = {
        runTimeConstraints: {
          allowedPortPrivacySettings: Codespaces::PortPrivacyPolicy.get_allowed_port_privacy_settings(repository: repository, billable_owner: billable_owner)
        },
      }

      if billable_owner&.feature_enabled?(:codespaces_enforce_image_allow_list_in_agent)
        body[:runTimeConstraints].merge!({ imageAllowList: Codespaces::ImagePolicy.merged_allowlists(billable_owner:, repository:) })
      end

      vscs_api(:post, "api/v1/environments/#{EscapeUtils.escape_uri_component(id)}/shutdown", body: body.to_json, caller: "shutdown_environment")
    end

    def create_prebuild_instance(pool_code:, github_token:, location:, repository:, secrets: [], environment_options: {})
      body = {
        environment_options: environment_options,
        secrets: Codespaces::AssembleSecrets.call(
          user: user,
          github_token: github_token,
          codespace_token: nil,
          user_secrets: secrets,
          repository: repository,
          vscs_target_url: api_url,
          vscs_target:,
        ),
      }

      body_json = body.to_json

      with_sensitive_log_keys :secrets do
        url = Addressable::URI.new(path: "api/v2/prebuilds/pools/#{EscapeUtils.escape_uri_component(pool_code)}/instances").to_s
        vscs_api(
          :put,
          url,
          body: body_json,
          caller: "create_prebuild_instance",
          tags: ["location:#{location}"],
        )
      end
    end

    def create_prebuild_template(location:, environment_options: {}, name:, repo:, prebuild_hash:, moniker:, workflow_run_id: nil, configuration_id: nil)
      body = build_template_environment_body(
        environment_options: environment_options,
        name: name,
        repo: repo,
        prebuild_hash: prebuild_hash,
        moniker: moniker,
        workflow_run_id: workflow_run_id,
        configuration_id: configuration_id,
        storage_type: environment_options["storage_type"],
        create_type: nil,
      )

      body_json = body.to_json

      url = Addressable::URI.new(path: "api/v2/prebuilds/templates").to_s

      vscs_api(
        :post,
        url,
        body: body_json,
        caller: "create_prebuild_template",
        tags: ["location:#{location}"],
      )
    rescue BadResponseError => e
      raise
    end

    def update_prebuild_template_status(location:, template_guid:, is_success:)
      body = {
        isSuccess: is_success,
      }

      body_json = body.to_json

      url = Addressable::URI.new(path: "api/v2/prebuilds/templates/#{EscapeUtils.escape_uri_component(template_guid)}/updatestatus").to_s

      vscs_api(
        :post,
        url,
        body: body_json,
        caller: "update_prebuild_template_status",
        tags: ["location:#{location}"],
      )
    rescue BadResponseError => e
      raise
    end

    def delete_prebuild_templates!(location:, repository_id:, branch:, configuration_id:, devcontainer_path: nil)
      body = {
        repoId: repository_id,
        branchName: branch,
        devContainerPath: devcontainer_path,
      }

      if configuration_id.present?
        body[:configurationId] = configuration_id
      end

      body_json = body.to_json

      url = Addressable::URI.new(path: "api/v2/prebuilds/delete").to_s

      vscs_api(
        :post,
        url,
        body: body_json,
        caller: "delete_prebuild_templates!",
        tags: ["location:#{location}"],
      )
    rescue BadResponseError => e
      raise e unless e.status == 404
    end

    def update_prebuild_template_versions(location:, repository:, branch:, maximum_template_versions:, devcontainer_path: nil, vscs_target: Codespaces::Vscs.default_target)
      body = {
        repoId: repository.id,
        branchName: branch,
        maxPrebuildTemplateVersions: maximum_template_versions,
        devContainerPath: devcontainer_path,
      }

      body_json = body.to_json

      url = Addressable::URI.new(path: "api/v2/prebuilds/templates/updatemaxversions").to_s

      vscs_api(
        :post,
        url,
        body: body_json,
        caller: "update_prebuild_template_versions",
        tags: ["location:#{location}", "vscs_target:#{vscs_target}"],
      )
    end

    def fetch_agent_download_info
      url = Addressable::URI.new(path: "api/v1/agents/vsoagentlinux").to_s
      vscs_api(
        :get,
        url,
        caller: "fetch_agent_download_info",
      )
    end

    def send_agent_telemetry(telemetry_json)
      url = Addressable::URI.new(path: "api/v1/agenttelemetry/standalone").to_s
      vscs_api(
        :post,
        url,
        body: telemetry_json,
        caller: "send_agent_telemetry"
      )
    end

    def update_user_secrets(codespace, secrets: [])
      with_sensitive_log_keys :secrets do
        secrets_payload = {
          secrets: Codespaces::AssembleSecrets.call(
            user: user,
            github_token: nil,
            codespace_token: nil,
            user_secrets: secrets,
            repository: codespace.repository,
            vscs_target_url: api_url,
            vscs_target:,
          )
        }.to_json
        url = Addressable::URI.new(path: "api/v1/environments/#{codespace.guid}/secrets").to_s
        vscs_api(
          :put,
          url,
          body: secrets_payload,
          caller: "update_user_secrets",
        )
      end
    rescue BadResponseError => e
      if e.error_codes.include? ACTION_NOT_ALLOWED_IN_THIS_STATE_ERROR_CODE
        raise InvalidSecretUpdatingStateError
      else
        raise
      end
    end

    # Public: Fetches a cascade token.
    #
    # vscs_target - The Symbol VSCS target to generate the token for. E.g. :production, :ppe, etc.
    # user        - The User whose identity will be tied to the token.
    # cache       - Specifies whether or not the token should be cached
    #               locally in KV (optional, default: true).
    # expires_in  - The time in seconds before the cascade token should expire
    #               and no longer be valid for requests against VSO (optional, default: 24 hours).
    # environment_id - The environment that the cascade token should be scoped to (optional, default: nil)
    # force_refresh  - Forces a fresh token to be fetched if `true`. `false` values will use cached tokens, if any
    # cache_with_expiration - Caches the token together with the expiration date we set.
    # for_unscoped_management - Mints a token without a user identity. To use this token you MUST include user identity in the vscs_api request.
    #
    # Returns a token String or String of json token data.
    def fetch_cascade_token(
      user:,
      cache: true,
      expires_in: CASCADE_TOKEN_EXPIRATION,
      environment_id: nil,
      force_refresh: false,
      for_unscoped_deletion_or_suspension: false,
      cache_with_expiration: false,
      for_unscoped_management: false,
      scope: nil,
      ports: []
    )

      fetch = if for_unscoped_deletion_or_suspension
        -> { fetch_cascade_token_for_delete_or_suspend! }
      elsif for_unscoped_management
        -> { fetch_management_cascade_token! \
          expires_in: expires_in
        }
      else
        -> {
          fetch_cascade_token! \
            user: user,
            expires_in: expires_in,
            environment_id: environment_id,
            cache_with_expiration: cache_with_expiration,
            scope: scope,
            port_numbers: ports
        }
      end

      if for_unscoped_deletion_or_suspension || !cache
        fetch.call
      else
        type, key_segments, encrypted = case
        when for_unscoped_management
          ["unscoped_management_cascade", [plan_id], true]
        when cache_with_expiration
          ["cascade_with_expiration", [plan_id, user.id], false]
        else
          ["cascade", [plan_id, user.id], false]
        end

        if environment_id
          key_segments << environment_id
        end

        if scope
          key_segments << scope
        end

        if ports&.any?
          key_segments.concat(ports)
        end

        key_segments << "direct_token_minting_v1"

        T.unsafe(self).cache_token(*key_segments, type: type, force: force_refresh, encrypted: encrypted) do
          [fetch.call, expires_in]
        end
      end
    end

    def fetch_storage_accounts_and_tokens(bypass_cache: false)
      # let's see if the account token map is already cached
      if !bypass_cache
        cache_key = STORAGE_ACCOUNTS_AND_TOKENS_CACHE_KEY_V2

        # if this isn't production, we append the environment id to the cache key
        cache_key += ":#{vscs_target}" unless vscs_target == :production

        cached_response = ActiveRecord::Base.connected_to(role: :reading) do
          Codespaces::Kv.store.get(cache_key).value { nil }
        end
        return GitHub::JSON.parse(cached_response) if cached_response
      end

      parsed_response = vscs_api(:get, BILLING_SAS_PATH, caller: "fetch_storage_accounts_and_tokens", body: {})

      # SAS tokens we receive from VSCS are good for 120 minutes. cache for 90.
      ActiveRecord::Base.connected_to(role: :writing) do
        Codespaces::Kv.store.set(T.must(cache_key), parsed_response.to_json, expires: 90.minutes.from_now) unless bypass_cache
      end

      parsed_response
    rescue Yajl::ParseError
      raise BadResponseError, request_err_message("Bad response", :post, "invalid JSON")
    rescue Faraday::TimeoutError
      raise TimeoutError, request_err_message("Timeout exceeded", :post)
    rescue Faraday::ConnectionFailed => e
      raise ConnectionFailed, request_err_message("Connection failed: #{e.message}", :post)
    end

    def fetch_tunnel_access_token_and_visibility(codespace_id:, port:)
      url = Addressable::URI.new(path: "api/v1/tunnel/#{codespace_id}/portInfo", query_values: { portNumber: port }).to_s
      response = vscs_api(
          :get,
          url,
          caller: "fetch_tunnel_access_token",
        )
      [response["tunnelToken"], response["portVisibility"]&.downcase]
    end

    private

    def vscs_plan_url_path(plan_name)
      raise PlanNameMissingError unless plan_name
      "/plans/#{plan_name}"
    end

    def fetch_cascade_token!(
      user:,
      expires_in:,
      environment_id: nil,
      cache_with_expiration: false,
      scope: nil,
      port_numbers: []
    )
      expiration = expires_in.from_now.to_i

      with_sensitive_log_data user_name: user.login, display_name: user.name do  # rubocop:disable GitHub/DoNotAllowLogin FE expects login to be unique
        post_body = {
          "identity": {
            "id": "#{user.id}",
            "username": "#{user.login}", # rubocop:disable GitHub/DoNotAllowLogin FE expects login to be unique
            "displayName": "#{user.name}",
          },
          "scope": scope.nil? ? WRITE_SCOPE : scope,
          "expiration": expiration
        }

        post_body["environmentIds"] = Array(environment_id) unless environment_id.blank?

        parsed_response = vscs_api(:post, "api/v1/tokens#{plan_id}/writeDelegates", caller: "fetch_cascade_token", body: post_body.to_json)

        if token = parsed_response["accessToken"]
          if cache_with_expiration
            { token:, expiration: }.to_json
          else
            token
          end
        else
          nil
        end
      end
    end

    # The expiration for this is hardcoded to 24h on the VSCS side.
    # This endpoint currently does not accept an `expiration` because of a bug.
    # See: https://github.com/github/codespaces/issues/2520#issuecomment-802112576
    def fetch_cascade_token_for_delete_or_suspend!
      parsed_response = vscs_api(:post, "api/v1/tokens#{plan_id}/deleteAllCodespaces", caller: "fetch_cascade_token_for_delete_or_suspend", body: {}.to_json)

      parsed_response["accessToken"]
    end

    # Fetches a cascade token that is not scoped to user identity. When using this token you should pass the identity in your requests to the VSCS API.
    # This token should only be used for server-side management operations. Only create and start vscs endpoints support this token. This token is scoped to the plan only.
    def fetch_management_cascade_token!(expires_in:)
      expiration = expires_in.from_now.to_i

      post_body = {
        "scope": WRITE_SCOPE,
        "expiration": expiration
      }

      parsed_response = vscs_api(:post, "api/v1/tokens#{plan_id}/writeCodespaces", caller: "fetch_management_cascade_token", body: post_body.to_json)

      if token = parsed_response["accessToken"]
        { token:, expiration: }.to_json
      else
        nil
      end
    end

    def build_netmon_correlation_data(repo:, billable_owner:, user: nil)
      {
        billableOwnerGlobalRelayId: billable_owner&.global_relay_id,
        billableOwnerDatabaseId: billable_owner&.id,
        billableOwnerCreatedAt: billable_owner&.created_at.utc.iso8601(3),
        billableOwnerPlan: billable_owner&.plan.to_s,
        ownerGlobalRelayId: user&.global_relay_id,
        ownerDatabaseId: user&.id,
        ownerCreatedAt: user&.created_at.utc.iso8601(3),
        ownerPlan: user&.plan.to_s,
        repositoryGlobalRelayId: repo&.global_relay_id,
        repositoryDatabaseId: repo&.id,
        repositoryCreatedAt: repo&.created_at.utc.iso8601(3),
        repositoryPrivate: repo&.private?,
      }
    end

    def add_user_tier_to_body(body:, user:)
      tier_result = Codespaces::Tier.for_user(user)
      tier_name = TrustTiers::Tier.tier_name(tier_result.tier)
      body[:userTier] = tier_name
    end

    def add_vnet_injected_subnet_id_to_body(body:, repo:, user:, billable_owner:, location:)
      return unless network_config = Codespaces::NetworkConfiguration.for(repository: repo, billable_owner: billable_owner, actor: user)
      subnet_id = network_config.subnet_id(location)
      return unless subnet_id.present?
      body[:vnetInjectionSubnetId] = subnet_id
    rescue Codespaces::NetworkConfiguration::NotFoundForRegion
      raise VNetInjectionNotAvailableForRegionError
    end

    # Features to be sent via the create/start body
    def add_features_to_body(body, billable_owner, features = {}, repo:)
      body[:features] = Codespaces::Vscs.feature_flags(user, billable_owner).merge(features)

      # Add Host Setup Policy flag separately since its checking two flags and the service is already looking at the codespacesHostSetupPolicy feature attribute
      body[:features][:codespacesHostSetupPolicy] = billable_owner.in_codespaces_salus_beta? && billable_owner.feature_enabled?(:codespaces_host_setup_policy)

      # !!! NOTE: Do not add new features flags below !!!
      # To add a new feature flag add it to the Codespaces::Vscs::OWNER_FEATURE_FLAGS or BILLABLE_OWNER_FEATURE_FLAGS array. Below is Ye Olde Way. ###
      body[:features][:processKillTracing] = GitHub.flipper[:codespaces_process_kill_tracing].enabled?(user)
      body[:features][:enableProvjobd] = on_vm_abuse_monitoring_should_be_enabled?(billable_owner:, repo:)
      body[:features][:usePublicDevcontainerCli] = GitHub.flipper[:codespaces_use_public_devcontainer_cli].enabled?(user)
      body[:features][:experimentalDevContainerLockfile] = GitHub.flipper[:codespaces_experimental_dev_container_lockfile].enabled?(user)
      body[:features][:remountStorageAsReadWrite] = GitHub.flipper[:codespaces_remount_storage_as_read_write].enabled?(user)
      body[:features][:enableOnVmSwapping] = GitHub.flipper[:codespaces_enable_on_vm_swap].enabled?(user)
    end

    def build_environment_body_with_raw_secrets(environment_options:, moniker: nil, name:, billable_owner:, repo:, sku_name: nil, github_token:, codespace_token: "", secrets:, use_unscoped_management_token: false, prebuild_hash: nil, prebuild_allowed: false, create_type:, location:)
      seed = build_environment_seed_details(
        prebuild_hash: prebuild_hash,
        repo: repo,
        oid: oid,
        moniker: moniker,
        branch: branch,
        devcontainer_path: environment_options[:devcontainerPath],
        create_type:,
      )
      analytics_tracking_id = nil
      if user
        if GitHub.flipper[:codespaces_enable_analytics_id].enabled?(user)
          analytics_tracking_id = user.analytics_tracking_id
        end
      end

      # Passing copliotWorkspaceConfig as secrets as it contains sensitive data (eg. JWT)
      copilot_workspace_config_secrets = []
      if environment_options.is_a?(Hash)
        copilot_workspace_config = environment_options.delete(:copilotWorkspaceConfig)

        if copilot_workspace_config && !copilot_workspace_config.empty? && copilot_workspace_config.respond_to?(:to_json)
          # Intentionally added "GITHUB" prefix to the secret name so that a user cannot create a user/repo/org level secret with the same name
          copilot_workspace_config_secrets = [
            {
              "type": Codespaces::Secret::TYPE_ENV_VAR,
              "name": "GITHUB_COPILOT_WORKSPACE_CONFIG",
              "value": copilot_workspace_config.to_json,
            }
          ]
        end
      end

      secrets = Codespaces::AssembleSecrets.call(
        user: user,
        github_token: github_token,
        codespace_token: codespace_token,
        user_secrets: secrets,
        repository: repo,
        vscs_target_url: api_url,
        vscs_target:,
      )

      Array(secrets).concat(copilot_workspace_config_secrets)

      codespace_environment_body = {
        id: "",
        type: ENVIRONMENT_TYPE,
        friendlyName: name,
        seed: seed,
        gitHubAnalyticsId: analytics_tracking_id,
        personalization: {
          dotfilesTargetPath: "~/dotfiles",
        },
        connection: {
          sessionId: "",
          sessionPath: "",
        },
        githubEnvironmentEndpoint: "#{monolith_url_builder.api_url}/internal/vscs/environment_webhook",
        created: Time.now.utc.iso8601(3),
        skuName: sku_name,
        secrets: secrets,
        preferredComputeImageChannel: get_compute_image_channel
      }

      if user.present?
        codespace_environment_body[:identity] = {
          id: "#{user.id}",
          username: "#{user.login}", # rubocop:disable GitHub/DoNotAllowLogin FE expects login to be unique
          displayName: "#{user.name}",
        }
      end

      # attributes in codespace_environment_body should take priority over passthrough environment_options
      environment_options.merge(codespace_environment_body).tap do |body|
        body[:autoShutdownDelayMinutes] = AUTO_SHUTDOWN_MINUTES if body[:autoShutdownDelayMinutes].nil?
        body[:experimentalFeatures] ||= {}
        body[:experimentalFeatures][:customContainers] = true
        body[:experimentalFeatures][:queueResourceAllocation] = true
        body[:gitHubAppUrl] = monolith_url_builder.url
        body[:gitHubApiUrl] = monolith_url_builder.api_url
        body[:devTunnelsDomain] = Vscs.dev_tunnels_domain_for_target(vscs_target)
        body[:testAccount] = GitHub.flipper[:codespaces_automated_testing].enabled?(user)
        target_config = Codespaces::Vscs.config_for_target(vscs_target)
        body[:gitHubPfsAuthEndpoint] = "#{target_config[:web_portal_url_format] % { name:, second_level_domain: GitHub.codespaces_web_portal_second_level_domain }}/pf-signin"

        # TODO: Remove when we move Copilot Workspace for Issues into Cloudspaces architecture
        if GitHub.flipper[:copilot_workspace].enabled?(user) && environment_options[:copilot_workspace_id].present? && environment_options[:copilot_workspace_id] != WorkspaceEditor::Cloudspace::COPILOT_WORKSPACE_ID
          body[:experimentalFeatures][:copilotWorkspace] = true
        end

        if prebuild_allowed
          body[:experimentalFeatures][:usePrebuiltImages] = true
          configuration = Codespaces::PrebuildConfiguration.find_by(repository_id: repo.id, branch: branch, devcontainer_path: environment_options[:devcontainerPath], vscs_target: vscs_target)

          if !configuration.present? && vscs_target == Codespaces::Vscs.default_target
            configuration = Codespaces::PrebuildConfiguration.find_by(repository_id: repo.id, branch: branch, devcontainer_path: environment_options[:devcontainerPath], vscs_target: nil)
          end

          body[:experimentalFeatures][:usePrebuildFastPathIfAvailable] = configuration&.fast_path_enabled || false
        end

        use_storage_v2 = Codespaces::Vscs.use_storage_v2?(repo: repo, current_user: user, sku_name: sku_name, billable_owner: billable_owner)
        body[:experimentalFeatures][:useStorageV2] = use_storage_v2

        use_raw_fuse = use_storage_v2 && (raw_fuse_enabled(repo: repo, billable_owner: billable_owner) || environment_options[:forceRawFuse] == true)
        body[:experimentalFeatures][:useRawFuse] = use_raw_fuse

        use_file_syncer_with_bridge = environment_options.delete(:fileSyncerWithBridge) if environment_options[:fileSyncerWithBridge].present?
        body[:experimentalFeatures][:fileSyncerWithBridge] = use_file_syncer_with_bridge if use_file_syncer_with_bridge

        # Should we install a post commit hook to enable "fork before push" behavior
        # We check can_fork? and has_forked? in case the user has an exisiting fork but because of settings changes
        # can't create a new fork we can still use the post commit to point the codespace to their exisiting fork
        install_post_commit_fork_hook = user &&
          !repo.pushable_by?(user) &&
          (user.can_fork?(repo) || user.has_forked?(repo))

        features = body[:features] || {}
        features[:installPostCommitForkHook] = install_post_commit_fork_hook if install_post_commit_fork_hook
        features[:useStorageV2] = use_storage_v2
        features[:useRawFuse] = use_raw_fuse
        features[:fileSyncerWithBridge] = use_file_syncer_with_bridge if use_file_syncer_with_bridge
        add_features_to_body(body, billable_owner, features, repo: repo)

        if user&.codespace_dotfiles_enabled? && user.codespace_dotfiles_repository.present?
          body[:personalization][:dotfilesRepository] = user.codespace_dotfiles_repository.permalink
        end

        add_vnet_injected_subnet_id_to_body(body:, repo: repo, user:, billable_owner:, location:)
      end
    end

    def get_compute_image_channel
      if GitHub.flipper[:codespaces_compute_beta_images].enabled?(user)
        user.codespace_preferred_host_image
      else
        Codespaces::Settings::PREFERRED_HOST_IMAGE_STABLE
      end
    end

    def build_template_environment_body(environment_options:, moniker: nil, name:, repo:, use_unscoped_management_token: false, prebuild_hash: nil, workflow_run_id: nil, configuration_id: nil, storage_type: nil, create_type:)
      seed = build_environment_seed_details(
        prebuild_hash: prebuild_hash,
        repo: repo,
        oid: oid,
        moniker: moniker,
        branch: branch,
        devcontainer_path: environment_options["devcontainer_path"],
        create_type:,
      )

      raise ArgumentError, "prebuild_hash is required in template seed. " unless seed[:repository][:prebuild_hash].present?

      codespace_environment_body = {
        id: "",
        type: ENVIRONMENT_TYPE,
        friendlyName: name,
        seed: seed,
        created: Time.now.utc.iso8601(3),
        devcontainerPath: environment_options["devcontainer_path"],
        gitHubPrebuildInstanceEndpoint: "#{GitHub.api_url}/internal/vscs/codespaces/prebuild/instances",
        gitHubPrebuildTemplateEndpoint: "#{GitHub.api_url}/internal/vscs/codespaces/prebuild/templates",
      }

      target_suffix = vscs_target == Codespaces::Vscs.default_target.to_sym ? "" : "_#{vscs_target}"
      if repo.feature_enabled?("codespaces_add_features_to_create_prebuild_request#{target_suffix}")
        codespace_environment_body[:features] = {
          IsTemplateRepoPrebuild: repo.feature_enabled?(:codespaces_prebuild_use_template_account)
        }
      end

      template_info = environment_options["template_info"]
      if template_info.present?
        template_info_body = {
          totalTimeSavingsInSeconds: template_info["total_time_saving"],
          templateSizeInGB: template_info["template_size"],
          workflowRunId: workflow_run_id,
          configurationId: configuration_id,
          container: {
            id: template_info["container"]["id"],
            schemaVersion: template_info["container"]["schema_version"],
            imageName: template_info["container"]["image_name"],
          },
        }

        storage_image_version = template_info["storage_image_version"]
        if storage_image_version.present?
          template_info_body[:storageImageVersion] = storage_image_version
        end

        codespace_environment_body[:templateInfo] = template_info_body
      else
        raise ArgumentError, "template_info is required"
      end


      storage_type = environment_options["storage_type"]
      if storage_type.present?
        codespace_environment_body[:storageType] = storage_type
      end

      codespace_environment_body
    end

    def build_environment_seed_details(prebuild_hash:, repo:, oid:, moniker:, branch:, create_type:, devcontainer_path: nil)
      if user
        git_username, git_email = User.git_author_info(user)
        git_email = user.default_author_email(repo) || git_email
      else
        git_username, git_email = nil
      end

      seed = {
        type: "git",
        moniker: moniker,
        # include_host is false here because #permalink only allows use of the default GitHub host (which sometimes codespaces customizes in development)
        cloneUrl: monolith_url_builder.url + repo.permalink(include_host: false),
        gitConfig: {
          userName: git_username,
          userEmail: git_email,
        },
      }

      seed.merge!({
        repository: build_repository_details(
          repo: repo,
          branch: branch,
          prebuild_hash: prebuild_hash,
          oid: oid,
          moniker: moniker,
          devcontainer_path: devcontainer_path,
          create_type:,
        )
      })

      seed
    end

    def build_repository_details(repo:, branch:, oid:, moniker:, prebuild_hash:, devcontainer_path:, create_type:)
      # common properties regardless whether prebuild configured or not
      repository_details = {
        id: repo.id,
        name: repo.name,
        commit: oid,
        create_type:,
        owner: repo.owner.display_login,
        disk_usage: repo.disk_usage,
      }

      if Codespaces::Prebuilds.configured?(repo)
        repository_details.merge!(build_prebuild_repository_details(
          prebuild_hash: prebuild_hash,
          repo: repo,
          oid: oid,
          moniker: moniker,
          branch: branch,
          devcontainer_path: devcontainer_path,
        ))
      else
        repository_details.merge!({
          branch: branch,
        })
      end
    end

    def build_prebuild_repository_details(prebuild_hash:, repo:, oid:, moniker:, branch:, devcontainer_path:)
      if prebuild_hash.nil? && repo.present? && oid.present?
        prebuild_hash = Codespaces::CalculatePrebuildHash.call(repository: repo, oid: oid, devcontainer_path: devcontainer_path)
      end

      repository = {
        url: moniker,
        prebuild_hash: prebuild_hash
      }
      repository[:branch] = branch if branch.present?

      repository
    end

    def vscs_api(method, path, caller:, body: {}, tags: [], &block)
      response = vscs_api_hmac_raw(method, path, caller: caller, body: body, tags: tags)

      if response.success?
        begin
          result = GitHub::JSON.parse(response.body)
          if block_given?
            yield response
          else
            result
          end
        rescue Yajl::ParseError
          raise BadResponseError.new(request_err_message("Bad response", method, "invalid JSON"), response.status, response.body, rollup_components: [caller])
        end
      else
        error_body = response.body
        begin
          error_body = GitHub::JSON.parse(response.body)
        rescue Yajl::ParseError
        end
        raise BadResponseError.new(request_err_message("Bad response", method), response.status, error_body, rollup_components: [caller])
      end

    rescue Faraday::TimeoutError
      raise TimeoutError.new(request_err_message("Timeout exceeded", method), rollup_components: [caller])
    rescue Faraday::ConnectionFailed => e
      raise ConnectionFailed.new(request_err_message("Connection failed: #{e.message}", method), rollup_components: [caller])
    end

    def vscs_api_hmac_raw(method, path, caller:, body:, tags: [])
      headers = {
        "Content-Type" => (method == :patch ? "application/json-patch+json" : "application/json"),
        "Request-HMAC" => request_hmac,
        "X-Subscription-Id" => plan.subscription,
      }

      if user.present?
        headers["X-User-Id"] = user.id
      end

      if plan.present?
        headers["X-Plan-Id"] = plan.name
      end

      all_tags = ["caller:#{caller}"]
      if tags.present?
        all_tags = all_tags.concat(tags)
      end

      all_tags = (all_tags + stats_tagger.datadog_tags).uniq

      with_response_timing("codespaces.client.vscs_api.response", tags: all_tags) do
        if method == :get
          vscs_connection.get(path, body, headers)
        else
          vscs_connection.run_request(method, path, body, headers)
        end
      end
    end

    def request_hmac
      hmac_key = HMAC_KEYS[vscs_target]
      raise MissingHMACKeyError unless hmac_key

      GitHub::RequestHmacValidator.request_hmac(Time.current, hmac_key)
    end

    # environment-scoped cascade token inherits its expiration from the plan-scoped token
    def write_cascade_token_cache(guid:, token:, expiration:)
      Codespaces::TokenCache.write_codespace_cascade_token(owner_id: user.id, guid: guid, token: token, expiration: expiration)
    end

    def vscs_connection
      @vscs_connection ||= connection_for(api_url) do |f|
        f.use Codespaces::FollowVsoRedirects
      end
    end

    def stats_tagger
      @stats_tagger ||= Codespaces::StatsTagger.new(
        vscs_target: vscs_target,
        user: user,
        location: location,
      )
    end

    def skip_requesting_access_token?
      user&.feature_enabled?(:codespaces_skip_requesting_access_token)
    end

    def raw_fuse_enabled(repo:, billable_owner:)
      raw_fuse_disallowed_flag = "codespaces_raw_fuse_disallowed"
      return false if user.feature_enabled?(raw_fuse_disallowed_flag) || repo.feature_enabled?(raw_fuse_disallowed_flag)

      target_suffix = vscs_target == Codespaces::Vscs.default_target.to_sym ? "" : "_#{vscs_target}"
      feature_flag_name = "codespaces_use_raw_fuse#{target_suffix}"

      billable_owner&.feature_enabled?(feature_flag_name) || user.feature_enabled?(feature_flag_name) || repo.feature_enabled?(feature_flag_name)
    end

    sig { params(billable_owner: User, repo: Repository).returns(T::Boolean) }
    def on_vm_abuse_monitoring_should_be_enabled?(billable_owner:, repo:)
      return false unless GitHub.flipper[:codespaces_enable_on_vm_monitoring].enabled?(user)
      return false if GitHub.flipper[:codespaces_on_vm_monitoring_killswitch].enabled?(user)
      return false if billable_owner.feature_enabled?(:codespaces_on_vm_monitoring_killswitch)
      return false if GitHub.flipper[:codespaces_on_vm_monitoring_killswitch].enabled?(repo)
      tier_result = Codespaces::Tier.for_user(user)
      tier_flag = "codespaces_on_vm_monitoring_killswitch_tier_#{tier_result.tier.to_i}".to_sym
      return false if GitHub.flipper[tier_flag].enabled?
      true
    end
  end
end
