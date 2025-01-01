# typed: true # rubocop:todo Sorbet/StrictSigil
# frozen_string_literal: true

module CloudEnvironments
  class Create < CloudEnvironments::Command

    class Result
      include CloudEnvironments::ICreateResult

      sig { params(cloud_environment: CloudEnvironment).void }
      def initialize(cloud_environment)
        @cloud_environment = cloud_environment
      end

      sig { params(cloud_environment: CloudEnvironment).returns(CloudEnvironment) }
      attr_writer :cloud_environment

      sig { params(env: Codespaces::Environment).returns(Codespaces::Environment) }
      attr_writer :env

      sig { params(github_token: String).returns(String) }
      attr_writer :github_token

      sig { params(github_token_valid_after: Float).returns(Float) }
      attr_writer :github_token_valid_after

      sig { override.returns(CloudEnvironment) }
      attr_reader :cloud_environment

      sig { override.returns(T.nilable(Codespaces::Environment)) }
      attr_reader :env

      sig { override.returns(T.nilable(String)) }
      attr_reader :github_token

      sig { override.returns(T.nilable(Float)) }
      attr_reader :github_token_valid_after

      sig { override.returns(T::Boolean) }
      def provisioned?
        return false unless cloud_environment.provisioned?
        !!env&.has_connection?
      end
    end

    attr_reader :attributes, :environment_options, :result, :ref, :oid, :operation

    sig do
      params(
        attributes: T::Hash[Symbol, T.untyped],
        operation: Codespaces::AsyncOperation,
        stats_tagger: CloudEnvironments::IStatsTagger,
        environment_options: T::Hash[Symbol, T.untyped],
        provisioner: T.nilable(T.class_of(Codespaces::Command)),
        entry_point: T.nilable(T.any(String, Symbol))
      ).void
    end
    def initialize(attributes:,
        operation:,
        stats_tagger:,
        environment_options: {},
        provisioner: nil,
        entry_point: nil
      )
      @attributes = attributes
      @environment_options = environment_options
      @provisioner = provisioner
      @stats_tagger = stats_tagger
      @entry_point = entry_point
      @operation = operation
    end

    sig { override.returns(Result) }
    def perform
      @result = Result.new(T.cast(CloudEnvironments::CloudEnvironment.create!(attributes), CloudEnvironment))

      # Capture the create attempt *after* we've enforced rate limiting, concurrency limits, and performed
      # validation, and *before* we actually write the record to the database. That way we don't count invalid
      # requests but we do count attempts that fail because the database is unavailable.
      GitHub.dogstats.increment("codespace.created", tags: dd_tags)
      GitHub.dogstats.distribution("codespace.created.dist", 1, tags: dd_tags)

      GitHub.logger.info(
        "codespace.created",
        "gh.catalog_service" => "github/codespaces",
        "gh.codespaces.name" =>  cloud_environment.name,
        "gh.codespaces.id" => cloud_environment.id,
        "gh.codespaces.billable_owner_login" => cloud_environment.billable_owner&.login, # rubocop:disable GitHub/DoNotAllowLogin
        "gh.codespaces.owner_login" => cloud_environment.owner&.login, # rubocop:disable GitHub/DoNotAllowLogin
        "gh.repo.name_with_owner" => cloud_environment.repository&.nwo, # rubocop:disable GitHub/DoNotAllowNameWithOwner
        "gh.codespaces.region" => cloud_environment.location,
      )

      if operation
        operation.update(codespace: cloud_environment)
        operation.mark_as_started
      end

      cloud_environment.track_pr_source!
      cloud_environment.merge_environment_data!({ state: Codespaces::Vscs::State::CREATED })

      # Immediately schedule this so that if we're interrupted by a GLB timeout while doing the synchronous
      # provision we'll still have a chance to retry provisioning.
      CodespacesProvisionJob.perform_after_waiting_period(
        waiting_period: GitHub.default_request_timeout,
        codespace: cloud_environment,
        environment_options: environment_options,
        entry_point: @entry_point
      )

      GitHub.tracer.in_span("codespaces/create#perform_sync", attributes: tags, kind: :internal) do |span|
        generate_github_token!
        result.env = provision!
        span.set_attribute("gh.codespaces.immediately_connected", result.env["connection"].present?) if result.env
      end

      result
    end

    def provisioner
      @provisioner ||= Codespaces::ProvisionEnvironment
    end

    private

    def cloud_environment
      result&.cloud_environment
    end

    def provision!
      provisioner.call(
        cloud_environment,
        skip_find: true, # We know we need to create the environment, so save time & don't try to find it first.
        environment_options: environment_options,
        github_token: result.github_token
      )
    rescue *CodespacesProvisionJob::ALL_RETRYABLE_ERRORS => e
      # Retry as a job that can auto-handle a lot of these failure modes, and handle "true failure" properly.
      GitHub.dogstats.increment("codespaces.create.synchronous.retryable_failure", tags: dd_tags.concat(["error:#{e.class.name}"]))
      GitHub.dogstats.distribution("codespaces.create.synchronous.retryable_failure.dist", 1, tags: dd_tags.concat(["error:#{e.class.name}"]))
      nil
    rescue => e # rubocop:todo Lint/GenericRescue
      cloud_environment.failed!
      operation&.mark_as_failed(failure_reason: e)
      raise
    end

    def generate_github_token!
      github_token, github_token_valid_after = Codespaces::Tokens.mint_github_token_with_estimated_validity(cloud_environment.owner, cloud_environment, entry_point: @entry_point)
      result.github_token = github_token
      result.github_token_valid_after = github_token_valid_after
    end

    def dd_tags
      tags = super
      tags << "codespaces_use_storage_v2_internal:true" if use_storage_v2_internal?
      tags
    end

    def use_storage_v2_internal?
      return false unless cloud_environment
      return false unless attributes[:owner]&.feature_enabled?(:codespaces_developer)
      storage_v2_enabled = [cloud_environment.repository, attributes[:owner]].all? do |entity|
        entity&.feature_enabled?(:codespaces_use_storage_v2)
      end

      force_storage_v2_enabled = [cloud_environment.repository, attributes[:owner]].any? do |entity|
        entity&.feature_enabled?(:codespaces_force_storage_v2)
      end

      storage_v2_enabled || force_storage_v2_enabled
    end
  end
end
