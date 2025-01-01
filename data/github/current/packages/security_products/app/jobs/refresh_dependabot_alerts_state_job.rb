# typed: true
# frozen_string_literal: true

# This job is responsible for refreshing the auto-dismissal state on Dependabot Alerts that already exist.
#
class RefreshDependabotAlertsStateJob < BatchedJob
  include GitHub::Memoizer

  queue_as :vulnerability_identification

  retry_on_dirty_exit
  retry_on_recoverable_exceptions attempts: 10

  exempt_from_tenant_context_requirement

  before_enqueue do |job|
    vulnerable_version_range_id = job.arguments.dig(0, :vulnerable_version_range_id)

    if vulnerable_version_range_id.nil?
      raise ArgumentError, "A vulnerable_version_range_id must be provided."
    end
  end

  RULE_TYPE = {
    cwe_ids: "cwe",
    epss: "epss",
    severity: "severity"
  }

  # This job is responsible for refreshing the auto-dismissal state on Dependabot Alerts that already exist.
  # The overall strategy here is there are 2 invocations of the job
  # 1) To reprocess repo specific rules
  # 2) To reprocess org specific rules
  # During repo rule reprocessing, we simply iterate over batches of repo ids that have associated VulnerabilityAlertRule records.
  # During org rule reprocessing, we iterate over batches of org ids that have associated VulnerabilityAlertRule records,
  # Gathering batches of repo ids that belong to the batch of orgs represented by above org ids
  # And then we exclude the repo ids that have repo-specific rules from the org repo batch since they were already processed
  # While a single DB query can return both repo + org, that query's structure prevents it from leveraging the DB index, so it kept timing out.
  # Splitting the jobs apart simplifies the query so that even though this job structure emits more total queries, the queries are so much faster that it's a huge performance win.

  def process_batch(batch, vulnerable_version_range_id: nil, changes: nil, org_rules: false, **kwargs)
    start_time = GitHub::Dogstats.monotonic_time

    if org_rules
      GitHub.dogstats.increment("refresh_dependabot_alerts_state_job.job_count", tags: ["rule_scope:org"])
      process_org_batch(batch, vulnerable_version_range_id, changes)
    else
      GitHub.dogstats.increment("refresh_dependabot_alerts_state_job.job_count", tags: ["rule_scope:repo"])
      process_repo_batch(batch, vulnerable_version_range_id, changes)
    end
  end

  def process_org_batch(batch, vulnerable_version_range_id, changes)
    rule_type = get_rule_type(changes)
    Repositories.domain.repo_ids_by_owners(owner_ids: batch) do |repo_ids_batch|
      repo_rules_query = VulnerabilityAlertRule
        .where(target_type: "Repository")
        .where(target_id: repo_ids_batch)
      if rule_type
        repo_rules_query = repo_rules_query.where("JSON_EXTRACT(vulnerability_alert_rules.conditions, '$.#{rule_type}') IS NOT NULL")
      end

      process_repo_batch(repo_ids_batch - repo_rules_query.pluck(:target_id), vulnerable_version_range_id, changes)
    end
  end

  def process_repo_batch(batch, vulnerable_version_range_id, changes)
    get_alerts_for_repo_batch(batch, vulnerable_version_range_id).each do |alert|
      if alert.repository&.active && alert.repository&.vulnerability_alerts_enabled?
        GitHub.dogstats.increment("repository_vulnerability_alert.processed_alerts", tags: ["rule_type:#{rule_type_tag_value(changes)}"])

        with_write do
          if alert.auto_dismiss_or_reopen(reason: :alert_updated)
            GitHub.dogstats.increment("repository_vulnerability_alert.refreshed_alerts", tags: ["rule_type:#{rule_type_tag_value(changes)}"])
          end
        end

        if changes.present?
          GitHub.instrument("repository_vulnerability_alert.vulnerability_update", {
            action: changes.include?("severity") ? "severity_change" : "vulnerability_metadata_change",
            created_at: alert.created_at,
            updated_at: alert.updated_at,
            repo_id: alert.repository_id,
            alert_id: alert.id,
            alert_number: alert.number,
            severity: alert.vulnerable_version_range&.vulnerability&.severity,
            vulnerable_version_range_id: alert.vulnerable_version_range_id,
            vulnerability_id: alert.vulnerability_id,
            ghsa_id: alert.vulnerable_version_range&.vulnerability&.ghsa_id,
          })
        end
      end

      if alert.candidate_for_pull_request?
        Dependabot::RepositoryVulnerabilityCreatedJob.enqueue(alert)
        GitHub.dogstats.increment("repository_vulnerability_alert.candidate_prs")
      end
    end
  end

  def get_rule_type(changes)
    rule_types = changes & DependabotAlerts::UpstreamModel::VULNERABILITY_CHANGE_TRIGGERS
    if rule_types && rule_types.size == 1
      RULE_TYPE[rule_types.first]
    end
  end

  def rule_type_tag_value(changes)
    tag_value = get_rule_type(changes) # returns nil if none OR more than one... For example, CWE & Severity can be changed at the same time.
    if tag_value.nil?
      tag_value = changes & DependabotAlerts::UpstreamModel::VULNERABILITY_CHANGE_TRIGGERS ? "multiple" : "none"
    end
    tag_value
  end

  # Alert rules can be set at the per-repo level or the org level (applied to all repos in the org). This returns all
  # matching repos that have per-repo level rules set on them.
  def get_repo_ids_with_matching_repo_rules(rule_type, offset_item_id)
    repo_id_query = VulnerabilityAlertRule
      .where(target_type: "Repository")
      .where("target_id > ?", offset_item_id)
    if rule_type
      repo_id_query = repo_id_query.where("JSON_EXTRACT(vulnerability_alert_rules.conditions, '$.#{rule_type}') IS NOT NULL")
    end

    repo_id_query
      .order(:target_id)
      .limit(BATCH_SIZE)
      .distinct # There may be more than one rule targeting the repo
      .pluck(:target_id)
  end

  # This returns chunks of repos that have either a per-repo rule or an org rule that matches the given rule type.
  def get_org_ids_with_matching_org_rules(rule_type, offset_item_id)
    owner_id_query = VulnerabilityAlertRule
      .where(target_type: "User") # Org-level rules
      .where("target_id > ?", offset_item_id)
    if rule_type
      owner_id_query = owner_id_query
        .where("JSON_EXTRACT(vulnerability_alert_rules.conditions, '$.#{rule_type}') IS NOT NULL")
    end

    owner_id_query
      .order(:target_id)
      .limit(BATCH_SIZE)
      .distinct
      .pluck(:target_id)
  end

  def get_alerts_for_repo_batch(batch, vulnerable_version_range_id)
    rvas = RepositoryVulnerabilityAlert.without_default_scope
      .includes(:repository)
      .where(vulnerable_version_range_id: vulnerable_version_range_id)
      # Limiting by `local_offset_id` isn't required since everything in `get_ordered_chunk_of_repo_ids_with_matching_rules`
      # is already guaranteed to be larger than `local_offset_id``. But including it is a DB optimization hint so the
      # DB planner can immediately prune the search space before executing the `IN(repo_ids_to_search)` clause.
      .where(repository_id: batch).to_a
    GitHub::PrefillAssociations.prefill_batch_method(rvas.map(&:repository), :vulnerability_alerts_enabled?)
    rvas
  end

  def next_batch(vulnerable_version_range_id: nil, offset_item_id: 0, changes: nil, org_rules: false, **kwargs)
    if vulnerable_version_range_id.nil?
      raise ArgumentError, "Must specify a vulnerable_version_range_id"
    end

    rule_type = get_rule_type(changes)
    if org_rules
      get_org_ids_with_matching_org_rules(rule_type, offset_item_id)
    else
      get_repo_ids_with_matching_repo_rules(rule_type, offset_item_id)
    end
  end

  def next_batch_offset_item_id(batch, *args, **options)
    batch.max
  end
end
