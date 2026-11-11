# typed: strict
# frozen_string_literal: true

module CodeScanning
  class ManagedAnalysesEnablement
    sig { params(repository: Repository, feature: Symbol, disabled_by_prerequisites: T::Boolean).void }
    def initialize(repository, feature, disabled_by_prerequisites)
      @repository = repository
      @feature = feature
      @disabled_by_prerequisites = disabled_by_prerequisites
    end

    sig { returns(String) }
    def onboarding_status
      @onboarding_status ||= T.let(
        # We are using an explicit disabled check, as we do want the behavior to be affected if the prerequisites are not met.
        if @disabled_by_prerequisites
          "disabled"
        else
          turboscan_data.status_v2.to_s.downcase
        end,
        T.nilable(String)
      )
    end

    sig { returns(T::Boolean) }
    def disabled?
      onboarding_status == "disabled"
    end

    # TODO: Rename this to `onboarding?`
    sig { returns(T::Boolean) }
    def enabling?
      onboarding_status == "onboarding"
    end

    sig { returns(T::Boolean) }
    def updating?
      onboarding_status == "updating"
    end

    sig { returns(T::Boolean) }
    def waiting?
      onboarding_status == "waiting"
    end

    sig { returns(T.nilable(Time)) }
    def next_scheduled_run_at
      t = turboscan_data.next_scheduled_run_at
      t.present? ? t.to_time : nil
    end

    sig { returns(T::Boolean) }
    def enabled?
      %w[waiting onboarding stable updating].include? onboarding_status
    end

    # Returns whether Turboscan considers the managed analysis enabled, regardless of
    # whether prerequisites are currently met.
    sig { returns(T::Boolean) }
    def enabled_ignoring_prerequisites?
      %w[waiting onboarding stable updating].include? onboarding_status_ignoring_prerequisites
    end

    sig { returns(String) }
    def onboarding_status_ignoring_prerequisites
      @onboarding_status_ignoring_prerequisites ||= T.let(
        turboscan_data.status_v2.to_s.downcase,
        T.nilable(String)
      )
    end

    sig { returns(T::Boolean) }
    def has_failed_update?
      turboscan_data.has_failed_update
    end

    sig { returns(T.nilable(String)) }
    def error_message
      turboscan_data.error
    end

    sig { returns(T.nilable(CodeScanning::ManagedAnalysesConfig)) }
    def debuggable_configuration
      cfg = turboscan_data.debuggable_config
      return if cfg.blank?

      state = has_failed_update? ? "not-configured" : "configured"
      deserialize_config(cfg, state)
    end

    sig do
      returns(
        Turboscan::Proto::GetManagedAnalysisInfoResponse
      )
    end
    def turboscan_data
      @turboscan_response ||= T.let(begin
        response = GitHub::Turboscan::ManagedAnalyses.get_managed_analysis_info(
          repository_id: @repository.id,
          feature: @feature,
        )
        if response.blank? || response.error.present? || response.data.nil?
          raise CodeScanning::AutoCodeqlError.new("Error fetching #{@feature} data from turboscan", repo_id: @repository.id, twirp_error: response&.error)
        else
          response.data
        end
      end, T.nilable(Turboscan::Proto::GetManagedAnalysisInfoResponse))
    end

    sig { returns(T::Boolean) }
    def is_repo_active?
      turboscan_data.active_repo
    end

    sig { returns(T.nilable(Integer)) }
    def get_workflow_run_id
      workflow_run_id = turboscan_data.debuggable_workflow_run_id
      return if workflow_run_id.nil?

      Integer(workflow_run_id)
    rescue StandardError => error
      GitHub.logger.warn(
        "Failed to retrieve debuggable workflow run id",
        "code.namespace": "CodeScanning::ManagedAnalysesEnablement",
        "code.function": "get_workflow_run_id",
        "code.feature": @feature,
        "gh.repo.id": @repository.id,
        "code.error.class": error.class.name,
        "code.error.message": error.message,
      )
      nil
    end

    sig { params(query_suite: T.untyped).returns(T.nilable(String)) }
    def deserialize_query_suite(query_suite)
      if query_suite == :QUERY_SUITE_SECURITY_EXTENDED
        "extended"
      elsif query_suite == :QUERY_SUITE_DEFAULT
        "default"
      else
        nil
      end
    end

    sig { params(threat_model: T.untyped).returns(T.nilable(String)) }
    def deserialize_threat_model(threat_model)
      if threat_model == :THREAT_MODEL_REMOTE_LOCAL
        "remote_and_local"
      elsif threat_model == :THREAT_MODEL_REMOTE
        "remote"
      else
        nil
      end
    end

    sig { params(config: Turboscan::Proto::CodeQLConfig, state: String).returns(CodeScanning::ManagedAnalysesConfig) }
    def deserialize_config(config, state)
      query_suite = deserialize_query_suite(config.query_suite)
      threat_model = deserialize_threat_model(config.threat_model)

      # TS has old non canonical names in the DB, so we need to convert them to make sure we are only using canonical names
      # TODO: Is this still true?
      languages = language_support.canonical_names(config.languages.map(&:to_s))

      CodeScanning::ManagedAnalysesConfig.new(
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

    sig { returns(CodeScanning::ManagedAnalysesLanguageSupport) }
    def language_support
      @language_support ||= T.let(CodeScanning::ManagedAnalysesLanguageSupport.new(@repository, @feature), T.nilable(CodeScanning::ManagedAnalysesLanguageSupport))
    end

    sig { returns(CodeScanning::ManagedAnalysesConfig) }
    def configuration
      onboarding_state = onboarding_status
      if onboarding_state == "disabled"
        return CodeScanning::ManagedAnalysesConfig.new(
          state: "not-configured",
          languages: [],
          query_suite: nil,
          threat_model: nil,
          updated_at: nil,
          schedule: nil,
          initial_languages: [],
          creation_trigger: nil,
          runner_label: nil,
          code_quality_enabled: false,
        )
      elsif onboarding_state == "waiting" || onboarding_state == "onboarding" || onboarding_state == "enabling"
        managed_analysis_info = turboscan_data

        # The repo is enabled but we do not have a current config yet.
        # We return only the information that is defined at the repo level.
        return CodeScanning::ManagedAnalysesConfig.new(
          state: "configured",
          languages: [],
          query_suite: deserialize_query_suite(managed_analysis_info.query_suite),
          threat_model: deserialize_threat_model(managed_analysis_info.threat_model),
          updated_at: nil, # TODO: Shall we have a timestamp here?
          schedule: nil,
          initial_languages: [],
          creation_trigger: nil,
          runner_label: managed_analysis_info.runner_label,
          code_quality_enabled: managed_analysis_info.code_quality_enabled,
        )
      elsif onboarding_state == "stable" || onboarding_state == "updating" || onboarding_state == "enabled"
        ts_cfg = turboscan_data.current_config
        raise CodeScanning::AutoCodeqlError.new("No current config in Turboscan data", repo_id: @repository.id) if ts_cfg.nil?
        config = deserialize_config(ts_cfg, "configured")
        config.schedule = "weekly" if is_repo_active?
        return config
      end

      # We should have covered all the cases
      raise CodeScanning::AutoCodeqlError.new("Unexpected onboarding status: #{onboarding_state}", repo_id: @repository.id)
    end

    sig { params(actor: User, config: CodeScanning::ManagedAnalysesConfig).returns(T.nilable(Twirp::ClientResp[Turboscan::Proto::EnableResponse])) }
    def enable_managed_analysis(actor:, config:)
      # On GHES we need the old global ids to onboard
      repo_global_id = GitHub.enterprise? ? @repository.global_relay_id : @repository.next_global_id
      actor_global_id = GitHub.enterprise? ? actor.global_relay_id : actor.next_global_id

      request = {
        repository_id: @repository.id,
        global_repository_id: repo_global_id,
        feature: @feature,
        enabled_by_actor_grid: actor_global_id,
        enabled_by_actor_login: actor.login,
        default_ref: @repository.default_branch_ref&.qualified_name,
        owner_id: @repository.owner_id,
        supported_languages: language_support.supported_languages,
        has_kotlin: language_support.has_kotlin?,
        codeql_packs: CodeScanningOrgConfigurations.codeql_packs(@repository),
      }
      request[:runner_label] = config.runner_label if config.runner_label.present?

      request[:selected_languages] = config.languages
      query_suite = config.query_suite
      request[:query_suite] = protobuf_query_suite(query_suite) if query_suite.present?
      threat_model = config.threat_model
      request[:threat_model] = protobuf_threat_model(threat_model) if threat_model.present?

      if scan_inactive_repos_enabled_for_org?
        request[:scan_when_inactive] = true
      end

      resp = GitHub::Turboscan::ManagedAnalyses.enable(request)
      if !resp&.data&.noop
        clear_memoized_turboscan_data
        if !resp&.data.nil? && !resp&.error.present?
          publish_codeql_instrumentation(action: "enabled", actor: actor, query_suite: query_suite, threat_model: threat_model, languages: request[:selected_languages])
        end
      end
      resp
    end

    sig { params(actor: User, config: CodeScanning::ManagedAnalysesConfig, update_runner_label: T::Boolean).returns(T.nilable(Twirp::ClientResp[Turboscan::Proto::UpdateResponse])) }
    def update_managed_analysis(actor:, config:, update_runner_label:)
      request = {
        repository_id: @repository.id,
        feature: @feature,
        global_actor_id: GitHub.enterprise? ? actor.global_relay_id : actor.next_global_id,
        actor_login: actor.display_login,
        default_ref: @repository.default_branch_ref&.qualified_name,
        owner_id: @repository.owner_id,
        supported_languages: language_support.supported_languages,
        codeql_packs: CodeScanningOrgConfigurations.codeql_packs(@repository),
        runner_type: Turboscan::Proto::UpdateRequest::RunnerType::RUNNER_TYPE_UNCHANGED,
      }

      if update_runner_label && config.runner_label.present?
        request[:runner_type] = Turboscan::Proto::UpdateRequest::RunnerType::RUNNER_TYPE_LABELED
        request[:runner_label] = config.runner_label
      elsif update_runner_label && config.runner_label.blank?
        request[:runner_type] = Turboscan::Proto::UpdateRequest::RunnerType::RUNNER_TYPE_STANDARD
      end

      request[:languages] = config.languages if config.languages.present?

      # config.languages == nil ==> There was no change to the selected languages
      # config.languages == [] ==> All the languages have been deselected
      # config.languages == ["x", "y"] ==> Only x and y should now be selected
      request[:selected_languages] = { languages: config.languages } if !config.languages.nil?

      request[:query_suite] = protobuf_query_suite(config.query_suite) if config.query_suite.present?
      request[:threat_model] = protobuf_threat_model(config.threat_model) if config.threat_model.present?

      request[:code_quality_enabled] = config.code_quality_enabled if config.code_quality_enabled.present?

      response = GitHub::Turboscan::ManagedAnalyses.update(request)

      if !response&.data&.noop
        clear_memoized_turboscan_data
        if !response&.data.nil? && !response&.error.present?
          publish_codeql_instrumentation(action: "updated", actor: actor, query_suite: config.query_suite, threat_model: config.threat_model, languages: request[:languages])
        end
      end
      response
    end

    sig { params(languages_to_add: T::Array[String], languages_to_delete: T::Array[String]).void }
    def update_languages(languages_to_add:, languages_to_delete:)
      # If there is an update already in progress, we raise in order to retry the job a bit later
      if updating?
        raise AutoCodeqlError.new("Config update already in progress", repo_id: @repository.id)
      end

      response = GitHub::Turboscan::ManagedAnalyses.update_languages(
        repository_id: @repository.id,
        languages_added: languages_to_add,
        languages_removed: languages_to_delete,
        default_ref: @repository.default_branch_ref&.qualified_name,
        owner_id: @repository.owner_id,
        supported_languages: language_support.supported_languages,
        codeql_packs: CodeScanningOrgConfigurations.codeql_packs(@repository),
        feature: @feature,
      )

      if response.nil? || response.data.nil? || response.error.present?
        Failbot.push(twirp_error: response&.error)

        # If a new update was triggered then we skip the retry
        # because we can assume that the update already accounts for the updated list of languages
        unless response&.error&.code == :already_exists
          raise AutoCodeqlError.new(
            "Turboscan update_language endpoint failed for #{@feature} LanguageUpdateJob",
            repo_id: @repository.id,
            twirp_error: response&.error
          )
        end

        GitHub.logger.info(response&.error&.msg,
          "code.namespace": "CodeScanning::ManagedAnalysesEnablement",
          "code.function": "update_languages",
          "gh.repo.id": @repository.id,
        )
      else
        stat_name = @feature == :CODE_QUALITY ? "code_scanning.code_quality_language_update" : "code_scanning.auto_codeql_language_update"
        GitHub.dogstats.increment(
          stat_name,
          tags: ["adds:#{languages_to_add.count}", "deletes:#{languages_to_delete.count}"]
        )
      end
    end

    sig { params(action: String, actor: User, query_suite: T.untyped, threat_model: T.untyped, languages: T.nilable(T::Array[String])).void }
    def publish_codeql_instrumentation(action:, actor:, query_suite: nil, threat_model: nil, languages: nil)
      payload = {
        actor: actor,
        repo: @repository
      }

      payload[:org] = @repository.organization if @repository.in_organization?
      payload[:query_suite] = query_suite if query_suite.present?
      payload[:threat_model] = threat_model if threat_model.present?
      payload[:languages] = languages if languages.present?

      case @feature
      when :CODE_QUALITY
        GitHub.instrument("repo.code_quality_#{action}", payload)
      when :CODE_SCANNING
        GitHub.instrument("repo.codeql_#{action}", payload)
      end
    end

    sig { returns(NilClass) }
    def clear_memoized_turboscan_data
      @turboscan_response = nil
    end

    sig { params(query_suite: T.untyped).returns(Symbol) }
    def protobuf_query_suite(query_suite)
      if query_suite == "default"
        :QUERY_SUITE_DEFAULT
      elsif query_suite == "extended"
        :QUERY_SUITE_SECURITY_EXTENDED
      else
        :QUERY_SUITE_UNSPECIFIED
      end
    end

    sig { params(threat_model: T.untyped).returns(Symbol) }
    def protobuf_threat_model(threat_model)
      if threat_model == "remote_local" || threat_model == "remote_and_local"
        :THREAT_MODEL_REMOTE_LOCAL
      elsif threat_model == "remote"
        :THREAT_MODEL_REMOTE
      else
        :THREAT_MODEL_UNSPECIFIED
      end
    end

    sig { params(actor: User).returns(T.nilable(Twirp::ClientResp[Turboscan::Proto::DisableResponse])) }
    def disable_managed_analyses(actor:)
      clear_memoized_turboscan_data # Invalidate existing data as this is action can change the state of Turboscan

      request = {
        repository_id: @repository.id,
        feature: @feature,
      }

      response = GitHub::Turboscan::ManagedAnalyses.disable(request)

      if !response&.error.present? && !response&.data.nil? && !response&.data&.noop
        publish_codeql_instrumentation(action: "disabled", actor: actor)
      end
      response
    end

    sig { returns(T::Boolean) }
    def is_private_preview_config?
      # Private Preview customers will be using Code Scanning configurations with code_quality_enabled set to true
      @feature == :CODE_QUALITY && turboscan_data.feature == :CODE_SCANNING
    end

    sig { params(languages: T::Array[String], workflow_run_id: T.nilable(Integer)).returns(T.nilable(CodeScanning::ManagedAnalysesError)) }
    def adjust(languages, workflow_run_id = nil)
      # Ensure canonical representation of the languages
      languages = language_support.canonical_names(languages)

      request = {
        repository_id: @repository.id,
        owner_id: @repository.owner_id,
        languages: languages,
        workflow_run_id: workflow_run_id || 0
      }

      response = GitHub::Turboscan::ManagedAnalyses.adjust(request)
      if response&.data.nil? || response&.error.present?
        return ManagedAnalysesError.new(
          "Turboscan adjust configuration endpoint failed",
          twirp_error: response&.error,
        )
      end

      # Invalidate the memoized turboscan data
      clear_memoized_turboscan_data

      nil
    end

    sig { returns(T::Boolean) }
    def scan_inactive_repos_enabled_for_org?
      return false unless @feature == :CODE_SCANNING
      return false unless @repository.in_organization?

      organization = T.must(@repository.organization)
      return false unless CodeScanning::ScanInactiveRepos.feature_flag_enabled_for?(organization)

      CodeScanningOrganizationConfig.new(organization:).code_scanning_scan_inactive_repos_settings_enabled?
    end

    private :turboscan_data
  end
end
