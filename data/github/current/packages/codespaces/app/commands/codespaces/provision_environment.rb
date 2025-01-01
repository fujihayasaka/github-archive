# typed: true
# frozen_string_literal: true

module Codespaces
  class ProvisionEnvironment < Command
    PROVISIONING_LOCK_TIMEOUT = 20.seconds

    class Lock
      def initialize(codespace, ttl: PROVISIONING_LOCK_TIMEOUT)
        @ttl = ttl
        @lock_key = "codespaces-provisioning-lock-#{codespace.name}"
      end

      def locked?
        Codespaces::Kv.store.exists(@lock_key).value { false }
      end

      def lock!
        Codespaces::Kv.store.setnx(@lock_key, "true", expires: @ttl.from_now)
      end

      def unlock!
        Codespaces::Kv.store.del(@lock_key)
      end
    end

    attr_reader :codespace, :environment_options, :request_cascade_token, :github_token, :skip_find, :lock
    delegate :locked?, :lock!, :unlock!, to: :lock, private: true
    delegate :provisioning!, :pending!, :failed!, to: :codespace, prefix: true, private: true

    def initialize(codespace, skip_find: false, environment_options: {}, github_token: "", request_cascade_token: false, lock: Lock.new(codespace), error_reporter: Codespaces::ErrorReporter, mutex: nil)
      @codespace = codespace
      @skip_find = skip_find
      @environment_options = environment_options
      @github_token = github_token.to_s
      @request_cascade_token = request_cascade_token
      @lock = lock
      @error_reporter = error_reporter
      @mutex ||= GitHub::Redis::ConcurrencySafeMutex.new("codespaces.provisioning.#{codespace.id}", timeout: 10.seconds, wait: 0.5.seconds, sleep: 0.1.seconds)
    end

    def perform
      @mutex.lock do
        # We need this because it's possible the synchronous creation flow is still running its own
        # `ProvisionEnvironment` and we cannot allow another one to start in that case.
        begin
          @error_reporter.push(codespace: codespace)

          if codespace.provisioning?
            # As far as we know we should only get in here while already in `provisioning` if we timed out after
            # `Create` started provisioning synchronously but before it had a chance to schedule its provisioning job.
            # Log this state but let provisioning continue.
            GitHub.dogstats.increment("codespaces.provision_environment.provisioning_stuck_allowed", tags: dd_tags.concat(["state:#{codespace.state}"]))
            GitHub.logger.info(
              "Codespaces::ProvisionEnvironment allowed provisioning codespace to attempt provisioning",
              "gh.catalog_service" => "github/codespaces",
              "gh.codespaces.name" => codespace.name,
              "gh.codespaces.state" => codespace.state,
            )
          elsif !codespace.pending?
            GitHub.dogstats.increment("codespaces.provision_environment.skip_not_pending", tags: dd_tags.concat(["state:#{codespace.state}"]))
            GitHub.logger.info(
              "Skipped provisioning because the codespace is not pending",
              "gh.catalog_service" => "github/codespaces",
              "gh.codespaces.name" => codespace.name,
              "gh.codespaces.state" => codespace.state,
            )
            return
          end

          codespace_provisioning!
          environment = provision_environment!
          instrument_provisioning(environment)
        rescue # rubocop:todo Lint/GenericRescue
          # Any failures should put us back into `pending`. The job itself may put
          # us in `failed` depending on the type of error. I don't think we want to
          # duplicate the retryable error stuff here.
          codespace_pending!
          raise
        end
      end
    end

    # Attempts to find or create an environment for this codespace in
    # VSCS. Special retry handling is included here to safeguard against
    # creating duplicate environments on retries.
    #
    # When a timeout is encountered, we lock provisioning and raise a specific
    # error class that can be retried independently of other retryable errors.
    # When the job retries, we can check for this lock and know that we only
    # want to attempt to read the environment until the lock expires. This puts
    # us in a situation where we end up effectively doing:
    #   1. Creation TimeoutError -> lock! -> raise
    #   2. locked? -> Environment found? -> No -> raise
    #   3. locked? -> Environment found? -> No -> raise
    #   4. locked? -> Environment found? -> No -> raise
    #   5. Found environment to use and complete provisioning -> unlock!
    # There is also a possibility that we will continue retrying and never find
    # an environment with the correct name. This would happen if we timed out
    # initially and the request actually went on to FAIL in VSCS. In that case
    # we would want to retry creation again once the lock expires.
    def provision_environment!
      environment = begin
        if locked? # The bang variant here raises if not found.
          Codespaces::FindEnvironment.call!(codespace)
        elsif skip_find # The caller will know an environment doesn't exist yet on the first run for a new codespace.
          Codespaces::CreateEnvironment.call(codespace, environment_options: environment_options, github_token: github_token, request_cascade_token: request_cascade_token)
        else
          Codespaces::FindEnvironment.call(codespace) ||
            Codespaces::CreateEnvironment.call(codespace, environment_options: environment_options, github_token: github_token, request_cascade_token: request_cascade_token)
        end.tap { unlock! }
      rescue Codespaces::CreateEnvironment::TimeoutError
        # If creation timed out we need to lock fetching this codespace temporarily.
        lock! and raise
      end
      codespace.update!(
        guid: environment.id,
        state: :provisioned,
        environment_data: environment,
      )
      environment
    end

    def instrument_provisioning(environment)
      GitHub.dogstats.increment("codespaces.provisioned", tags: dd_tags)
      GitHub.dogstats.distribution("codespaces.provisioned.dist", 1, tags: dd_tags)
      GitHub.logger.info(
        "codespaces.provisioned",
        "gh.catalog_service" => "github/codespaces",
        "gh.codespaces.name" => codespace.name,
        "gh.codespaces.id" => codespace.id,
      )

      GlobalInstrumenter.instrument("codespaces.provisioned", codespace: codespace, attempted_from_prebuild: environment.attempted_from_prebuild, prebuild_type: environment.prebuild_type)

      if codespace.repository&.owner.codespaces_feature_enabled? && environment.attempted_from_prebuild
        codespace.instrument(:attempted_to_create_from_prebuild, guid: codespace.guid)
        if environment.prebuild_type.present?
          GitHub.dogstats.increment("codespaces.prebuild_type", tags: dd_tags.concat(["prebuild_type:#{environment.prebuild_type}"]))
        end
      end

      codespace.instrument :provision_environment, guid: codespace.guid
      codespace.instrument_connect
      codespace.instrument(:start_environment, actor: codespace.owner)
      environment
    end
  end
end
