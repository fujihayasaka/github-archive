# typed: true
# frozen_string_literal: true

Hydro::EventForwarder.configure(source: GlobalInstrumenter) do
  subscribe("browser.actions.execution_graph_click") do |payload|
    repository = if FeatureFlag.vexi.enabled?(:repos_by_id_config, default: false)
      Repositories.domain.by_id(payload[:repository_id])
    else
      Repository.find_by(id: payload[:repository_id])
    end

    message = {
      request_context: serializer.request_context(GitHub.context.to_hash),
      user: serializer.user(payload[:client][:user]),
      repository: serializer.repository(repository),
      session_id: payload[:session_id],
      click_area: serializer.enum_from_string(payload[:click_area]),
    }

    publish(message, schema: "github.actions.v0.ExecutionGraphClick")
  end

  subscribe("actions.dreamlifter_joined_waitlist") do |payload|
    message = {
      request_context: serializer.request_context(GitHub.context.to_hash),
      user: serializer.user(payload[:user]),
      spamurai_form_signals: serializer.spamurai_form_signals(GitHub.context[:spamurai_form_signals]),
    }

    publish(message, schema: "github.actions.v0.DreamlifterJoinedWaitlist", topic_format_options: { format_version: Hydro::Topic::FormatVersion::V1 }) # rubocop:disable GitHub/HydroPublishLegacyTopicFormat
  end

  subscribe("actions.artifact_storage_event") do |payload|
    message = {
      artifact_id: payload[:artifact_id],
      artifact_name: payload[:artifact_name],
      artifact_repository_owner_id: payload[:artifact_repository_owner_id],
      artifact_repository_id: payload[:artifact_repository_id],
      artifact_repository_visibility: serializer.enum_from_string(payload[:artifact_repository_visibility]),
      artifact_size_in_bytes: payload[:artifact_size_in_bytes],
      check_suite_id: payload[:check_suite_id],
      artifact_event_type: serializer.enum_from_string(payload[:event_type]),
      expires_at: payload[:expires_at],
      previously_expired_at: payload[:previously_expired_at],
      artifact_global_id: payload[:artifact_global_id],
      created_at: payload[:created_at],
    }

    publish(message, schema: "github.actions.v0.ArtifactStorageEvent", partition_key: payload[:artifact_id], topic_format_options: { format_version: Hydro::Topic::FormatVersion::V1 }) # rubocop:disable GitHub/HydroPublishLegacyTopicFormat
  end

  subscribe("browser.check_suite_image.expand") do |payload|
    message = {
      request_context: serializer.request_context(GitHub.context.to_hash,
        overrides: browser_request_context_overrides(payload)),
      actor: serializer.user(payload[:client][:user]),
      check_suite_id: serializer.user(payload[:client][:check_suite_id]),
      check_run_id: serializer.user(payload[:client][:check_run_id]),
      github_app_id: serializer.user(payload[:client][:github_app_id]),
      filename: serializer.user(payload[:client][:filename]),
    }

    publish(message, schema: "github.v1.CheckSuiteImageExpand", topic_format_options: { format_version: Hydro::Topic::FormatVersion::V1 }) # rubocop:disable GitHub/HydroPublishLegacyTopicFormat
  end

  subscribe("browser.check_suite.external_click") do |payload|
    message = {
      request_context: serializer.request_context(GitHub.context.to_hash,
        overrides: browser_request_context_overrides(payload)),
      actor: serializer.user(payload[:client][:user]),
      check_suite_id: serializer.user(payload[:client][:check_suite_id]),
      check_run_id: serializer.user(payload[:client][:check_run_id]),
      github_app_id: serializer.user(payload[:client][:github_app_id]),
      external_link_url: serializer.user(payload[:client][:link_url]),
      external_link_text: serializer.user(payload[:client][:link_text]),
    }

    publish(message, schema: "github.v1.CheckSuiteExternalClick", topic_format_options: { format_version: Hydro::Topic::FormatVersion::V1 }) # rubocop:disable GitHub/HydroPublishLegacyTopicFormat
  end

  subscribe("browser.actions.onboarding_setup_workflow_click") do |payload|
    repository = if FeatureFlag.vexi.enabled?(:repos_by_id_config, default: false)
      Repositories.domain.by_id(payload[:repository_id])
    else
      Repository.find_by(id: payload[:repository_id])
    end

    # Create message with conditional template_source_visibility field based on workflow_template_visibility_tracking feature flag
    user_id = payload[:client][:user]&.is_a?(Hash) ? payload[:client][:user][:id] : payload[:client][:user]
    user = if user_id.is_a?(User)
      user_id  # Already a User object
    elsif user_id
      User.find_by(id: user_id)  # Load User by ID
    end

    if FeatureFlag.vexi.enabled?(:workflow_template_visibility_tracking, user, repository&.owner, default: false)
      message = {
        request_context: serializer.request_context(GitHub.context.to_hash),
        user: serializer.user(payload[:client][:user]),
        repository: serializer.repository(repository),
        workflow_template: payload[:workflow_template],
        view_section: payload[:view_section],
        view_rank: payload[:view_rank],
        templates_count: payload[:templates_count],
        template_creator: payload[:template_creator],
        new_with_filter_view: payload[:new_with_filter_view],
        # Currently, correlation_id value is the request_id of actioncontroller actions/new request while request_context's request_id
        # is of browser event request. The correlation_id will help in correlating the controller hydro events with browser events. Also,
        # its value can a valid uuid if we add same uuid to controller request events.
        correlation_id: payload[:correlation_id],
        category: payload[:category],
        search_query: payload[:search_query],
        template_source_visibility: payload[:template_source_visibility]
      }
    else
      message = {
        request_context: serializer.request_context(GitHub.context.to_hash),
        user: serializer.user(payload[:client][:user]),
        repository: serializer.repository(repository),
        workflow_template: payload[:workflow_template],
        view_section: payload[:view_section],
        view_rank: payload[:view_rank],
        templates_count: payload[:templates_count],
        template_creator: payload[:template_creator],
        new_with_filter_view: payload[:new_with_filter_view],
        # Currently, correlation_id value is the request_id of actioncontroller actions/new request while request_context's request_id
        # is of browser event request. The correlation_id will help in correlating the controller hydro events with browser events. Also,
        # its value can a valid uuid if we add same uuid to controller request events.
        correlation_id: payload[:correlation_id],
        category: payload[:category],
        search_query: payload[:search_query]
      }
    end

    publish(message, schema: "github.actions.v0.OnboardingSetupWorkflowClick", topic_format_options: { format_version: Hydro::Topic::FormatVersion::V1 }) # rubocop:disable GitHub/HydroPublishLegacyTopicFormat
  end

  subscribe("browser.actions.setup_actions_popover_click") do |payload|
    repository = Repositories.domain.by_id(payload[:repository_id].to_i)

    message = {
      request_context: serializer.request_context(GitHub.context.to_hash),
      user: serializer.user(payload[:client][:user]),
      repository: serializer.repository(repository),
      click_type: serializer.enum_from_string(payload[:click_type]),
    }

    publish(message, schema: "github.actions.v0.SetupActionsPopoverClick")
  end

  subscribe("browser.actions.workflow_upgrade_popover_click") do |payload|
    repository = Repositories.domain.by_id(payload[:repository_id].to_i)

    message = {
      request_context: serializer.request_context(GitHub.context.to_hash),
      user: serializer.user(payload[:client][:user]),
      repository: serializer.repository(repository),
      location: payload[:location],
    }

    publish(message, schema: "github.actions.v0.WorkflowUpgradePopoverClick")
  end

  subscribe("actions.invocation_blocked") do |payload|
    message = {
      account: serializer.user(payload[:account])
    }

    if FeatureFlag.vexi.enabled?(:actions_send_repo_in_invocation_event, default: false) && payload[:repository]
      message[:repository] = serializer.repository(payload[:repository], overrides: { next_global_id: payload[:repository].next_global_id })
    end

    publish(message, schema: "github.actions.v0.InvocationBlocked", topic_format_options: { format_version: Hydro::Topic::FormatVersion::V1 }) # rubocop:disable GitHub/HydroPublishLegacyTopicFormat
  end

  subscribe("actions.invocation_unblocked") do |payload|
    message = {
      account: serializer.user(payload[:account])
    }

    if FeatureFlag.vexi.enabled?(:actions_send_repo_in_invocation_event, default: false) && payload[:repository]
      message[:repository] = serializer.repository(payload[:repository], overrides: { next_global_id: payload[:repository].next_global_id })
    end

    publish(message, schema: "github.actions.v0.InvocationUnblocked")
  end

  subscribe("workflow.action_required_approved") do |payload|
    message = {
      pull_request_id: payload[:pull_request_id],
      actor_id: payload[:actor_id],
      repo_id: payload[:repo_id],
      workflow_run_ids: payload[:workflow_run_ids],
    }

    publish(message, schema: "github.actions.v0.ActionRequiredWorkflowApproved")
  end

  subscribe("actions.connect_resolve_request") do |payload|
    message = {
      enterprise_installation: serializer.enterprise_installation(payload[:enterprise_installation]),
      resolved_repository: serializer.repository(payload[:resolved_repository]),
      ref: payload[:ref]
    }

    publish(message, schema: "github.actions.v0.ConnectResolveRequest")
  end

  subscribe("actions.resolve_actions_request") do |payload|
    message = {
      resolved_repository: serializer.repository(payload[:resolved_repository]),
      ref: payload[:ref],
      resolved_ref: payload[:resolved_ref],
      resolved_sha: payload[:resolved_sha],
      user: serializer.user(payload[:user]),
      connect_request: payload[:connect_request],
      enterprise_installation: serializer.enterprise_installation(payload[:enterprise_installation]),
      workflow_run_id: payload[:workflow_run_id],
      job_id: payload[:job_id],
      workflow_repository_id: payload[:workflow_repository_id],
      action_nwo: payload[:action_nwo],
      package_id: payload[:package_id]
    }

    partition_key = payload[:resolved_repository]&.id || payload[:package_id]
    publish(message,
      schema: "github.actions.v0.ResolveActionRequest",
      partition_key: partition_key, topic_format_options: { format_version: Hydro::Topic::FormatVersion::V1 } # rubocop:disable GitHub/HydroPublishLegacyTopicFormat
    )
  end

  subscribe("repository_actions.recommended_templates") do |payload|
    repository = if FeatureFlag.vexi.enabled?(:repos_by_id_config, default: false)
      Repositories.domain.by_id(payload[:repository_id])
    else
      Repository.find_by(id: payload[:repository_id])
    end
    message = {
      request_context: serializer.request_context(GitHub.context.to_hash),
      repository: serializer.repository(repository),
      category: payload[:category],
      templates: payload[:templates],
      commit_sha: payload[:commit_sha]
    }

    publish(message, schema: "github.actions.v0.OnboardingRecommendedWorkflowTemplate")
  end

  subscribe("gate_request.created") do |payload|
    message = {
      gate_request_id: payload[:gate_request_id],
      gate_id: payload[:gate_id],
      gate_type: serializer.enum_from_string(payload[:gate_type]),
      check_suite_id: payload[:check_suite_id],
      check_run_id: payload[:check_run_id],
      repository: serializer.repository(payload[:repository]),
      integration: serializer.integration(payload[:integration])
    }

    publish(message, schema: "github.actions.v0.GateRequestCreated")
  end

  subscribe("workflow_run_execution.completed") do |payload|
    message = {
      actor_id: payload[:actor_id],
      attempt: payload[:attempt],
      conclusion: payload[:conclusion],
      check_suite_id: payload[:check_suite_id],
      repository_id: payload[:repository_id],
      repository_owner_id: payload[:repository_owner_id],
      status: payload[:status],
      workflow_run_external_id: payload[:workflow_run_external_id],
      workflow_run_id: payload[:workflow_run_id],
      workflow_run_path: payload[:workflow_run_path],
      started_at: payload[:started_at],
      completed_at: payload[:completed_at]
    }

    publish(message, schema: "github.actions.v0.WorkflowRunExecution")
  end
end

Hydro::EventForwarder.configure(source: GitHub) do
  subscribe("repo.actions_enabled") do |payload|
    actor = User.find_by(id: payload[:actor_id])
    repository = if FeatureFlag.vexi.enabled?(:repos_by_id_config, default: false)
      Repositories.domain.by_id(payload[:repo_id])
    else
      Repository.find_by(id: payload[:repo_id])
    end

    message = {
      actor: Hydro::EntitySerializer.user(actor),
      repository: Hydro::EntitySerializer.repository(repository),
    }

    publish(message, schema: "github.actions.v0.RepoEnabled", topic_format_options: { format_version: Hydro::Topic::FormatVersion::V1 }) # rubocop:disable GitHub/HydroPublishLegacyTopicFormat
  end
end

Hydro::EventForwarder.configure(source: GlobalInstrumenter) do
  subscribe("workflow.pinning_activity") do |payload|
    message = {
      workflow_id: payload[:workflow_id],
      actor_id: payload[:actor_id],
      workflow_repository_id: payload[:workflow_repository_id],
      event: serializer.enum_from_string(payload[:event])
    }

    publish(message, schema: "github.actions.v0.PinnedWorkflowsActivity")
  end
end
