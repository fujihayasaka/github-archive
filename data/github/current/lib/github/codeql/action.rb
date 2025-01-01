# typed: true
# frozen_string_literal: true

module GitHub
  class CodeQLAction
    extend T::Helpers
    extend T::Sig

    # Internal organizations used for testing that we exclude from our monitors and SLOs.
    INTERNAL_TESTING_ORGS = %w(accessibility-test-org actions-canary-dependabot actions-canary actions-sauron
      ajhenry-migration api-playground bbq-beets billing-vnext-test-org-1 bookish-potato chocrates-test-org
      client-apps-ec-testing codspace codspaces corycalahan-enterprise-cloud-testing deep-space-9 dependabot-fixtures
      discounts-testing docs-org-dont-delete dsp-testing exp-primer-copilot-cohort-1 ghas-performance-testing
      ghas-results github-iam-demo github-iam github-localization-testing github-maccloud-partners github-ospo-test
      githubbounty githubuserdemo guacamole-bowl hosted-runners-perf import-test-fast import-testing kraiouchkine-ghas
      marcogario-org ncdhhs-poc no-ghas-org octo-org octoshift-review-lab octoshift-staging onboarding-testing-org
      org-workflow-test-organization paper-spa piped-piper-inc properties-game ps-developers-sandbox public-repos-org
      repo-network-incorporated roasted-eggplant sofjones-experiences-test tarotapi tdupoiron-org
      valet-testing-integration vnext-testorg2 vnext-testorg3 vnext-testorg5 voxsteelorg workflow-development-testing
      yellow-jacket-swarm).freeze
    # The earliest supported version of the CodeQL Action.
    MINIMUM_ACTION_VERSION = Semantic::Version.new("2.1.37")
    # The earliest supported version of the CodeQL CLI.
    MINIMUM_CLI_VERSION = Semantic::Version.new("2.11.6")
    ML_POWERED_QUERIES_ALLOWED_STATUSES = ["~0.0.2", "~0.1.0", "~0.2.0", "~0.3.0", "~0.4.0", "latest", "false"].freeze
    # First CodeQL Action release including reliable reporting of `tools_feature_flags_valid`
    # (see https://github.com/github/codeql-action/pull/1538)
    TOOLS_FEATURE_FLAGS_VALID_MIN_VERSION = Semantic::Version.new("2.2.5")

    def self.internal_testing_repo?(repository_nwo)
      INTERNAL_TESTING_ORGS.include?(repository_nwo.split("/").first)
    end

    def self.feature_flags_for(repo, requested_features)
      return nil unless repo

      response = default_version_flags(repo)
      response.merge!(legacy_features_hash(repo))

      if requested_features
        requested_features.each do |feature|
          unless feature.match?(/\A\w+\z/)
            raise ArgumentError.new("Invalid feature name: #{feature}")
          end

          enabled_flag = "codeql_action_#{feature}".to_sym
          disabled_flag = "codeql_action_#{feature}_disabled".to_sym
          response[feature.to_sym] = repo.check_enabled_and_disabled_flags?(enabled_flag, disabled_flag)
        end
      end

      response
    end

    def self.default_version_flags(repo)
      {
        default_codeql_version_2_17_5_enabled: true,
        default_codeql_version_2_17_6_enabled: repo.code_scanning_default_codeql_version_2_17_6_enabled?,
        default_codeql_version_2_18_0_enabled: repo.code_scanning_default_codeql_version_2_18_0_enabled?,
        default_codeql_version_2_18_1_enabled: repo.code_scanning_default_codeql_version_2_18_1_enabled?,
        default_codeql_version_2_18_2_enabled: repo.code_scanning_default_codeql_version_2_18_2_enabled?,
        default_codeql_version_2_18_3_enabled: repo.code_scanning_default_codeql_version_2_18_3_enabled?,
        default_codeql_version_2_18_4_enabled: repo.code_scanning_default_codeql_version_2_18_4_enabled?,
        default_codeql_version_2_18_5_enabled: repo.code_scanning_default_codeql_version_2_18_5_enabled?,
        default_codeql_version_2_18_6_enabled: repo.code_scanning_default_codeql_version_2_18_6_enabled?,
      }
    end

    # The legacy features hash contains entries for two types of feature flags (FF):
    # - all old-style FFs, which will be set to true/false when no longer active (code_scanning_ in DevPortal)
    # - the final value of new-style FFs that are no longer used in the CodeQL Action (codeql_action_ in DevPortal)
    # Note that new-style FFs will only appear in this hash once they are no longer used in the CodeQL Action.
    def self.legacy_features_hash(repo)
      {
        analysis_summary_v2_enabled: true,
        autobuild_direct_tracing_v2: true,
        cli_config_file_enabled: true,
        cli_sarif_merge_enabled: true,
        codeql_java_lombok_enabled: true,
        combine_sarif_files_deprecation_warning_enabled: true,
        cpp_dependency_installation_enabled: repo.code_scanning_cpp_dependency_installation_enabled?,
        cpp_trap_caching_enabled: true,
        database_uploads_enabled: true,
        disable_java_buildless_enabled: repo.code_scanning_disable_java_buildless_enabled?,
        disable_kotlin_analysis_enabled: repo.code_scanning_disable_kotlin_analysis_enabled?,
        disable_python_dependency_installation_enabled: true,
        python_default_is_to_skip_dependency_installation_enabled: true,
        evaluator_fine_grained_parallelism_enabled: true,
        export_code_scanning_config_enabled: true,
        export_diagnostics_enabled: repo.code_scanning_export_diagnostics_enabled?,
        file_baseline_information_enabled: true,
        golang_extraction_reconciliation_enabled: true,
        language_baseline_config_enabled: true,
        lua_tracer_config_enabled: true,
        ml_powered_queries_enabled: false,
        qa_telemetry_enabled: repo.code_scanning_qa_telemetry_enabled?,
        scaling_reserved_ram_enabled: true,
        sublanguage_file_coverage_enabled: true,
        trap_caching_enabled: true,
        upload_failed_sarif_enabled: true,
      }
    end

    # Delegates the status report to all destinations
    def self.report_status(repo, params)
      # Versions of the CodeQL Action 2.1.8 and earlier didn't strip some whitespace from
      # the version string, so we do this here to support old versions of the Action. This can be removed once
      # we stop processing status reports from CodeQL Action 2.1.8 and earlier.
      if "codeql_version".in?(params)
        params["codeql_version"] = params["codeql_version"].strip
      end

      action_deprecated = params["action_version"].present? &&
        params["action_version"].match(Semantic::Version::SemVerRegexp) &&
        Semantic::Version.new(params["action_version"]) < MINIMUM_ACTION_VERSION
      codeql_deprecated = params["codeql_version"].present? &&
        params["codeql_version"].match(Semantic::Version::SemVerRegexp) &&
        Semantic::Version.new(params["codeql_version"]) < MINIMUM_CLI_VERSION

      # Degrade any failures using unsupported versions of the CodeQL Action or CodeQL to configuration errors.
      if params["status"] == "failure" && (action_deprecated || codeql_deprecated)
        params["status"] = "user-error"
      end
      if params["job_status"] == :JOB_STATUS_FAILURE.name && (action_deprecated || codeql_deprecated)
        params["job_status"] = :JOB_STATUS_CONFIGURATION_ERROR
      end

      params["feature_flags_status"] = self.feature_flags_for_telemetry(repo)

      # We serialize all enum values appropriately before sending.
      if params.has_key?("tools_source") && params["tools_source"].is_a?(String)
        params["tools_source"] = Hydro::EntitySerializer.enum_from_string(params["tools_source"])
      end
      if params.has_key?("job_status") && params["job_status"].is_a?(String)
        params["job_status"] = Hydro::EntitySerializer.enum_from_string(params["job_status"])
      end

      self.report_status_to_splunk(params)
      self.report_status_to_hydro(params)
      self.report_status_to_datadog(repo, params)
    end

    def self.report_status_to_splunk(params)
      params = params.dup

      # converts hashes to strings for logging to Splunk, but not Datadog.
      params["feature_flags_status"] = params["feature_flags_status"].to_json
      params["event_reports"] = params["event_reports"].to_json
      params["properties"] = params["properties"].to_json

      # move variable length values to the end of the log line, using delete method
      params["matrix_vars"] = params.delete("matrix_vars") if params["matrix_vars"].present?
      params["cause"] = params.delete("cause") if params["cause"].present?
      params["exception"] = params.delete("exception") if params["exception"].present?

      params.each_pair do |key, value|
        # convert any control characters; \n => \\n etc
        params[key] = value.to_str.strip.dump[1...-1] if value.respond_to?(:to_str)
      end

      # Transform some keys to standard names, but for the rest of the keys,
      # prepend them with "codeql_action.report_status" to safely namespace them all
      params = params.transform_keys do |key|
        case key
        when :repository_id
          "gh.repo.id"
        when :repository_nwo
          "gh.repo.name_with_owner"
        else
          "gh.code_scanning.codeql_action.report_status.#{key}"
        end
      end

      # add class/method info, but at the front of the hash
      params = {
        "code.namespace" => GitHub::CodeQLAction.name,
        "code.function" => __method__.to_s
      }.merge(params)

      GitHub.logger.info("codeql-action status report", params)
    end

    def self.report_status_to_hydro(params)
      GlobalInstrumenter.instrument("code_scanning.status_report", params)
    end

    def self.sanitize_datadog_tag_value(value, possibilities, other = "sanitized-value")
      # If a Datadog tag comes from user input we need to make sure it is only in a finite set of possible values.
      # This is because Datadog charges us based on cardinality, so a malicious user could create a large blow-up in
      # cardinality by providing many possible input values.
      possibilities.include?(value) ? value : other
    end

    def self.feature_flags_for_telemetry(repo)
      {
        "cpp-dependency-installation": repo.code_scanning_cpp_dependency_installation_enabled?,
        "disable-java-buildless": repo.code_scanning_disable_java_buildless_enabled?,
        "disable-kotlin-analysis": repo.code_scanning_disable_kotlin_analysis_enabled?,
        "export-diagnostics": repo.code_scanning_export_diagnostics_enabled?,
        "qa-telemetry": repo.code_scanning_qa_telemetry_enabled?,
      }
    end

    def self.datadog_tags_for_feature_flags(feature_flags_status)
      feature_flags_status.map { |flag, value| "feature-flag-#{flag}:#{value}" }
    end

    def self.report_status_to_datadog(repo, params)
      action_name = self.sanitize_datadog_tag_value(params["action_name"], %w[autobuild finish init upload-sarif init-post resolve-environment])
      status = self.sanitize_datadog_tag_value(params["status"], %w[success failure aborted starting user-error])
      runner_os = self.sanitize_datadog_tag_value(params["runner_os"], %w[Linux Windows macOS])

      tags = [
        "action-name:#{action_name}",
        "status:#{status}",
        "runner-os:#{runner_os}",
      ]

      if params.has_key?("runner_arch")
        runner_arch = self.sanitize_datadog_tag_value(params["runner_arch"], %w[X86 X64 ARM ARM64])
        tags << "runner-arch:#{runner_arch}"
      end
      if params.has_key?("action_version")
        action_version_major = self.sanitize_datadog_tag_value(params["action_version"].split(".").first, %w[1 2 3])
        tags << "action-version-major:#{action_version_major}"
      end
      if params.has_key?("build_mode")
        build_mode = self.sanitize_datadog_tag_value(params["build_mode"], %w[autobuild manual none])
        tags << "build-mode:#{build_mode}"
      end
      if params.has_key?("codeql_version")
        # Only allow a limited number of values to avoid Datadog cardinality blow-up.
        # Here we allow 2.0.0 through 2.19.7 (160 values).
        codeql_version = if params["codeql_version"].match(/\A2\.1?[0-9]\.[0-7]\z/)
          params["codeql_version"]
        else
          "sanitized-value"
        end
        tags << "codeql-version:#{codeql_version}"
      end
      if params.has_key?("languages")
        languages = self.sanitize_datadog_tag_value(params["languages"], %w[cpp csharp go java javascript python ruby swift])
        tags << "languages:#{languages}"
      end
      if params.has_key?("ml_powered_javascript_queries")
        ml_powered_javascript_queries = self.sanitize_datadog_tag_value(
          params["ml_powered_javascript_queries"],
          ML_POWERED_QUERIES_ALLOWED_STATUSES,
          other = "other"
        )
        tags << "ml-powered-javascript-queries:#{ml_powered_javascript_queries}"
      end
      if params["testing_environment"].present? # testing_environment may be set to an empty string.
        testing_environment = self.sanitize_datadog_tag_value(params["testing_environment"], %w[qa-rc qa-rc-1 qa-rc-2 qa-experiment-1 qa-experiment-2 qa-experiment-3 codeql-action-pr-checks])
        tags << "testing-environment:#{testing_environment}"
      end
      if params.has_key?(:repository_nwo) # repository_nwo and repository_id are symbols.
        # Only append the `internal-testing-repo` value if there wasn't already another value set in the status report.
        if !params["testing_environment"].present? && internal_testing_repo?(params[:repository_nwo])
          tags << "testing-environment:internal-testing-repo"
        end

        dogfood_repo = (params[:repository_nwo] == "github/github")
        tags << "dogfood-repo:#{dogfood_repo}"
      end
      if params.has_key?("tools_feature_flags_valid") && params["action_version"].present? &&
          params["action_version"].match(Semantic::Version::SemVerRegexp) &&
          Semantic::Version.new(params["action_version"]) >= TOOLS_FEATURE_FLAGS_VALID_MIN_VERSION
        tools_feature_flags_valid = self.sanitize_datadog_tag_value(params["tools_feature_flags_valid"], [true, false])
        tags << "tools-feature-flags-valid:#{tools_feature_flags_valid}"
      end
      if params.has_key?("tools_source")
        tools_source = self.sanitize_datadog_tag_value(params["tools_source"], [:DOWNLOAD, :LOCAL, :TOOLCACHE, :UNKNOWN])
        tags << "tools-source:#{tools_source}"
      end
      if params.has_key?("job_status")
        job_status = self.sanitize_datadog_tag_value(params["job_status"], [:UNKNOWN, :JOB_STATUS_SUCCESS, :JOB_STATUS_FAILURE, :JOB_STATUS_CONFIGURATION_ERROR])
        tags << "job-status:#{job_status}"
      end
      if params.has_key?("first_party_analysis")
        first_party_analysis = self.sanitize_datadog_tag_value(params["first_party_analysis"], [true, false])
        tags << "first-party-analysis:#{first_party_analysis}"
      end
      if params.has_key?("steady_state_default_setup")
        steady_state_default_setup = self.sanitize_datadog_tag_value(params["steady_state_default_setup"], [true, false])
        tags << "steady-state-default-setup:#{steady_state_default_setup}"
      end

      # Add values of CodeQL Action feature flags
      tags += self.datadog_tags_for_feature_flags(params["feature_flags_status"])

      # Log the success/failure/aborted event with datadog
      if status != "starting"
        GitHub.dogstats.increment("codeql_action.count", tags: tags)
      else
        # Count all `starting` events so we can track the number of killed jobs that were unable to send failure reports
        GitHub.dogstats.increment("codeql_action.starting_count", tags: tags)
      end

      # Log the duration with datadog if we have both started_at and completed_at timestamps
      if "completed_at".in?(params)
        start_date = params["started_at"]
        complete_date = params["completed_at"]
        duration_ms = ((complete_date - start_date) * 24 * 60 * 60 * 1000).to_i
        GitHub.dogstats.distribution("codeql_action.duration", duration_ms, tags: tags)
      end
    end
  end
end
