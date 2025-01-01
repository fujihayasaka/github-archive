# typed: true
# frozen_string_literal: true

module Codespaces
  class StatsTagger
    # This ensures our attributes conform to GH-flavored OpenTelemetry semantic conventions.
    SEMCONV_TAG_MAP = {
      location:            "gh.codespaces.location",
      repository:          "gh.repo.id",
      name:                "gh.codespaces.name",
      pull_request:        "gh.pull_request.id",
      sku_name:            "gh.codespaces.sku_name",
      from_pr:             "gh.codespaces.is_from_pr",
      from_fork:           "gh.codespaces.is_from_fork",
      billable_owner_type: "gh.codespaces.billable_owner_type",
      using_default_sku:   "gh.codespaces.is_using_default_sku",
      repo_empty:          "gh.codespaces.is_repo_empty",
      use_prebuild:        "gh.codespaces.repo_has_prebuild_configured",
    }

    ALLOWED_DATADOG_TAGS = %i[
      codespaces_automated_testing
      location
      using_default_sku
      sku_name
      vscs_target
      use_prebuild
      billable_owner_type
      is_copilot_workspace
      is_task_cloud_environment
    ]
    attr_reader :tags, :codespace, :owner, :vscs_target, :is_copilot_workspace, :is_task_cloud_environment

    def initialize(codespace: nil, user: nil, owner: nil, vscs_target: nil, is_copilot_workspace: nil, is_task_cloud_environment: nil, **tags)
      @tags = tags.with_indifferent_access
      @owner = owner || user || codespace&.owner
      @codespace = codespace
      @vscs_target = vscs_target || codespace&.vscs_target
      @is_copilot_workspace = codespace&.copilot_workspace? || is_copilot_workspace
      @is_task_cloud_environment = codespace&.task_cloud_environment? || is_task_cloud_environment
    end

    def datadog_tags
      all_tags.slice(*ALLOWED_DATADOG_TAGS).map do |key, value|
        "#{key}:#{value}"
      end
    end

    def all_tags
      add_codespace_automated_testing!
      add_is_copilot_workspace!
      add_is_task_cloud_environment!
      add_vscs_target!
      add_codespace_tags!
      tags.compact.symbolize_keys
    end

    def all_semconv_tags
      all_tags.transform_keys do |key|
        SEMCONV_TAG_MAP[key] || instrument_unmapped_key(key)
      end
    end

    private

    def instrument_unmapped_key(key) # Track anything we missed for OTel SemConv compliance.
      GitHub.dogstats.increment("codespaces.stats_tagger.unmapped_semconv_key", tags: ["key:#{key}"])
      key
    end

    def add_codespace_automated_testing!
      if !tags.key?(:codespaces_automated_testing) && codespaces_automated_testing?
        tags[:codespaces_automated_testing] = true
      end
    end

    def add_is_copilot_workspace!
      unless is_copilot_workspace.nil?
        tags[:is_copilot_workspace] = is_copilot_workspace
      end
    end

    def add_is_task_cloud_environment!
      unless is_task_cloud_environment.nil?
        tags[:is_task_cloud_environment] = is_task_cloud_environment
      end
    end

    def add_vscs_target!
      tags[:vscs_target] = vscs_target
    end

    def add_codespace_tags!
      return unless codespace

      tags.reverse_merge!(
        location: codespace.location,
        repository: codespace.repository&.id,
        name: codespace.name,
        pull_request: codespace.pull_request_with_fallback&.id,
        sku_name: codespace.sku_name,
        from_pr: !codespace.pull_request_with_fallback.blank?,
        from_fork: codespace.repository&.fork?,
        vscs_target: vscs_target || Codespaces::Vscs.default_target,
        billable_owner_type: if codespace.billable_owner.present?
                               codespace.billable_owner.organization? ? "organization" : "user"
                             else
                               nil
                             end,
        is_copilot_workspace: codespace.copilot_workspace?,
        is_task_cloud_environment: codespace.task_cloud_environment?,
      )
    end

    def codespaces_automated_testing?
      non_production = vscs_target && vscs_target != :production
      is_test_user = owner && GitHub.flipper[:codespaces_automated_testing].enabled?(owner)
      non_production || is_test_user
    end
  end
end
