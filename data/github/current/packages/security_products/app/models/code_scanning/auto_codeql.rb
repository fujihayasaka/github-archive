# typed: true
# frozen_string_literal: true

module CodeScanning
  class AutoCodeql < SecurityProduct::Service

    include GitHub::Memoizer
    include SecurityProduct::Service::ActionsChecks

    DISMISSED_AUTO_CODEQL_NOTICE = "dismissed_auto_codeql_notice"
    DEFAULT_RUNNER_LABEL = "code-scanning"

    ERROR_MESSAGES = {
      turboscan_onboard_failed: "Turboscan onboard endpoint failed",
      turboscan_update_failed: "Turboscan update endpoint failed",
      turboscan_offboard_failed: "Turboscan offboard endpoint failed",
      turboscan_adjust_failed: "Turboscan adjust configuration endpoint failed"
    }

    WORKFLOW_FILE_PATH = "dynamic/github-code-scanning/codeql"

    class Options < SecurityProduct::Service::Options
      option :runner_type, default: "not_set"
      validates :runner_type, allow_nil: false, inclusion: {
        in: (
          if GitHub.enterprise?
            %w[not_set labeled]
          else
            %w[not_set standard labeled]
          end
        ),
        message: (
          if GitHub.enterprise?
            "option must be a labeled runner."
          else
            "option must be standard GitHub runner or labeled runner."
          end
        )
      }
      option :runner_label, default: nil
      validates :runner_label, length: { minimum: 1, maximum: 255 }, if: :labeled_runner?

      def not_set?
        (T.let(self, T.untyped).runner_type.presence || "not_set") == "not_set"
      end

      def labeled_runner?
        T.let(self, T.untyped).runner_type == "labeled"
      end
    end

    # on_enable and on_disable are called when the user enables or disables AutoCodeQL,
    # or updates the configuration.
    # The methods are typically called via the SecurityProduct::ToggledServiceCollection class
    # When changing these methods, please ensure that the behavior is idempotent, as this is
    # a requirement for this interface.
    def on_enable(actor:, options:)
      log_timing do
        # we want to know whether this is happenning for enabling or for updating.
        # callers can encode that into the options using :action => :update or :enable
        # This allows us to avoid extra calls to turboscan unless strictly necessary.
        case options[:action]
        when :update
          update = true
        when :enable
          update = false
        when nil
          update = !disabled?
        else
          raise ArgumentError, "Invalid action #{options[:action]}"
        end

        # enforce repository security configuration if it does not match the new runner label settings
        if repository.owner&.security_configurations_enabled?
          repository_security_configuration = RepositorySecurityConfiguration.joins(:security_configuration).find_by(repository_id: repository.id)
          security_configuration = repository_security_configuration&.security_configuration

          if repository_security_configuration.present? && security_configuration&.code_scanning_options.present?
            security_configuration_options = CodeScanning::AutoCodeql::Options.new_from_hash(security_configuration&.code_scanning_options)
            new_options = CodeScanning::AutoCodeql::Options.new_from_hash(options.with_indifferent_access)

            # do not do anything if the runner type is 'not set'
            unless security_configuration_options.not_set?
              options_match = security_configuration_options.runner_type == new_options.runner_type && security_configuration_options.runner_label == new_options.runner_label

              if !options_match
                if repository_security_configuration.enforced?
                  return SecurityProduct::Result.new(SecurityProduct::ToggledServiceCollection.empty, :security_configuration_enforced)
                else
                  repository_security_configuration.remove_if_possible(
                    action: "enabled",
                    feature: to_sym,
                    owner: T.must(repository.owner),
                    force: true,
                  )
                end
              end
            end
          end
        end

        update ? do_update(actor:, options:) : do_enable(actor:, options:)
      end
    end

    def on_disable(actor:, options:)
      log_timing do
        @turboscan_data = nil # Invalidate existing data as this is action can change the state of Turboscan

        response = GitHub::Turboscan::ManagedAnalyses.disable({ repository_id: repository.id })
        error = nil
        if response.nil? || response.data.nil? || response.error.present?
          error = AutoCodeqlError.new(ERROR_MESSAGES[:turboscan_offboard_failed], repo_id: repository.id, twirp_error: response&.error)
          return SecurityProduct::Result.new(SecurityProduct::ToggledServiceCollection.create(to_sym, options), error)
        end

        # Exit early if the operation was a noop
        return SecurityProduct::Result.new(SecurityProduct::ToggledServiceCollection.empty) if response.data.noop

        publish_auto_codeql_instrumentation(action: "disabled", actor: actor)
        SecurityProduct::Result.new(SecurityProduct::ToggledServiceCollection.create(to_sym, options))
      end
    end

    sig { params(languages: T::Array[String], workflow_run_id: T.nilable(Integer)).returns(SecurityProduct::Result) }
    def adjust_configuration(languages, workflow_run_id = nil)
      @turboscan_data = nil # Invalidate existing data as this action can change the state of Turboscan

      # Ensure canonical representation of the languages
      languages = language_support.canonical_names(languages)

      request = {
        repository_id: repository.id,
        owner_id: repository.owner_id,
        languages: languages,
        workflow_run_id: workflow_run_id || 0
      }

      response = GitHub::Turboscan::ManagedAnalyses.adjust(request)
      if response&.data.nil? || response&.error.present?
        error = AutoCodeqlError.new(ERROR_MESSAGES[:turboscan_adjust_failed], repo_id: repository.id, twirp_error: response&.error)
        return SecurityProduct::Result.new(false, error)
      end

      SecurityProduct::Result.new(true)
    end

    sig { override.params(options: T.untyped).returns(T::Boolean) }
    def enabled_with_options?(options: {})
      enabled? && options[:runner_type] == configuration.runner_type && options[:runner_label] == configuration.runner_label
    end

    def enabled?
      log_timing do
        %w[waiting onboarding stable updating].include? onboarding_status
      end
    end

    def disabled?
      onboarding_status == "disabled"
    end

    # TODO: Rename this to `onboarding?`
    def enabling?
      onboarding_status == "onboarding"
    end

    def updating?
      onboarding_status == "updating"
    end

    def waiting?
      onboarding_status == "waiting"
    end

    # Returns whether the repository is onboarded to AutoCodeQL.
    # If we do not have data about the repository, we consider AutoCodeQL disabled.
    def onboarding_status
      return "disabled" unless CodeScanning::AutoCodeql.required_services_enabled?(repository)

      turboscan_data.status_v2.to_s.downcase
    end

    # Returns whether the repository is onboarded to AutoCodeQL.
    # If we do not have data about the repository, we consider AutoCodeQL disabled.
    def has_failed_update?
      turboscan_data.has_failed_update
    end

    # Returns the id of the latest debuggable workflow run from default setup
    # This will be for a configuration that is validating or has recently failed validation
    def debuggable_auto_codeql_run_id
      workflow_run_id = turboscan_data.debuggable_workflow_run_id

      workflow_run_id.to_s unless workflow_run_id.zero?
    end

    # Returns the id of the latest workflow run (for both, yml and AutoCodeQL setup)
    def latest_workflow_run_id
      workflow_run_id = codeql_status&.latest_workflow_run_id

      workflow_run_id unless workflow_run_id&.zero?
    end

    sig { returns(T.nilable(CodeScanning::Status::ToolInfo)) }
    def codeql_status
      return @codeql_status if defined?(@codeql_status)
      @codeql_status = codeql_status_inner
    end

    # Checks if we should consider the repo as having a manual workflow (YML or API).
    def has_manual_workflow?
      has_codeql_setup? && codeql_status&.has_recent_manual_workflow?(max_age: 90.days) && codeql_status&.active_workflows&.any?
    end

    # Returns workflow path if the latest analysis was done via actions.
    # This might be a real path (in the git repo) or a `dynamic/...` path
    # in case of a dynamic workflow run.
    sig { returns T.nilable(T.any(String, Pathname)) }
    def codeql_workflow_path
      codeql_status&.workflow_paths&.first
    end

    # Returns onboarding validation run failed error message
    def disabled_reason
      return unless onboarding_status == "waiting"

      # If the required services are not enabled, we don't want to show the error message
      return unless CodeScanning::AutoCodeql.required_services_enabled?(repository)

      # TODO: instead of bubbling up ts error as it is, should we wrap it with a more generic error message?
      turboscan_data.error
    end

    def can_enable?(actor:, options:)
      log_timing do
        error = CodeScanning::Status.validate_prerequisites(repository, actor, options: options.merge(include_default_setup_prerequisites: true))
        return SecurityProduct::Result.new(false, error) if error.present?

        if !!options.dig(:fail_on_manual_workflow?) && has_manual_workflow?
          return SecurityProduct::Result.new(false, :manual_workflow_configured)
        end

        SecurityProduct::Result.new(true)
      end
    end

    memoize def runners_error
      CodeScanning::Status.validate_default_setup_runners(repository)
    end

    def self.error_to_message(error)
      case error
      when :repo_archived
        "Code scanning default setup cannot be enabled on archived repositories."
      when :advanced_security_disabled
        "Code scanning default setup can only be enabled on repos where Advanced Security is enabled."
      when :code_security_disabled
        "Code scanning default setup can only be enabled on repos where Code Security is enabled."
      when :code_scanning_not_available
        "Code scanning default setup cannot be enabled as Code Scanning is not available."
      when :instance_actions_disabled
        "Code scanning default setup can only be enabled if Actions is enabled. GitHub Actions is not enabled on this instance, please ask your instance administrator to configure Actions."
      when :instance_actions_disabled_admin
        "Code scanning default setup can only be enabled if Actions is enabled. GitHub Actions is not enabled on this instance, please configure Actions."
      when :repo_actions_disabled_by_owner
        "Code scanning default setup can only be enabled if Actions is enabled. GitHub Actions is disabled on this repostiory by an enterprise or organization policy. Please ask your organization administrator to enable Actions."
      when :repo_actions_disabled
        "Code scanning default setup can only be enabled if Actions is enabled. GitHub Actions is disabled on this repository, please enable it."
      when :actions_policy_disabled
        # This is not following the same format as the other errors
        "GitHub Actions policy is limiting the use of some required actions. To use code scanning default setup, allow actions from `actions/*` and `github/codeql-action/*`."
      when :no_runners_assigned
        "Code scanning default setup can only be enabled if runners with label code-scanning are assigned to this repository."
      when :no_macos_runners_assigned
        "Code scanning default setup for Swift can only be enabled if runners with both code-scanning and macOS labels are assigned to this repository."
      when :manual_workflow_configured
        "Code scanning default setup can only be enabled if no manual workflow is configured."
      when :advanced_setup_enabled
        "Code scanning default setup can only be enabled if advanced setup is disabled."
      when :security_configuration_enforced
        "Code scanning default setup cannot be modified. This setting is controlled by organization administrators."
      when :runner_not_available
        "Code scanning default setup can only be enabled if a runner with the specified label is assigned to this repository."
      else
        "Failed to toggle code scanning default setup."
      end
    end

    def can_disable?(actor:, options:)
      log_timing do
        # we expect user-specific authorization check to have happened before this point
        # apart from that there are no scenario where Auto CodeQL can't be disabled
        SecurityProduct::Result.new(true)
      end
    end

    def to_sym
      :auto_codeql
    end

    def self.name
      "Auto CodeQL"
    end

    def update_languages(languages_to_add:, languages_to_delete:)
      # If there is an update already in progress, we raise in order to retry the job a bit later
      if updating?
        raise AutoCodeqlError.new("Config update already in progress", repo_id: repository.id)
      end

      language_support = CodeScanning::AutoCodeqlLanguageSupport.new(repository)
      response = GitHub::Turboscan::ManagedAnalyses.update_languages(
        repository_id: repository.id,
        languages_added: languages_to_add,
        languages_removed: languages_to_delete,
        default_ref: repository.default_branch_ref&.qualified_name,
        owner_id: repository.owner_id,
        supported_languages: language_support.supported_languages,
        codeql_packs: CodeScanningOrgConfigurations.codeql_packs(repository),
      )

      if response.nil? || response.data.nil? || response.error.present?
        Failbot.push(twirp_error: response&.error)

        # If a new update was triggered then we skip the retry
        # because we can assume that the update already accounts for the updated list of languages
        unless response&.error&.code == :already_exists
          raise AutoCodeqlError.new(
            "Turboscan update_language endpoint failed for AutoCodeqlLanguageUpdateJob",
            repo_id: repository.id,
            twirp_error: response&.error
          )
        end

        GitHub.logger.info(response&.error&.msg,
          "code.namespace": "CodeScanning::AutoCodeql",
          "code.function": "update_languages",
          "gh.repo.id": repository.id,
        )
      else
        repository.code_scanning_active!

        GitHub.dogstats.increment("code_scanning.auto_codeql_language_update",
          tags: ["adds:#{languages_to_add.count}", "deletes:#{languages_to_delete.count}"]
        )
      end
    end

    def latest_successful_codeql_analysis_date
      return @latest_successful_codeql_analysis_date if defined?(@latest_successful_codeql_analysis_date)
      @latest_successful_codeql_analysis_date = begin
        response = GitHub::Turboscan.analyses(
          repository_id: repository.id,
          tool: "CodeQL",
          most_recent: true,
          numeric_page: 1,
          limit: 1,
          sort_order: GitHub::Turboscan.api_to_analyses_sort_order("created_at", "desc"),
        )
        if response.blank? || response.error.present? || response.data.total_count == 0
          nil
        else
          response.data.analyses.first.created_at&.to_time
        end
      end
    end

    def has_codeql_setup?
      codeql_status.present?
    end

    # Checks whether the latest CodeQL analysis was done via Default Setup (Managed)
    def latest_codeql_analysis_is_managed?
      codeql_status&.latest_analysis_delivery_origin == :DELIVERY_ORIGIN_MANAGED
    end

    def auto_codeql_failed?
      disabled_reason.present?
    end

    def language_support
      return @language_support if @language_support
      @language_support = CodeScanning::AutoCodeqlLanguageSupport.new(repository)
    end

    def dismiss_auto_codeql_notice(repository_id:, user_id:)
      value = debuggable_auto_codeql_run_id
      return if value.nil?
      CodeScanning::KV.store.setnx(dismiss_notice_key(repository_id: repository_id, user_id: user_id), value)
    end

    def dismissed_auto_codeql_notice?(repository_id:, user_id:)
      ActiveRecord::Base.connected_to(role: :reading) do
        key = dismiss_notice_key(repository_id: repository_id, user_id: user_id)
        CodeScanning::KV.store.get(key).value! == debuggable_auto_codeql_run_id
      end
    end

    def self.required_services_enabled?(repo)
      repo.actions_enabled? && CodeSecurity::Features::AdvancedSecurityHelper.code_security_features_usable?(repository: repo)
    end

    sig { returns(AutoCodeqlConfig) }
    def configuration
      if onboarding_status == "disabled"
        return AutoCodeqlConfig.new(
          state: "not-configured",
          languages: [],
          query_suite: nil,
          threat_model: nil,
          updated_at: nil,
          schedule: nil,
          initial_languages: [],
          creation_trigger: nil,
          runner_label: nil,
        )
      elsif onboarding_status == "waiting" || onboarding_status == "onboarding" || onboarding_status == "enabling"
        # The repo is enabled but we do not have a current config yet.
        # We return only the information that is defined at the repo level.
        return AutoCodeqlConfig.new(
          state: "configured",
          languages: [],
          query_suite: deserialize_query_suite(turboscan_data.query_suite),
          threat_model: deserialize_threat_model(turboscan_data.threat_model),
          updated_at: nil, # TODO: Shall we have a timestamp here?
          schedule: nil,
          initial_languages: [],
          creation_trigger: nil,
          runner_label: turboscan_data.runner_label,
        )
      elsif onboarding_status == "stable" || onboarding_status == "updating" || onboarding_status == "enabled"
        ts_cfg = turboscan_data.current_config
        raise AutoCodeqlError.new("No current config in Turboscan data", repo_id: repository.id) if ts_cfg.nil?
        config = deserialize_config(ts_cfg, "configured")
        config.schedule = "weekly" if is_repo_active?
        return config
      end

      # We should have covered all the cases
      raise AutoCodeqlError.new("Unexpected onboarding status: #{onboarding_status}", repo_id: repository.id)
    end

    def debuggable_configuration
      ts_debuggable_cfg = turboscan_data.debuggable_config
      if ts_debuggable_cfg.present?
        deserialize_config(
          ts_debuggable_cfg,
          has_failed_update? ? "not-configured" : "configured"
        )
      end
    end

    def next_scheduled_run_at
      t = turboscan_data.next_scheduled_run_at
      t.present? ? t.to_time : nil
    end

    def is_repo_active?
      turboscan_data.active_repo
    end

    sig { returns(T.nilable(String)) }
    memoize def default_runner_label
      if GitHub.enterprise? ||
        SecurityProductsEnablement::Actions::RunnerChecker.new(repository).labelled_runners_available?(
          desired_labels: [CodeScanning::AutoCodeql::DEFAULT_RUNNER_LABEL],
          calling_context_only_for_metrics: :auto_codeql_default)

        CodeScanning::AutoCodeql::DEFAULT_RUNNER_LABEL
      end
    end

    sig { returns(AutoCodeqlConfig) }
    memoize def recommended_configuration
      config = recommended_configuration_without_runner_labels
      config.runner_label = default_runner_label

      config
    end


    # The recommended configuration but without setting a recommended runner label.
    # This is to avoid the expensive check to determine whether runners with the `code-scanning`
    # label are available.
    # Use `recommended_configuration` if you need runner label information.
    sig { returns(AutoCodeqlConfig) }
    def recommended_configuration_without_runner_labels
      AutoCodeqlConfig.new(
        state: "not-configured",
        languages: supported_languages,
        query_suite: AutoCodeql.recommended_query_suite(repository),
        threat_model: "remote",
        updated_at: nil,
        schedule: nil,
        initial_languages: [],
        creation_trigger: nil,
        runner_label: nil
        )
    end

    def supported_languages
      language_support.supported_languages
    end

    def self.query_suite_options(owner)
      recommended_description = ""
      if owner.is_a?(Organization) || owner.is_a?(User)
        recommended_description = "Recommended by your organization. " if owner.code_scanning_recommend_extended_query_suite?
      end

      [
        {
          label: "Default",
          value: "default",
          description: "CodeQL high-precision queries.",
        },
        {
          label: "Extended",
          value: "extended",
          description: "#{recommended_description}Queries from the default suite, plus lower severity and precision queries.",
        },
      ]
    end

    sig { params(scope: T.any(Organization, Repository)).returns(String) }
    def self.recommended_query_suite(scope)
      owner = scope.is_a?(Organization) ? scope : scope.owner
      owner&.code_scanning_recommend_extended_query_suite? ? "extended" : "default"
    end

    # TODO: this is no longer needed
    # Returns the configured query suite or nil if unconfigured.
    sig { returns(T.nilable(String)) }
    def active_query_suite
      return unless configuration.state == "configured"
      configuration.query_suite
    end

    def protobuf_query_suite(query_suite)
      if query_suite == "default"
        :QUERY_SUITE_DEFAULT
      elsif query_suite == "extended"
        :QUERY_SUITE_SECURITY_EXTENDED
      else
        :QUERY_SUITE_UNSPECIFIED
      end
    end

    def protobuf_threat_model(threat_model)
      if threat_model == "remote_local" || threat_model == "remote_and_local"
        :THREAT_MODEL_REMOTE_LOCAL
      elsif threat_model == "remote"
        :THREAT_MODEL_REMOTE
      else
        :THREAT_MODEL_UNSPECIFIED
      end
    end

    def set_completed_run_conclusion(run:)
      if !run.completed?
        raise AutoCodeqlError.new("Cannot set the completed status for the run as the run has not completed yet.", repo_id: repository.id)
      end

      response = GitHub::Turboscan::ManagedAnalyses.set_run_conclusion(
        repository_id: repository.id,
        owner_id: repository.owner_id,
        workflow_run_id: run.id,
        conclusion: run.success? ? :CODEQL_RUN_STATUS_COMPLETED : :CODEQL_RUN_STATUS_FAILED,
      )
      if response.blank? || response.error.present? || response.data.nil?
        raise AutoCodeqlError.new("Error fetching data from turboscan", repo_id: repository.id, twirp_error: response&.error)
      end
      # Right now the method is not returning anything
      nil
    end


    private

    def codeql_status_inner
      return nil unless repository.default_branch_ref

      response = GitHub::Turboscan.get_tool_status(
        repository_id: repository.id,
        ref: repository.default_branch_ref.qualified_name,
      )

      # We ignore all errors since we don't want to fail.
      # We just assume nothing is configured if we don't have data.
      if response.nil?
        GitHub.logger.error("Turboscan response was nil",
          "code.namespace": "CodeScanning::AutoCodeql",
          "code.function": "codeql_status",
          "gh.repo.id": repository.id
        )
        return nil
      elsif response.error.present?
        GitHub.logger.error(response.error&.msg,
        "code.namespace": "CodeScanning::AutoCodeql",
        "code.function": "codeql_status",
        "gh.repo.id": repository.id
        )
        return nil
      elsif response.data.nil?
        GitHub.logger.error("Turboscan response was missing data",
          "code.namespace": "CodeScanning::AutoCodeql",
          "code.function": "codeql_status",
          "gh.repo.id": repository.id
          )
        return nil
      end

      tool = T.must(response.data).tools.find { |t| t.name == "CodeQL" }
      return if tool.nil?

      CodeScanning::Status::ToolInfo.new(tool: tool, repo: repository)
    end

    def publish_auto_codeql_instrumentation(action:, actor:, query_suite: nil, threat_model: nil, languages: nil)
      payload = {
        actor: actor,
        repo: repository
      }

      payload[:org] = repository.organization if repository.in_organization?
      payload[:query_suite] = query_suite if query_suite.present?
      payload[:threat_model] = threat_model if threat_model.present?
      payload[:languages] = languages if languages.present?

      if action == "disabled"
        repository.code_scanning_inactive!
      else
        repository.code_scanning_active!
      end

      GitHub.instrument("repo.codeql_#{action}", payload)
    end

    sig { returns(Turboscan::Proto::GetManagedAnalysisInfoResponse) }
    def turboscan_data
      @turboscan_data ||= begin
        response = GitHub::Turboscan::ManagedAnalyses.get_managed_analysis_info(repository_id: repository.id)
        if response.blank? || response.error.present? || response.data.nil?
          raise AutoCodeqlError.new("Error fetching data from turboscan", repo_id: repository.id, twirp_error: response&.error)
        else
          response.data
        end
      end
    end

    sig { params(actor: User, options: T::Hash[Symbol, T.untyped]).returns(SecurityProduct::Result) }
    def do_enable(actor:, options: {})
      # On GHES we need the old global ids to onboard
      repo_global_id = GitHub.enterprise? ? repository.global_relay_id : repository.next_global_id
      actor_global_id = GitHub.enterprise? ? actor.global_relay_id : actor.next_global_id

      request = {
        repository_id: repository.id,
        global_repository_id: repo_global_id,
        enabled_by_actor_grid: actor_global_id,
        enabled_by_actor_login: actor.login,
        default_ref: repository.default_branch_ref&.qualified_name,
        owner_id: repository.owner_id,
        supported_languages: language_support.supported_languages,
        has_kotlin: language_support.has_kotlin?,
        codeql_packs: CodeScanningOrgConfigurations.codeql_packs(repository),
      }

      # on GHES we only support labeled runners
      if GitHub.enterprise?
        options[:runner_type] = "labeled"
        options[:runner_label] ||= CodeScanning::AutoCodeql::DEFAULT_RUNNER_LABEL
      end

      # if CodeQL is enabled and a runner type has not been specified (e.g: via security configurations not-set)
      # and we are recommending a runner label, use that.
      # (we do not recommend a default runner if it is not available)
      if CodeScanning::AutoCodeql::Options.new_from_hash(options.with_indifferent_access).not_set? && recommended_configuration.runner_label.present?
        options[:runner_type] = "labeled"
        options[:runner_label] = recommended_configuration.runner_label
      end

      if options[:runner_type].to_s == "labeled"
        if options[:runner_label].present? && actions_runner_checker&.labelled_runners_available?(desired_labels: [options[:runner_label]], calling_context_only_for_metrics: :auto_codeql_enable)
          request[:runner_label] = options[:runner_label]
        else
          return SecurityProduct::Result.new(SecurityProduct::ToggledServiceCollection.create(to_sym, options), :runner_not_available)
        end
      end

      request[:selected_languages] = options[:languages] || recommended_configuration.languages
      query_suite = options[:query_suite] || recommended_configuration.query_suite
      request[:query_suite] = protobuf_query_suite(query_suite)
      threat_model = options[:threat_model] || recommended_configuration.threat_model
      request[:threat_model] = protobuf_threat_model(threat_model)

      response = GitHub::Turboscan::ManagedAnalyses.enable(request)

      error = nil
      if response.nil? || response.data.nil? || response.error.present?
        error = AutoCodeqlError.new(ERROR_MESSAGES[:turboscan_onboard_failed], repo_id: repository.id, twirp_error: response&.error)
        return SecurityProduct::Result.new(SecurityProduct::ToggledServiceCollection.create(to_sym, options), error)
      end

      if response.data.noop
        options[:noop] = true
      else
        @turboscan_data = nil # Invalidate existing data as this action can change the state of Turboscan
        publish_auto_codeql_instrumentation(action: "enabled", actor: actor, query_suite:, threat_model:, languages: request[:selected_languages])
        dismiss_yml(actor:)
      end

      options[:workflow_run_id] = response.data.workflow_run_id

      SecurityProduct::Result.new(SecurityProduct::ToggledServiceCollection.create(to_sym, options))
    end

    sig { params(actor: User, options: T::Hash[Symbol, T.untyped]).returns(SecurityProduct::Result) }
    def do_update(actor:, options:)
      request = {
        repository_id: repository.id,
        global_actor_id: GitHub.enterprise? ? actor.global_relay_id : actor.next_global_id,
        actor_login: actor.display_login,
        default_ref: repository.default_branch_ref&.qualified_name,
        owner_id: repository.owner_id,
        supported_languages: language_support.supported_languages,
        codeql_packs: CodeScanningOrgConfigurations.codeql_packs(repository),
        runner_type: Turboscan::Proto::UpdateRequest::RunnerType::RUNNER_TYPE_UNCHANGED,
      }

      case options[:runner_type].to_s
      when "standard" then
        request[:runner_type] = Turboscan::Proto::UpdateRequest::RunnerType::RUNNER_TYPE_STANDARD
      when "labeled" then
        if options[:runner_label].present? && actions_runner_checker&.labelled_runners_available?(desired_labels: [options[:runner_label]], calling_context_only_for_metrics: :auto_codeql_update)
          request[:runner_label] = options[:runner_label]
          request[:runner_type] = Turboscan::Proto::UpdateRequest::RunnerType::RUNNER_TYPE_LABELED
        else
          return SecurityProduct::Result.new(SecurityProduct::ToggledServiceCollection.create(to_sym, options), :runner_not_available)
        end
      end

      request[:languages] = options[:languages] if options[:languages].present?

      # options[:languages] == nil ==> There was no change to the selected languages
      # options[:languages] == [] ==> All the languages have been deselected
      # options[:languages] == ["x", "y"] ==> Only x and y should now be selected
      request[:selected_languages] = { languages: options[:languages] } if !options[:languages].nil?

      request[:query_suite] = protobuf_query_suite(options[:query_suite]) if options[:query_suite].present?
      request[:threat_model] = protobuf_threat_model(options[:threat_model]) if options[:threat_model].present?

      response = GitHub::Turboscan::ManagedAnalyses.update(request)
      if response&.data.nil? || response&.error.present?
        error_message = ERROR_MESSAGES[:turboscan_update_failed]

        if response&.error&.code == :already_exists
          error_message = "Configuration update already in progress"
          options[:already_exists] = true
        end

        error = AutoCodeqlError.new(error_message, repo_id: repository.id, twirp_error: response&.error)
        return SecurityProduct::Result.new(SecurityProduct::ToggledServiceCollection.create(to_sym, options), error)
      end

      if response&.data&.noop
        options[:noop] = true
      else
        @turboscan_data = nil # Invalidate existing data as this action can change the state of Turboscan
        publish_auto_codeql_instrumentation(action: "updated", actor: actor, query_suite: options[:query_suite], threat_model: options[:threat_model], languages: request[:languages])
      end

      options[:workflow_run_id] = response&.data&.workflow_run_id

      SecurityProduct::Result.new(SecurityProduct::ToggledServiceCollection.create(to_sym, options))
    end

    def dismiss_notice_key(repository_id:, user_id:)
      "#{DISMISSED_AUTO_CODEQL_NOTICE}.#{repository_id}.#{user_id}.#{debuggable_auto_codeql_run_id}"
    end

    def dismiss_yml(actor:)
      return unless has_manual_workflow?

      file_paths = codeql_status&.workflow_paths
      return if file_paths.blank?
      file_paths.each do |file_path|
        GitHub.logger.info("AutoCodeQL: trying to disable yml file", "code.function": __method__, "gh.repo.id": repository.id)
        fname = File.basename(file_path)
        workflow = T.unsafe(repository).workflows.non_required.find_from_id_or_filename(fname)
        if workflow.nil?
          GitHub.logger.info("AutoCodeQL: could not find workflow #{fname}", "code.function": __method__, "gh.repo.id": repository.id)
          next
        end

        begin
          workflow.disable(actor)
        rescue Actions::Workflow::NotActiveError
          GitHub.logger.info("AutoCodeQL: workflow is already disabled", "code.function": __method__, "gh.repo.id": repository.id)
        end
      end
    end

    def code_scanning_bot
      return @code_scanning_bot if defined?(@code_scanning_bot)

      code_scanning_app = Apps::Privileged.integration(:code_scanning) or fail "code scanning integration not installed!"
      @code_scanning_bot = code_scanning_app.bot
    end

    sig { params(config: Turboscan::Proto::CodeQLConfig, state: String).returns(AutoCodeqlConfig) }
    def deserialize_config(config, state)
      query_suite = deserialize_query_suite(config.query_suite)
      threat_model = deserialize_threat_model(config.threat_model)

      # TS has old non canonical names in the DB, so we need to convert them to make sure we are only using cannonical names
      # TODO: Is this still true?
      languages = language_support.canonical_names(config.languages.map(&:to_s))

      AutoCodeqlConfig.new(
        state: state,
        languages: languages,
        query_suite: query_suite,
        threat_model: threat_model,
        updated_at: config.updated_at,
        runner_label: config.runner_label,
        schedule: nil,
        initial_languages: config.initial_languages,
        creation_trigger: config.trigger,
      )
    end

    def no_codeql_language_left?(removed_languages:)
      removed_languages_canonical = language_support.canonical_names(removed_languages)
      config_languages = turboscan_data.current_config&.languages
      return false if config_languages.nil?

      (config_languages - removed_languages_canonical).empty?
    end

    def deserialize_query_suite(query_suite)
      if query_suite == :QUERY_SUITE_SECURITY_EXTENDED
        "extended"
      elsif query_suite == :QUERY_SUITE_DEFAULT
        "default"
      else
        nil
      end
    end

    def deserialize_threat_model(threat_model)
      if threat_model == :THREAT_MODEL_REMOTE_LOCAL
        "remote_and_local"
      elsif threat_model == :THREAT_MODEL_REMOTE
        "remote"
      else
        nil
      end
    end
  end
end
