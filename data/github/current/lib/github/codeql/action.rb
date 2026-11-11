# typed: true
# frozen_string_literal: true

require "github/codeql/features"

module GitHub
  module CodeQL
    class Action
      extend T::Helpers

      # Internal organizations used for testing that we exclude from our monitors and SLOs.
      INTERNAL_TESTING_ORGS = %w(accessibility-test-org actions-canary-dependabot actions-canary actions-sauron
        ajhenry-migration api-playground bbq-beets billing-vnext-test-org-1 bookish-potato chocrates-test-org
        client-apps-ec-testing codeql-dca-runners codspace codspaces corycalahan-enterprise-cloud-testing deep-space-9
        dependabot-fixtures discounts-testing docs-org-dont-delete dsp-testing exp-primer-copilot-cohort-1
        ghas-performance-testing ghas-results github-iam-demo github-iam github-localization-testing
        github-maccloud-partners github-ospo-test githubbounty githubuserdemo guacamole-bowl hosted-runners-perf
        import-test-fast import-testing kraiouchkine-ghas marcogario-org ncdhhs-poc no-ghas-org octo-org
        octoshift-review-lab octoshift-staging onboarding-testing-org org-workflow-test-organization paper-spa
        piped-piper-inc properties-game ps-developers-sandbox public-repos-org repo-network-incorporated
        roasted-eggplant sofjones-experiences-test tarotapi tdupoiron-org valet-testing-integration vnext-testorg2
        vnext-testorg3 vnext-testorg5 voxsteelorg workflow-development-testing yellow-jacket-swarm).freeze
      # The earliest supported version of the CodeQL Action.
      MINIMUM_ACTION_VERSION = Semantic::Version.new("3.28.6")
      # The earliest supported version of the CodeQL CLI.
      MINIMUM_CLI_VERSION = Semantic::Version.new("2.20.3")
      ML_POWERED_QUERIES_ALLOWED_STATUSES = ["~0.0.2", "~0.1.0", "~0.2.0", "~0.3.0", "~0.4.0", "latest", "false"].freeze
      # First CodeQL Action release including reliable reporting of `tools_feature_flags_valid`
      # (see https://github.com/github/codeql-action/pull/1538)
      TOOLS_FEATURE_FLAGS_VALID_MIN_VERSION = Semantic::Version.new("2.2.5")
      # The names of all known CodeQL actions
      ACTION_NAMES = %w[autobuild finish init upload-sarif init-post resolve-environment setup-codeql start-proxy].freeze
      # Known languages for telemetry.
      KNOWN_LANGUAGES = %w[actions cpp csharp go java javascript python ruby rust swift].freeze
      # Known languages for which dependency caching is supported.
      DEPENDENCY_CACHING_LANGUAGES = %w[csharp go java].freeze
      # Registry types we support for CodeQL.
      SUPPORTED_REGISTRY_TYPES = %w(maven_repository nuget_feed npm_registry python_index rubygems_server
        cargo_registry goproxy_server git_source).freeze
      # Analysis kinds we support.
      ANALYSIS_KINDS = %w[code-scanning code-quality risk-assessment].freeze

      # Captures the following enablement errors:
      # - Code Security must be enabled for this repository to use code scanning.
      # - Advanced Security must be enabled for this repository to use code scanning.
      # - Please verify that the necessary features are enabled: Code Security must be enabled
      #   for this repository to use code scanning. - https://docs.github.com/rest
      # - Code scanning is not enabled for this repository. Please enable code scanning in the
      #   repository settings. - https://docs.github.com/rest
      KNOWN_ENABLEMENT_CONFIGURATION_ERROR_REGEX = /((Code|Advanced) Security must be|Code scanning is not) enabled for this repository/i.freeze

      def self.internal_testing_repo?(repository_nwo)
        INTERNAL_TESTING_ORGS.include?(repository_nwo.split("/").first)
      end

      def self.feature_flags_for(repo, requested_features)
        return nil unless repo

        response = default_version_flags(repo)
        response.merge!(inactive_features_hash(repo))

        if requested_features
          requested_features.each do |feature|
            unless feature.match?(/\A\w+\z/)
              raise ArgumentError.new("Invalid feature name: #{feature}")
            end

            # Don't override flags that have already been graduated in inactive_features_hash
            feature_sym = feature.to_sym
            next if response.key?(feature_sym)

            enabled_flag = "codeql_action_#{feature}".to_sym
            disabled_flag = "codeql_action_#{feature}_disabled".to_sym
            response[feature_sym] = repo.check_enabled_and_disabled_flags?(enabled_flag, disabled_flag)
          end
        end

        response
      end

      sig { params(repo: Repository).returns(T::Hash[Symbol, T::Boolean]) }
      def self.default_version_flags(repo)
        {
          default_codeql_version_2_23_9_enabled: true,
          default_codeql_version_2_24_0_enabled: CodeQL::Features.default_codeql_version_2_24_0_enabled?(repo),
          default_codeql_version_2_24_1_enabled: CodeQL::Features.default_codeql_version_2_24_1_enabled?(repo),
          default_codeql_version_2_24_2_enabled: CodeQL::Features.default_codeql_version_2_24_2_enabled?(repo),
          default_codeql_version_2_24_3_enabled: CodeQL::Features.default_codeql_version_2_24_3_enabled?(repo),
          default_codeql_version_2_24_4_enabled: CodeQL::Features.default_codeql_version_2_24_4_enabled?(repo),
          default_codeql_version_2_24_5_enabled: CodeQL::Features.default_codeql_version_2_24_5_enabled?(repo),
          default_codeql_version_2_24_6_enabled: CodeQL::Features.default_codeql_version_2_24_6_enabled?(repo),
          default_codeql_version_2_24_7_enabled: CodeQL::Features.default_codeql_version_2_24_7_enabled?(repo),
          default_codeql_version_2_24_8_enabled: CodeQL::Features.default_codeql_version_2_24_8_enabled?(repo),
          default_codeql_version_2_24_9_enabled: CodeQL::Features.default_codeql_version_2_24_9_enabled?(repo),
          default_codeql_version_2_25_0_enabled: CodeQL::Features.default_codeql_version_2_25_0_enabled?(repo),
          default_codeql_version_2_25_1_enabled: CodeQL::Features.default_codeql_version_2_25_1_enabled?(repo),
          default_codeql_version_2_25_2_enabled: CodeQL::Features.default_codeql_version_2_25_2_enabled?(repo),
          default_codeql_version_2_25_3_enabled: CodeQL::Features.default_codeql_version_2_25_3_enabled?(repo),
          default_codeql_version_2_25_4_enabled: CodeQL::Features.default_codeql_version_2_25_4_enabled?(repo),
          default_codeql_version_2_25_5_enabled: CodeQL::Features.default_codeql_version_2_25_5_enabled?(repo),
          default_codeql_version_2_25_6_enabled: CodeQL::Features.default_codeql_version_2_25_6_enabled?(repo),
          default_codeql_version_2_25_7_enabled: CodeQL::Features.default_codeql_version_2_25_7_enabled?(repo),
          default_codeql_version_2_25_8_enabled: CodeQL::Features.default_codeql_version_2_25_8_enabled?(repo)
        }
      end

      # The inactive features hash contains entries for two types of feature flags (FF):
      # - all old-style FFs, which will be set to true/false when no longer active (code_scanning_ in DevPortal)
      # - the final value of new-style FFs that are no longer used in the CodeQL Action (codeql_action_ in DevPortal)
      # Note that new-style FFs will only appear in this hash once they are no longer used in the CodeQL Action.
      def self.inactive_features_hash(repo)
        {
          analysis_summary_v2_enabled: true,
          analyze_use_new_upload: true,
          artifact_v4_upgrade: true,
          autobuild_direct_tracing_v2: true,
          cli_config_file_enabled: true,
          cli_sarif_merge_enabled: true,
          codeql_java_lombok_enabled: true,
          combine_sarif_files_deprecation_warning_enabled: true,
          cpp_build_mode_none: true,
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
          extract_to_toolcache: true,
          file_baseline_information_enabled: true,
          golang_extraction_reconciliation_enabled: true,
          java_minimize_dependency_jars: true,
          language_baseline_config_enabled: true,
          lua_tracer_config_enabled: true,
          ml_powered_queries_enabled: false,
          qa_telemetry_enabled: repo.code_scanning_qa_telemetry_enabled?,
          resolve_supported_languages_using_cli: true,
          rust_analysis: true,
          scaling_reserved_ram_enabled: true,
          sublanguage_file_coverage_enabled: true,
          trap_caching_enabled: true,
          upload_failed_sarif_enabled: true,
          zstd_bundle: true,
          zstd_bundle_streaming_extraction: true,
        }
      end

      # Tries to determine whether a given status report is for Code Scanning or not.
      sig { params(params: T.untyped).returns(T::Boolean) }
      def self.is_code_scanning_status_report?(params)
        if "analysis_kinds".in?(params) && params["analysis_kinds"].is_a?(String)
          return params["analysis_kinds"].include?("code-scanning")
        end

        # If we don't have the `analysis_kinds` field in the status report,
        # assume that this is for Code Scanning.
        true
      end

      sig { params(status: String).returns(T::Boolean) }
      def self.is_unsuccessful_status?(status)
        status == "failure" || status == "aborted" || status == "user-error"
      end

      sig { params(job_status: String).returns(T::Boolean) }
      def self.is_unsuccessful_job_status?(job_status)
        job_status == :JOB_STATUS_FAILURE.name || job_status == :JOB_STATUS_CONFIGURATION_ERROR.name
      end

      # Delegates the status report to all destinations
      sig { params(repo: Repository, params: T.untyped).void }
      def self.report_status(repo, params)
        # Versions of the CodeQL Action 2.1.8 and earlier didn't strip some whitespace from
        # the version string, so we do this here to support old versions of the Action. This can be removed once
        # we stop processing status reports from CodeQL Action 2.1.8 and earlier.
        if "codeql_version".in?(params)
          params["codeql_version"] = params["codeql_version"].strip
        end

        action_deprecated = self.action_version_below?(params, MINIMUM_ACTION_VERSION)
        codeql_deprecated = params["codeql_version"].present? &&
          params["codeql_version"].match(Semantic::Version::SemVerRegexp) &&
          Semantic::Version.new(params["codeql_version"]) < MINIMUM_CLI_VERSION

        # Degrade the following failures to configuration errors:
        # - Any failure using an unsupported version of the CodeQL Action
        # - Any failure using an unsupported version of the CodeQL CLI
        # - Known configuration errors
        is_config_error = action_deprecated || codeql_deprecated || self.is_known_configuration_error?(params)
        if params["status"].present? && is_unsuccessful_status?(params["status"]) && is_config_error
          params["status"] = "user-error"
        end
        if params["job_status"].present? && is_unsuccessful_job_status?(params["job_status"]) && is_config_error
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

        self.report_status_to_splunk(repo, params)
        self.report_status_to_hydro(repo, params)
        self.report_status_to_datadog(repo, params)
      end

      sig { params(repo: Repository, params: T.untyped).void }
      def self.report_status_to_splunk(repo, params)
        params = params.dup

        # converts hashes to strings for logging to Splunk, but not Datadog.
        params["feature_flags_status"] = params["feature_flags_status"].to_json
        params["event_reports"] = params["event_reports"].to_json
        params["properties"] = params["properties"].to_json
        params["database_upload_results"] = params["database_upload_results"].to_json
        params["dependency_caching_usage"] = params["dependency_caching_usage"].to_json
        params["dependency_caching_restore_results"] = params["dependency_caching_restore_results"].to_json
        params["dependency_caching_upload_results"] = params["dependency_caching_upload_results"].to_json

        # move variable length values to the end of the log line, using delete method
        params["matrix_vars"] = params.delete("matrix_vars") if params["matrix_vars"].present?
        params["cause"] = params.delete("cause") if params["cause"].present?
        params["exception"] = params.delete("exception") if params["exception"].present?

        params.each_pair do |key, value|
          # convert any control characters; \n => \\n etc
          params[key] = value.to_str.strip.dump[1...-1] if value.respond_to?(:to_str)
        end

        # Prepend keys with "codeql_action.report_status" to safely namespace them
        params = params.transform_keys do |key|
          "gh.code_scanning.codeql_action.report_status.#{key}"
        end

        # add repo info
        params["gh.repo.id"] = repo.id
        params["gh.repo.name_with_owner"] = repo.nwo # rubocop:disable GitHub/DoNotAllowNameWithOwner

        # add class/method info, but at the front of the hash
        params = {
          "code.namespace" => GitHub::CodeQL::Action.name,
          "code.function" => __method__.to_s
        }.merge(params)

        GitHub.logger.info("codeql-action status report", params)
      end

      sig { params(repo: Repository, params: T.untyped).void }
      def self.report_status_to_hydro(repo, params)
        # Most params come in from JSON as string keys, but are expected as symbol keys.
        message = {
          action_name: params["action_name"],
          action_oid: params["action_oid"],
          action_ref: params["action_ref"],
          action_started_at: params["action_started_at"],
          action_version: params["action_version"],
          actions_event_name: params["actions_event_name"],
          analysis_builds_overlay_base_database: params["analysis_builds_overlay_base_database"],
          analysis_is_diff_informed: params["analysis_is_diff_informed"],
          analysis_is_overlay: params["analysis_is_overlay"],
          analysis_key: params["analysis_key"],
          analysis_kinds: params["analysis_kinds"],
          analysis_name: params["workflow_name"], # Field had to be renamed in the protobuf schema
          analyze_builtin_queries_actions_duration_ms: params["analyze_builtin_queries_actions_duration_ms"]&.to_i,
          analyze_builtin_queries_cpp_duration_ms: params["analyze_builtin_queries_cpp_duration_ms"]&.to_i,
          analyze_builtin_queries_csharp_duration_ms: params["analyze_builtin_queries_csharp_duration_ms"]&.to_i,
          analyze_builtin_queries_go_duration_ms: params["analyze_builtin_queries_go_duration_ms"]&.to_i,
          analyze_builtin_queries_java_duration_ms: params["analyze_builtin_queries_java_duration_ms"]&.to_i,
          analyze_builtin_queries_javascript_duration_ms: params["analyze_builtin_queries_javascript_duration_ms"]&.to_i,
          analyze_builtin_queries_python_duration_ms: params["analyze_builtin_queries_python_duration_ms"]&.to_i,
          analyze_builtin_queries_ruby_duration_ms: params["analyze_builtin_queries_ruby_duration_ms"]&.to_i,
          analyze_builtin_queries_rust_duration_ms: params["analyze_builtin_queries_rust_duration_ms"]&.to_i,
          analyze_builtin_queries_swift_duration_ms: params["analyze_builtin_queries_swift_duration_ms"]&.to_i,
          analyze_failure_language: params["analyze_failure_language"],
          autobuild_failure: params["autobuild_failure"],
          autobuild_languages: params["autobuild_languages"],
          build_mode: params["build_mode"],
          cause: params["cause"],
          codeql_version: params["codeql_version"],
          commit_oid: params["commit_oid"],
          completed_at: params["completed_at"],
          config_file: params["config_file"],
          database_upload_results: params["database_upload_results"]&.map do |upload_result|
            {
              language: upload_result["language"],
              zipped_upload_size_bytes: upload_result["zipped_upload_size_bytes"]&.to_i,
              # Preserve nil vs false distinction from the API
              is_overlay_base: upload_result["is_overlay_base"],
              upload_duration_ms: upload_result["upload_duration_ms"]&.to_i,
              error: upload_result["error"]
            }
          end,
          dependency_caching_restore_results: params["dependency_caching_restore_results"]&.map do |restore_result|
            {
              language: restore_result["language"],
              hit_kind: restore_result["hit_kind"],
              download_duration_ms: restore_result["download_duration_ms"]&.to_i
            }
          end,
          dependency_caching_upload_results: params["dependency_caching_upload_results"]&.map do |upload_result|
            {
              language: upload_result["language"],
              result: upload_result["result"],
              upload_size_bytes: upload_result["upload_size_bytes"]&.to_i,
              upload_duration_ms: upload_result["upload_duration_ms"]&.to_i
            }
          end,
          dependency_caching_usage: params["dependency_caching_usage"]&.then do |usage|
            {
              count: usage["count"]&.to_i,
              size_bytes: usage["size_bytes"]&.to_i
            }
          end,
          disable_default_queries: params["disable_default_queries"],
          event_reports: params["event_reports"]&.map do |event_report|
            {
              event: event_report["event"],
              started_at: event_report["started_at"],
              completed_at: event_report["completed_at"],
              exit_status: event_report["exit_status"],
              language: event_report["language"],
              properties: event_report["properties"].to_json
            }
          end,
          exception: params["exception"],
          first_party_analysis: params["first_party_analysis"],
          feature_flags_status: params["feature_flags_status"]&.map { |flag, value| { name: flag, enabled: value } },
          interpret_results_actions_duration_ms: params["interpret_results_actions_duration_ms"]&.to_i,
          interpret_results_cpp_duration_ms: params["interpret_results_cpp_duration_ms"]&.to_i,
          interpret_results_csharp_duration_ms: params["interpret_results_csharp_duration_ms"]&.to_i,
          interpret_results_go_duration_ms: params["interpret_results_go_duration_ms"]&.to_i,
          interpret_results_java_duration_ms: params["interpret_results_java_duration_ms"]&.to_i,
          interpret_results_javascript_duration_ms: params["interpret_results_javascript_duration_ms"]&.to_i,
          interpret_results_python_duration_ms: params["interpret_results_python_duration_ms"]&.to_i,
          interpret_results_ruby_duration_ms: params["interpret_results_ruby_duration_ms"]&.to_i,
          interpret_results_rust_duration_ms: params["interpret_results_rust_duration_ms"]&.to_i,
          interpret_results_swift_duration_ms: params["interpret_results_swift_duration_ms"]&.to_i,
          job_name: params["job_name"],
          job_run_uuid: params["job_run_uuid"],
          job_status: params["job_status"],
          languages: params["languages"],
          matrix_vars: params["matrix_vars"],
          ml_powered_javascript_queries: params["ml_powered_javascript_queries"],
          num_results_in_sarif: params["num_results_in_sarif"],
          overlay_base_database_download_duration_ms: params["overlay_base_database_download_duration_ms"]&.to_i,
          overlay_base_database_download_size_bytes: params["overlay_base_database_download_size_bytes"]&.to_i,
          packs: params["packs"],
          paths_ignore: params["paths_ignore"],
          paths: params["paths"],
          queries: params["queries"],
          query_filters: params["query_filters"],
          raw_upload_size_bytes: params["raw_upload_size_bytes"],
          ref: params["ref"],
          registries: params["registries"],
          registry_types: params["registry_types"],
          repository_id: repo.id,
          repository_nwo: repo.nwo, # rubocop:disable GitHub/DoNotAllowNameWithOwner
          runner_arch: params["runner_arch"],
          runner_available_disk_space_bytes: params["runner_available_disk_space_bytes"],
          runner_image_version: params["runner_image_version"],
          runner_os_release: params["runner_os_release"],
          runner_os: params["runner_os"],
          runner_total_disk_space_bytes: params["runner_total_disk_space_bytes"],
          scanned_language_extraction_duration_ms: params["scanned_language_extraction_duration_ms"]&.to_i,
          started_at: params["started_at"],
          status: params["status"],
          steady_state_default_setup: params["steady_state_default_setup"],
          testing_environment: params["testing_environment"],
          tools_download_duration_ms_opt: params["tools_download_duration_ms"]&.to_i, # Field renamed with _opt in the protobuf schema
          tools_feature_flags_valid_opt: params["tools_feature_flags_valid"], # Field renamed with _opt in the protobuf schema
          tools_input: params["tools_input"],
          tools_resolved_version: params["tools_resolved_version"],
          tools_source: params["tools_source"],
          trap_cache_cleanup_error: params["trap_cache_cleanup_error"],
          trap_cache_cleanup_size_bytes: params["trap_cache_cleanup_size_bytes"]&.to_i,
          trap_cache_cleanup_skipped_because: params["trap_cache_cleanup_skipped_because"],
          trap_cache_download_duration_ms: params["trap_cache_download_duration_ms"]&.to_i,
          trap_cache_download_size_bytes: params["trap_cache_download_size_bytes"],
          trap_cache_languages: params["trap_cache_languages"],
          trap_cache_upload_duration_ms: params["trap_cache_upload_duration_ms"]&.to_i,
          trap_cache_upload_size_bytes: params["trap_cache_upload_size_bytes"],
          trap_import_duration_ms: params["trap_import_duration_ms"]&.to_i,
          upload_failed_run_error: params["upload_failed_run_error"],
          upload_failed_run_skipped_because: params["upload_failed_run_skipped_because"],
          upload_failed_run_stack_trace: params["upload_failed_run_stack_trace"],
          workflow_languages: params["workflow_languages"],
          workflow_run_attempt: params["workflow_run_attempt"],
          workflow_run_id: params["workflow_run_id"],
          zipped_upload_size_bytes: params["zipped_upload_size_bytes"],
        }
        GitHub.aqueduct_fallback_hydro_publisher.publish(
          message,
          schema: "hydro.schemas.code_scanning.v0.StatusReport",
          topic: "code_scanning.v0.StatusReport",
          partition_key: repo.id
        )
      end

      # If `value` is an element of `possibilities`, then `value` is returned unchanged.
      # Otherwise, `other` is returned.
      sig { type_parameters(:A).params(value: T.type_parameter(:A), possibilities: T::Array[T.type_parameter(:A)], other: T.any(T.type_parameter(:A), String)).returns(T.any(T.type_parameter(:A), String)) }
      def self.sanitize_datadog_tag_value(value, possibilities, other = "sanitized-value")
        # If a Datadog tag comes from user input we need to make sure it is only in a finite set of possible values.
        # This is because Datadog charges us based on cardinality, so a malicious user could create a large blow-up in
        # cardinality by providing many possible input values.
        possibilities.include?(value) ? value : other
      end

      # Splits a comma-separated string value into its components and checks that each component is
      # an element of the accepted possibilities. All unique components are returned.
      sig { params(value: String, possibilities: T::Array[String], other: String).returns(T::Array[String]) }
      def self.sanitize_datadog_tag_list(value, possibilities, other = "sanitized-value")
        return [] unless value.is_a?(String)

        parts = value.split(",").map(&:strip).reject(&:empty?)
        return [] if parts.empty?

        components = parts.map do |component|
          sanitize_datadog_tag_value(component, possibilities, other)
        end

        components.uniq
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

      sig { params(tags: T::Array[String], dependency_caching_restore_status: Hash).void }
      def self.report_dependency_caching_restore_status_to_datadog(tags, dependency_caching_restore_status)
        return unless DEPENDENCY_CACHING_LANGUAGES.include?(dependency_caching_restore_status["language"])

        language = self.sanitize_datadog_tag_value(dependency_caching_restore_status["language"], DEPENDENCY_CACHING_LANGUAGES)
        hit_kind = self.sanitize_datadog_tag_value(dependency_caching_restore_status["hit_kind"], %w[no-hash miss exact partial])
        duration = dependency_caching_restore_status["download_duration_ms"]&.to_i || 0

        extra_tags = [
          "language:#{language}",
          "hit-kind:#{hit_kind}",
        ]

        GitHub.dogstats.increment("codeql_action.dependency_cache_restore_result", tags: extra_tags + tags)

        # Report the duration if a cache was restored
        if (hit_kind == "exact" || hit_kind == "partial") && duration > 0
          GitHub.dogstats.distribution("codeql_action.dependency_cache_restore", duration, tags: extra_tags + tags)
        end
      end

      sig { params(tags: T::Array[String], dependency_caching_upload_status: Hash).void }
      def self.report_dependency_caching_upload_status_to_datadog(tags, dependency_caching_upload_status)
        return unless DEPENDENCY_CACHING_LANGUAGES.include?(dependency_caching_upload_status["language"])

        language = self.sanitize_datadog_tag_value(dependency_caching_upload_status["language"], DEPENDENCY_CACHING_LANGUAGES)
        result = self.sanitize_datadog_tag_value(dependency_caching_upload_status["result"], %w[no-hash empty duplicate stored])
        duration = dependency_caching_upload_status["upload_duration_ms"]&.to_i || 0
        size = dependency_caching_upload_status["upload_size_bytes"]&.to_i || 0

        GitHub.dogstats.increment("codeql_action.dependency_cache_upload_result", tags: [
          "language:#{language}",
          "result:#{result}",
        ] + tags)

        # Report the duration and size if a cache was stored
        if result == "stored"
          if duration > 0
            GitHub.dogstats.distribution("codeql_action.dependency_cache_upload", duration, tags: [
              "language:#{language}",
            ] + tags)
          end
          if size > 0
            GitHub.dogstats.distribution("codeql_action.dependency_cache_size", size, tags: [
              "language:#{language}",
            ] + tags)
          end
        end
      end

      def self.report_status_to_datadog(repo, params)
        action_name = self.sanitize_datadog_tag_value(params["action_name"], ACTION_NAMES)
        status = self.sanitize_datadog_tag_value(params["status"], %w[success failure aborted starting user-error])
        runner_os = self.sanitize_datadog_tag_value(params["runner_os"], %w[Linux Windows macOS])

        tags = [
          "action-name:#{action_name}",
          "status:#{status}",
          "runner-os:#{runner_os}",
        ]

        # Only append the `internal-testing-repo` value if there wasn't already another value set in the status report.
        if !params["testing_environment"].present? && internal_testing_repo?(repo.nwo) # rubocop:disable GitHub/DoNotAllowNameWithOwner
          tags << "testing-environment:internal-testing-repo"
        end

        dogfood_repo = (repo.nwo == "github/github") # rubocop:disable GitHub/DoNotAllowNameWithOwner
        tags << "dogfood-repo:#{dogfood_repo}"

        if params.has_key?("runner_arch")
          runner_arch = self.sanitize_datadog_tag_value(params["runner_arch"], %w[X86 X64 ARM ARM64])
          tags << "runner-arch:#{runner_arch}"
        end
        if params.has_key?("action_version")
          action_version_major = self.sanitize_datadog_tag_value(params["action_version"].split(".").first, %w[1 2 3 4])
          tags << "action-version-major:#{action_version_major}"
        end
        if params.has_key?("build_mode")
          build_mode = self.sanitize_datadog_tag_value(params["build_mode"], %w[autobuild manual none])
          tags << "build-mode:#{build_mode}"
        end
        if params.has_key?("codeql_version")
          # Only allow a limited number of values to avoid Datadog cardinality blow-up.
          # Here we allow 2.0.0 through 2.39.9 (400 values).
          codeql_version = if params["codeql_version"].match(/\A2\.[123]?[0-9]\.[0-9]\z/)
            params["codeql_version"]
          else
            "sanitized-value"
          end
          tags << "codeql-version:#{codeql_version}"
        end
        if params.has_key?("languages")
          languages = self.sanitize_datadog_tag_value(params["languages"], KNOWN_LANGUAGES)
          tags << "languages:#{languages}"
        end
        if params.has_key?("analysis_kinds")
          analysis_kinds = self.sanitize_datadog_tag_list(params["analysis_kinds"], ANALYSIS_KINDS)
          analysis_kinds.each do |kind|
            tags << "analysis-kind:#{kind}"
          end
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
          job_status = self.sanitize_datadog_tag_value(params["job_status"], [:JOB_STATUS_UNKNOWN, :JOB_STATUS_SUCCESS, :JOB_STATUS_FAILURE, :JOB_STATUS_CONFIGURATION_ERROR])
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
        if params.has_key?("analysis_is_diff_informed")
          analysis_is_diff_informed = self.sanitize_datadog_tag_value(params["analysis_is_diff_informed"], [true, false])
          tags << "analysis-is-diff-informed:#{analysis_is_diff_informed}"
        end
        if params.has_key?("analysis_is_overlay")
          analysis_is_overlay = self.sanitize_datadog_tag_value(params["analysis_is_overlay"], [true, false])
          tags << "analysis-is-overlay:#{analysis_is_overlay}"
        end
        if params.has_key?("analysis_builds_overlay_base_database")
          analysis_builds_overlay_base_database = self.sanitize_datadog_tag_value(
            params["analysis_builds_overlay_base_database"], [true, false]
          )
          tags << "analysis-builds-overlay-base-database:#{analysis_builds_overlay_base_database}"
        end
        if params.has_key?("registry_types")
          registry_types = self.sanitize_datadog_tag_list(params["registry_types"], SUPPORTED_REGISTRY_TYPES)
          registry_types.each do |registry_type|
            tags << "registry-type:#{registry_type}"
          end
        end

        # Add values of CodeQL Action feature flags
        tags += self.datadog_tags_for_feature_flags(params["feature_flags_status"])

        # Update dependency caching metrics
        if FeatureFlag.vexi.enabled?(:codeql_action_new_datadog_caching_data, repo, repo.owner, repo.owner&.business, default: false)
          # To prevent abuse, we limit the maximum number of results that we store to the number of languages that support dependency caching.
          if params.has_key?("dependency_caching_restore_results") &&
            params["dependency_caching_restore_results"].length <= DEPENDENCY_CACHING_LANGUAGES.length
            params["dependency_caching_restore_results"].each { |result| report_dependency_caching_restore_status_to_datadog(tags, result) }
          end
          if params.has_key?("dependency_caching_upload_results") &&
            params["dependency_caching_upload_results"].length <= DEPENDENCY_CACHING_LANGUAGES.length
            params["dependency_caching_upload_results"].each { |result| report_dependency_caching_upload_status_to_datadog(tags, result) }
          end
        end

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

      # sig { params(params: T.untyped).returns(T::Boolean) }
      def self.is_known_configuration_error?(params)
        self.action_version_below?(params, Semantic::Version.new("4.31.2")) &&
        params["cause"].is_a?(String) &&
        params["cause"].match(KNOWN_ENABLEMENT_CONFIGURATION_ERROR_REGEX)
      end

      # sig { params(params: T.untyped, action_version: Semantic::Version).returns(T::Boolean) }
      def self.action_version_below?(params, action_version)
        self.status_report_version_below?(params["action_version"], action_version)
      end

      # sig { params(params: T.untyped, codeql_version: Semantic::Version).returns(T::Boolean) }
      def self.codeql_version_below?(params, codeql_version)
        self.status_report_version_below?(params["codeql_version"], codeql_version)
      end

      # sig { params(param: T.untyped, version: Semantic::Version).returns(T::Boolean) }
      def self.status_report_version_below?(param, version)
        param.present? &&
          param.match(Semantic::Version::SemVerRegexp) &&
          Semantic::Version.new(param) < version
      end
    end
  end
end
