# typed: true
# frozen_string_literal: true

# AutoCodeql is the github/github component which supports both Code
# Scanning Default Setup and Code Quality in using CodeQL without a
# user-created Actions workflow file.
#
# That said, note that some methods here relate to Code Scanning Advanced
# Setup (e.g. `has_advanced_codeql_setup?`). There are two reasons for this:
# First, the Default Setup logic uses them, and secondly they have Default
# Setup counterparts and it made sense to keep the similar logic in one
# place for now.
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

    # If you add additional options here, you should almost certainly also
    # add their keys to SecurityConfiguration#code_scanning_default_setup_options
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
    sig { override.params(actor: User, options: T::Hash[Symbol, T.untyped]).returns(SecurityProduct::Result) }
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

        # We only need to check security configurations when dealing with Code Scanning.
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
                    feature: :auto_codeql,
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
        response = managed_analyses_helper.disable_managed_analyses(actor:)
        error = nil
        if response.nil? || response.data.nil? || response.error.present?
          error = CodeScanning::AutoCodeqlError.new(ERROR_MESSAGES[:turboscan_offboard_failed], repo_id: repository.id, twirp_error: response&.error)
          return SecurityProduct::Result.new(SecurityProduct::ToggledServiceCollection.create(:auto_codeql, options), error)
        end

        # Exit early if the operation was a noop
        return SecurityProduct::Result.new(SecurityProduct::ToggledServiceCollection.empty) if response.data.noop

        SecurityProduct::Result.new(SecurityProduct::ToggledServiceCollection.create(:auto_codeql, options))
      end
    end

    sig { override.params(options: T.untyped).returns(T::Boolean) }
    def enabled_with_options?(options: {})
      enabled? && options[:runner_type] == configuration.runner_type && options[:runner_label] == configuration.runner_label
    end

    def enabled?
      log_timing do
        managed_analyses_helper.enabled?
      end
    end

    # would_be_enabled_if_prerequisites_were_met? bypasses prerequisute checks.
    # It is only used during transition from bundled to unbundled sku when the system state
    # can be inconsistent.
    sig { returns(T::Boolean) }
    def would_be_enabled_if_prerequisites_were_met?
      managed_analyses_helper.enabled_ignoring_prerequisites?
    end

    def disabled?
      managed_analyses_helper.onboarding_status == "disabled"
    end

    # TODO: Rename this to `onboarding?`
    def enabling?
      managed_analyses_helper.enabling?
    end

    def updating?
      managed_analyses_helper.updating?
    end

    def onboarding_status
      managed_analyses_helper.onboarding_status
    end

    def waiting?
      managed_analyses_helper.waiting?
    end

    # Returns whether the repository is onboarded to AutoCodeQL.
    # If we do not have data about the repository, we consider AutoCodeQL disabled.
    def has_failed_update?
      managed_analyses_helper.has_failed_update?
    end

    # Returns the id of the latest debuggable workflow run from default setup
    # This will be for a configuration that is validating or has recently failed validation
    def debuggable_auto_codeql_run_id
      workflow_run_id = managed_analyses_helper.get_workflow_run_id
      workflow_run_id.to_s unless workflow_run_id.nil? || workflow_run_id.zero?
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

    # Checks if we should consider the repo as having a manual CodeQL YAML workflow.
    def has_manual_codeql_workflow?
      has_codeql_setup? && codeql_status&.has_recent_active_manual_workflow?
    end

    # Checks if we should consider the repo as having CodeQL running not via Default Setup.
    # Note that unlike `has_manual_codeql_workflow?`, this checks for _any_ non-Default-Setup
    # case, whereas `has_manual_codeql_workflow?` only considers the YAML case.
    def has_advanced_codeql_setup?
      has_codeql_setup? && codeql_status&.has_recent_advanced_setup_run?
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
      return unless self.class.required_services_enabled?(repository)

      # TODO: instead of bubbling up ts error as it is, should we wrap it with a more generic error message?
      managed_analyses_helper.error_message
    end

    def can_enable?(actor:, options:)
      log_timing do
        error = CodeScanning::Status.validate_prerequisites(repository, actor, options: options.merge(include_default_setup_prerequisites: true))
        return SecurityProduct::Result.new(false, error) if error.present?

        if !!options.dig(:fail_on_manual_workflow?) && has_advanced_codeql_setup?
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
        "Code scanning default setup can only be enabled if Actions is enabled. GitHub Actions is disabled on this repository by an enterprise or organization policy. Please ask your organization administrator to enable Actions."
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
        additional_info = "."
        additional_info = ": #{error}" if Rails.env.development?
        "Failed to toggle code scanning default setup#{additional_info}"
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
      managed_analyses_helper.update_languages(languages_to_add: languages_to_add, languages_to_delete: languages_to_delete)
      nil
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
        if response.blank? || response.error.present? || response.data.nil? || response.data.analyses.empty?
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

    sig { returns(CodeScanning::ManagedAnalysesEnablement) }
    def managed_analyses_helper
      @managed_analyses_helper ||= begin
        CodeScanning::ManagedAnalysesEnablement.new(repository, :CODE_SCANNING, !self.class.required_services_enabled?(repository))
      end
    end

    sig { returns(ManagedAnalysesConfig) }
    def configuration
      managed_analyses_helper.configuration
    end

    def debuggable_configuration
      managed_analyses_helper.debuggable_configuration
    end

    def next_scheduled_run_at
      managed_analyses_helper.next_scheduled_run_at
    end

    def is_repo_active?
      managed_analyses_helper.is_repo_active?
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

    sig { returns(ManagedAnalysesConfig) }
    def recommended_configuration
      config = recommended_configuration_without_runner_labels
      config.runner_label = default_runner_label

      config
    end

    # The recommended configuration but without setting a recommended runner label.
    # This is to avoid the expensive check to determine whether runners with the `code-scanning`
    # label are available.
    # Use `recommended_configuration` if you need runner label information.
    sig { returns(ManagedAnalysesConfig) }
    def recommended_configuration_without_runner_labels
      CodeScanning::ManagedAnalysesConfig.new(
        state: "not-configured",
        languages: managed_analyses_helper.language_support.supported_languages,
        query_suite: self.class.recommended_query_suite(repository),
        threat_model: "remote",
        updated_at: nil,
        schedule: nil,
        initial_languages: [],
        creation_trigger: nil,
        runner_label: nil,
        code_quality_enabled: false,
        )
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

    # In general, disabling a service should result in an attached security configuration
    # being removed if that configuration had the service set as enabled. However, if
    # AutoCodeQL is being disabled as part of a switch to Advanced Setup, don't try and
    # remove the security configuration.
    sig { override.params(options: T::Hash[Symbol, T.untyped]).returns(T::Boolean) }
    def skip_removing_configuration_on_disable?(options:)
      options.fetch(:switching_setup_types, false)
    end

    private

    def publish_auto_codeql_instrumentation(action:, actor:, query_suite: nil, threat_model: nil, languages: nil)
      payload = {
        actor: actor,
        repo: repository
      }

      payload[:org] = repository.organization if repository.in_organization?
      payload[:query_suite] = query_suite if query_suite.present?
      payload[:threat_model] = threat_model if threat_model.present?
      payload[:languages] = languages if languages.present?

      GitHub.instrument("repo.codeql_#{action}", payload)
    end

    sig { params(actor: User, options: T::Hash[Symbol, T.untyped]).returns(SecurityProduct::Result) }
    def do_enable(actor:, options: {})
      error_symbol = update_runner_label_options(options: options)
      if !error_symbol.nil?
        return SecurityProduct::Result.new(SecurityProduct::ToggledServiceCollection.create(to_sym, options), error_symbol)
      end

      config = recommended_configuration_without_runner_labels.with_options(options)

      resp = managed_analyses_helper.enable_managed_analysis(actor:, config:)
      error = nil
      if resp.nil? || resp.data.nil? || resp.error.present?
        error = CodeScanning::AutoCodeqlError.new(ERROR_MESSAGES[:turboscan_onboard_failed], repo_id: repository.id, twirp_error: resp&.error)
        return SecurityProduct::Result.new(SecurityProduct::ToggledServiceCollection.create(:auto_codeql, options), error)
      end

      options[:workflow_run_id] = resp.data.workflow_run_id

      if !resp.data.noop
        dismiss_yml(actor: actor)
      else
        options[:noop] = true
      end

      SecurityProduct::Result.new(SecurityProduct::ToggledServiceCollection.create(:auto_codeql, options))
    end

    sig { params(actor: User, options: T::Hash[Symbol, T.untyped]).returns(SecurityProduct::Result) }
    def do_update(actor:, options:)
      config = CodeScanning::ManagedAnalysesConfig.from_hash(options)

      case options[:runner_type].to_s
      when "standard" then
        update_runner_label = true
        config.runner_label = nil
      when "labeled" then
        if options[:runner_label].present? && actions_runner_checker&.labelled_runners_available?(desired_labels: [options[:runner_label]], calling_context_only_for_metrics: :auto_codeql_update)
          update_runner_label = true
          config.runner_label = options[:runner_label]
        else
          return SecurityProduct::Result.new(SecurityProduct::ToggledServiceCollection.create(to_sym, options), :runner_not_available)
        end
      else
        update_runner_label = false
      end

      response = managed_analyses_helper.update_managed_analysis(actor:, config:, update_runner_label:)
      if response&.data.nil? || response&.error.present?
        error_message = ERROR_MESSAGES[:turboscan_update_failed]

        if response&.error&.code == :already_exists
          error_message = "Configuration update already in progress"
          options[:already_exists] = true
        end

        error = CodeScanning::AutoCodeqlError.new(error_message, repo_id: repository.id, twirp_error: response&.error)
        return SecurityProduct::Result.new(SecurityProduct::ToggledServiceCollection.create(:auto_codeql, options), error)
      end

      if response&.data&.noop
        options[:noop] = true
      end

      options[:workflow_run_id] = response&.data&.workflow_run_id

      SecurityProduct::Result.new(SecurityProduct::ToggledServiceCollection.create(:auto_codeql, options))
    end

    def dismiss_notice_key(repository_id:, user_id:)
      "#{DISMISSED_AUTO_CODEQL_NOTICE}.#{repository_id}.#{user_id}.#{debuggable_auto_codeql_run_id}"
    end

    # This method modifies the options in-place to include the runner label information.
    # It also checks for the availability of the labeled runner.
    sig { params(options: T::Hash[Symbol, T.untyped]).returns(T.nilable(Symbol)) }
    def update_runner_label_options(options:)
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
          nil
        else
          :runner_not_available
        end
      end
    end

    def dismiss_yml(actor:)
      return unless has_manual_codeql_workflow?

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

    sig { params(config: Turboscan::Proto::CodeQLConfig, state: String).returns(ManagedAnalysesConfig) }
    def deserialize_config(config, state)
      query_suite = deserialize_query_suite(config.query_suite)
      threat_model = deserialize_threat_model(config.threat_model)

      # TS has old non canonical names in the DB, so we need to convert them to make sure we are only using cannonical names
      # TODO: Is this still true?
      languages = managed_analyses_helper.language_support.canonical_names(config.languages.map(&:to_s))

      ManagedAnalysesConfig.new(
        state: state,
        languages: languages,
        query_suite: query_suite,
        threat_model: threat_model,
        updated_at: config.updated_at,
        runner_label: config.runner_label,
        schedule: nil,
        initial_languages: config.initial_languages,
        creation_trigger: config.trigger,
        code_quality_enabled: config.code_quality_enabled,
      )
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
