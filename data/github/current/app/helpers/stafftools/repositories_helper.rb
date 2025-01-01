# typed: true
# frozen_string_literal: true

module Stafftools
  module RepositoriesHelper
    def self.get_kusto_link_for_repo_details(repo)
      business = GitHub.multi_tenant_enterprise? ? GitHub::CurrentTenant.unscope { repo&.owner&.business } : nil
      stafftools_tenant = GitHub::CurrentTenant.get
      nwo = GitHub::CurrentTenant.set(business) do
        repo.name_with_display_owner
      end
      GitHub::CurrentTenant.set(stafftools_tenant)

      raw_query =
        <<~KQL
          // This calls GetNwoInfo to get NWO matches across all clusters then filters down to the stamp.
          //
          // Details:
          // - Source: https://github.com/github/actions-kusto/blob/main/functions/functions/Chatops/GetNwoInfo.csl
          // - Query: .show function GetNwoInfo | project trim_end("}", trim_start("{", Body))
          GetNwoInfo("#{nwo}") | where Stamp == "#{stamp}"
        KQL
      query = URI.encode_www_form_component(raw_query)

      "#{kusto_base_url}?query=#{query}"
    end

    # Returns splunk link for check suite or workflow run execution
    def self.get_splunk_link(entity)
      start_date = entity.started_at&.to_i || "-7d"
      end_date = entity.completed_at&.to_i || "now"

      "#{splunk_base_url}/en-US/app/gh_reference_app/search?display.page.search.mode=smart&dispatch.sample_ratio=1&earliest=#{start_date}&latest=#{end_date}&q=search%20index%3Dprod-resque%20stamp=#{stamp}%20gh.actions.workflow_run.id%3D#{entity.external_id}"
    end

    # Returns splunk link for workflow hydro postback updates
    def self.get_splunk_link_for_actions_workflow_run_postback_updates(check_suite)
      start_date = check_suite.created_at.present? ? (check_suite.created_at&.to_i - 1000) : "-7d"
      end_date = check_suite.completed_at.present? ? (check_suite.completed_at&.to_i + 1000) : "now"

      # index="prod-resque" job="HydroWorkflowUpdateJob" gh.actions.workflow_run.id=#{check_suite.external_id} code.function != "with_sharding"
      # | table Timestamp, gh.check_run.id, workflow_update.type, code.function, Body, update_properties
      # | sort Timestamp
      "#{splunk_base_url}/en-US/app/gh_reference_app/search?display.page.search.mode=smart&dispatch.sample_ratio=1&earliest=#{start_date}&latest=#{end_date}&q=search%20index%3D%22prod-resque%22%20stamp=#{stamp}%20job%3D%22HydroWorkflowUpdateJob%22%20gh.actions.workflow_run.id%3D%22#{check_suite.external_id}%22%20code.function%20!%3D%20%22with_sharding%22%0A%7C%20table%20Timestamp%2C%20gh.check_run.id%2C%20workflow_update.type%2C%20code.function%2C%20Body%2C%20update_properties%0A%7C%20sort%20Timestamp"
    end

    # Returns splunk link for workflow invocations for a SHA
    def self.get_splunk_link_for_workflow_run_invocation_logs(sha, created_at)
      start_date = (created_at&.to_i - 1000)
      end_date = (created_at&.to_i + 1000)
      raw_query = <<~SPL
        search index IN (prod-launch)
        "#{sha}"
        | sort by _time asc
      SPL

      query = URI.encode_uri_component(raw_query)
      "#{splunk_base_url}/en-US/app/gh_reference_app/search?q=#{query}&display.page.search.mode=verbose&dispatch.sample_ratio=1&workload_pool=&earliest=#{start_date}&latest=#{end_date}&display.page.search.tab=statistics&display.general.type=statistics"
    end

    # Returns splunk link for hydro postback udpates scoped to a single Actions Job
    def self.get_splunk_link_for_actions_job_postback_updates(check_run)
      start_date = check_run.created_at.present? ? (check_run.created_at&.to_i - 1000) : "-7d"
      end_date = check_run.completed_at.present? ? (check_run.completed_at&.to_i + 1000) : "now"

      # index="prod-resque" job="HydroWorkflowUpdateJob" gh.check_run.id=#{check_run.id} code.function != "with_sharding"
      # | table Timestamp, code.function, Body, update_properties
      # | sort Timestamp
      "#{splunk_base_url}/en-US/app/gh_reference_app/search?display.page.search.mode=smart&dispatch.sample_ratio=1&earliest=#{start_date}&latest=#{end_date}&q=search%20index%3D%22prod-resque%22%20stamp=#{stamp}%20job%3D%22HydroWorkflowUpdateJob%22%20gh.check_run.id%3D#{check_run.id}%20code.function%20!%3D%20%22with_sharding%22%0A%7C%20table%20Timestamp%2C%20code.function%2C%20Body%2C%20update_properties%0A%7C%20sort%20Timestamp"
    end

    def self.get_organization_container_packages_download_limit(namespace)
      # index=container-registry  Body="Rate-limit for namespace_key with redis store: #{namespace}_CONTAINER_READ, decision: false, bad_actor: false"
      # | timechart max(gh.container-registry.remaining)
      "#{splunk_base_url}/en-US/app/gh_reference_app/search?q=search%20index%3Dcontainer-registry%20%20Body%3D\"Rate-limit%20for%20namespace_key%20with%20redis%20store%3A%20#{namespace}_CONTAINER_READ%2C%20decision%3A%20false%2C%20bad_actor%3A%20false\"%20%20%7C%20timechart%20min(gh.container-registry.remaining)%20span%3D10s&display.page.search.mode=smart&dispatch.sample_ratio=1&workload_pool=Standard&earliest=-15m%40m&latest=now&display.page.search.tab=visualizations&display.general.type=visualizations"
    end

    def self.get_integration_dotcom_api_requests(integration_id)
      #index="rails" request_category="api" gh.integration.id="#{integration_id}"
      "#{splunk_base_url}/en-US/app/gh_reference_app/search?q=search%20index%3D%22rails%22%20request_category%3D%22api%22%20gh.integration.id%3D%22#{integration_id}%22&display.page.search.mode=smart&dispatch.sample_ratio=1&workload_pool=Standard&earliest=-24h%40h&latest=now"
    end

    # Returns kusto link for check suite or workflow run execution based on external_id (plan_id)
    def self.get_kusto_link_for_workflow_trace(external_id)
      raw_query =
        <<~KQL
          // This calls GetPlanTrace to find the plan across all clusters.
          //
          // Details:
          // - Source: https://github.com/github/actions-kusto/blob/main/functions/functions/Chatops/GetPlanTrace.csl
          // - Query: .show function GetPlanTrace | project trim_end("}", trim_start("{", Body))
          GetPlanTrace("#{external_id}")
        KQL
      query = URI.encode_www_form_component(raw_query)

      "#{kusto_base_url}?query=#{query}"
    end

    def self.get_kusto_link_for_cache_eviction(repo_id)
      raw_query =
        <<~KQL
          github_actions_v0_cache_eviction
          | where timestamp > ago(1d)
          | where repository_id == #{repo_id}
          | order by timestamp desc
          | take 100
        KQL
      query = URI.encode_www_form_component(raw_query)

      "#{kusto_analytics_hydro_base_url}?query=#{query}"
    end

    def self.get_splunk_link_for_workflow_trace(check_suite, external_id)
      start_date = check_suite.created_at.present? ? (check_suite.created_at&.to_i - 1000) : "-7d"
      end_date = check_suite.completed_at.present? ? (check_suite.completed_at&.to_i + 1000) : "now"
      raw_query = <<~SPL
        search index IN (prod-launch, actions-run-service, actions-broker, actions-broker-worker, actions-broker-listener, prod-actions-results)
        "#{external_id}"
        | eval unified_message = coalesce(Body, message, msg)
        | rename gh.actions.job.name as jobName
        | rename gh.actions.job.message_id AS jobmessageID
        | table _time, splunk_index, kube_cluster, kube_pod, host, unified_message, jobName, jobmessageID
        | sort by _time asc
      SPL

      query = URI.encode_uri_component(raw_query)
      "#{splunk_base_url}/en-US/app/gh_reference_app/search?q=#{query}&display.page.search.mode=verbose&dispatch.sample_ratio=1&workload_pool=&earliest=#{start_date}&latest=#{end_date}&display.page.search.tab=statistics&display.general.type=statistics"
    end

    def self.get_vizu_link_for_workflow_trace(check_suite, external_id)
      if FeatureFlag.vexi.enabled?(:actions_stafftools_vizu_workflow_trace, default: false)
        look_back_days = check_suite.created_at.present? ? ((Time.current - check_suite.created_at) / 1.day).ceil : 3
        "https://vizu.githubapp.com/diagram/workflowplanv2?ago=#{look_back_days}d&planId=#{external_id}&force=true"
      end
    end

    def self.get_compute_usage_link_for_check_suite(check_suite)
      start_date = check_suite.created_at.present? ? (check_suite.created_at&.to_i - 1000) : "-7d"
      end_date = check_suite.completed_at.present? ? (check_suite.completed_at&.to_i + 1000) : "now"

      raw_query =
        <<~KQL
          let start = datetime(#{start_date});
          let end = datetime(#{end_date});
          github_actions_v0_compute_usage
          | where timestamp between (start .. end)
          | where check_suite_id == #{check_suite.id}
          | sort by timestamp asc
          | project check_run_id, usage_mins, usage_ms, queued_at, last_step_completed_at, product_sku
        KQL
      query = URI.encode_www_form_component(raw_query)

      "#{kusto_hydro_base_url}?query=#{query}"
    end

    def self.get_artifact_storage_link_for_check_suite(check_suite)
      start_date = check_suite.created_at.present? ? (check_suite.created_at&.to_i - 1000) : "-7d"

      raw_query =
        <<~KQL
          let start = datetime(#{start_date});
          github_actions_v0_artifact_storage_event
          | where timestamp >= start
          | where check_suite_id == #{check_suite.id}
          | sort by timestamp asc
          | project artifact_event_type, artifact_name, created_at, expires_at, previously_expired_at, artifact_size_in_bytes
        KQL
      query = URI.encode_www_form_component(raw_query)

      "#{kusto_hydro_base_url}?query=#{query}"
    end

    # Returns audit log query link for a workflow run's job prep actions (includes information about passed secret names)
    def self.get_audit_log_link_for_workflow_job_prep(workflow_run_id, repository_id)
      query =
        <<~KQL
          webevents
          | where repo_id == #{repository_id}
          | where data.workflow_run_id == "#{workflow_run_id}"
          | where action == "workflows.prepared_workflow_job"
        KQL

      UrlHelpers.stafftools_audit_log_path(query: query)
    end

    def self.get_audit_log_link_for_workflow_run_deleted_artifacts(workflow_run_id, repository_id)
      query =
        <<~KQL
          webevents
          | where repo_id == #{repository_id}
          | where action == "artifact.destroy"
          | where data.workflow_run_id == "#{workflow_run_id}"
        KQL

      UrlHelpers.stafftools_audit_log_path(query: query)
    end

    def self.get_audit_log_link_for_repo_deleted_artifacts(repository_id)
      query =
        <<~KQL
          webevents
          | where repo_id == #{repository_id}
          | where action == "artifact.destroy"
        KQL

      UrlHelpers.stafftools_audit_log_path(query: query)
    end

    def self.get_audit_log_link_for_repo_deleted_workflow_runs(repository_id)
      query =
        <<~KQL
          webevents
          | where repo_id == #{repository_id}
          | where action == "workflows.delete_workflow_run"
        KQL

      UrlHelpers.stafftools_audit_log_path(query: query)
    end

    def self.get_audit_log_link_for_repo_deleted_caches(repository_id)
      query =
        <<~KQL
          webevents
          | where repo_id == #{repository_id}
          | where action == "actions_cache.delete"
        KQL

      UrlHelpers.stafftools_audit_log_path(query: query)
    end

    def self.kusto_base_url
      # Always use the eastus2 cluster since the Kusto functions, used above, perform cross-cluster queries.
      "https://dataexplorer.azure.com/clusters/githubactions.eastus2/databases/actions"
    end

    def self.kusto_hydro_base_url
      "https://dataexplorer.azure.com/clusters/ghdwprod.eastus/databases/hydro"
    end

    def self.kusto_analytics_hydro_base_url
      "https://dataexplorer.azure.com/clusters/gh-analytics.eastus/databases/hydro"
    end

    def self.splunk_base_url
      # Include all stamp Kusto clusters here.
      case ENV["HEAVEN_DEPLOYED_ENV"]
      # EU
      when "prod-weu-01"
        "https://splunk-eu.githubapp.com"
      # Dotcom and Staffship
      else
        "https://splunk.githubapp.com"
      end
    end

    def self.stamp
      deploy_env = ENV["HEAVEN_DEPLOYED_ENV"]
      return ENV["HEAVEN_DEPLOYED_ENV"] if deploy_env && GitHub::Config::Proxima.valid_stamp?(deploy_env)

      "dotcom"
    end
  end
end
