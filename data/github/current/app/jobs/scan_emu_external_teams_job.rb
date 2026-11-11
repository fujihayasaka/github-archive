# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

# This job scans for externally managed EMU teams that have a mismatch between the external_group members and the team members.
# If mismatched teams are found, the job will notify the external-identities team on slack and kick off an ExternalGroupTeamReconcileJob for each team.
# This job repeats every day (frequency TBD).
class ScanEmuExternalTeamsJob < ApplicationJob
  include ChecksJobUtility

  BATCH_SIZE = 10
  INTERVAL_OFFSET = 3
  DEFAULT_ABILITY_BATCH_SIZE = 5000
  # Bounded per-run cap for in_sync drift detection. Start conservative; raise only after
  # production timing/size telemetry justifies it.
  DRIFT_DETECTION_BATCH_SIZE = 500
  DRIFT_DETECTION_CURSOR_KEY = "scan_emu_external_teams:drift_detection:cursor"
  # Cursor self-heals to 0 (full re-sweep) if it ever expires; refreshed every run.
  DRIFT_DETECTION_CURSOR_TTL = 30.days
  EXTERNAL_GROUP_TEAM_SPLUNK_SEARCH_URL = "https://splunk.githubapp.com/en-US/app/gh_reference_app/search?" \
    "q=search%20index%3Dprod-resque%20code.namespace%3DScanEmuExternalTeamsJob%20" \
    "%28info.message%3D%22Mismatched%20EMU%20External%20Group%20Team%22%20OR%20" \
    "info.message%3D%22Scan%20EMU%20external%20teams%20enqueue%20summary%22%29" \
    "&display.page.search.mode=fast&dispatch.sample_ratio=1&workload_pool=Standard" \
    "&earliest=-24h%40h&latest=now&display.page.search.tab=events&display.general.type=events"

  queue_as :scan_emu_external_teams

  # This job's original start time is 6:30AM PST / 9:30AM EST / 14:30 UTC every day
  schedule interval: 12.hours, condition: -> { !GitHub.enterprise? }

  retry_on_dirty_exit
  retry_on(ActiveRecord::QueryCanceled, attempts: 2, wait: 5.minutes)

  exempt_from_tenant_context_requirement

  def perform
    # Runs only during off-peak traffic times to reduce DB load
    return if peak_traffic_time?

    skip_ability_count = FeatureFlag.vexi.enabled?(:scan_emu_skip_ability_count, default: false)

    interval = 0
    interval, external_group_teams_for_reconcile = perform_external_group_team_reconcile(interval, skip_ability_count: skip_ability_count)
    external_group_teams_for_deletion = perform_external_group_team_delete(interval)

    # When skip_ability_count is on, all teams are already enqueued for reconciliation
    # via find_each, so skip check_all_out_of_sync to avoid a redundant large NOT IN query.
    unless skip_ability_count
      external_group_teams_to_skip = [*external_group_teams_for_reconcile, *external_group_teams_for_deletion]
      check_all_out_of_sync_external_group_teams(external_group_teams_to_skip)
    end

    # When skip_ability_count is enabled the reconcile scan only covers not_in_sync rows, so rows
    # stuck at in_sync while actually drifted (e.g. a reconcile that crashed before updating
    # sync_status) are never re-examined. Bounded drift detection sweeps a rolling window of
    # in_sync rows with the cheap membership comparison (no abilities query) to recover them.
    if skip_ability_count && FeatureFlag.vexi.enabled?(:scan_emu_drift_detection, default: false)
      perform_in_sync_drift_detection
    end
  end

  private

  def perform_external_group_team_reconcile(interval, skip_ability_count: false)
    # When skip_ability_count is enabled, bypass all count queries and iterate teams directly.
    if skip_ability_count
      return perform_external_group_team_reconcile_all(interval)
    end

    external_group_team = ExternalGroupTeam.joins(:team).pluck(:id, :external_group_id, :team_id).to_h { |id, external_group_id, team_id| [id, { external_group_id: external_group_id, team_id: team_id }] }

    external_group_no_members = []
    deleted_groups_ids = ExternalGroup.where.not(deleted_at: nil).pluck(:id)
    deleted_groups_ids.each_slice(5000) do |ids|
      external_group_no_members.concat(ExternalIdentityGroupMembership.where(external_group_id: ids).distinct.pluck(:external_group_id))
    end

    GitHub.logger.info(
      "info.message" => "External groups marked deleted with existing memberships",
      "code.namespace" => self.class.name,
      "code.function" => "perform",
      "gh.external_groups.ids" => external_group_no_members.join(", "),
      "gh.external_groups.count" => external_group_no_members.size,
    )

    # Get external group ids and batch selects for counts.
    # When flag is enabled, scope to only groups linked to teams (avoids unbounded full-table scan).
    external_group_ids = if FeatureFlag.vexi.enabled?(:scan_emu_scope_external_groups, default: false)
      external_group_team.values.map { |val| val[:external_group_id] }.uniq
    else
      ExternalGroup.all.pluck(:id)
    end
    external_group_counts = {}
    external_group_ids.each_slice(5000) do |ids|
      external_group_counts.merge!(ExternalIdentityGroupMembership.joins(:external_identity).
        where(external_group_id: ids).where(external_identity: { active: true }).group(:external_group_id).count)
    end
    external_group_no_members.each { |external_group_id| external_group_counts[external_group_id] = 0 }

    team_ids = external_group_team.values.map { |val| val[:team_id] }.uniq

    team_counts = {}
    # Use a tunable batch size to avoid killed queries on the abilities table (see ability_query_batch_size).
    batch_size = ability_query_batch_size
    # When flag is enabled, query each subject_type separately for better index utilization.
    if FeatureFlag.vexi.enabled?(:scan_emu_split_subject_type, default: false)
      %w(BusinessTeam Team).each do |subject_type|
        team_ids.each_slice(batch_size) do |ids|
          team_counts.merge!(ability_team_count_query(ids, subject_type))
        end
      end
    else
      subject_types = %w(BusinessTeam Team)
      team_ids.each_slice(batch_size) { |ids| team_counts.merge!(ability_team_count_query(ids, subject_types)) }
    end
    mismatched_team_ids = external_group_team.reject { |_id, val| !team_counts.has_key?(val[:team_id]) && external_group_counts[val[:external_group_id]] == 0 || external_group_counts[val[:external_group_id]] == team_counts[val[:team_id]] }.keys

    mismatched_teams = ExternalGroupTeam.where(id: mismatched_team_ids)

    message = if mismatched_teams.empty?
      "No mismatched externally managed EMU teams found today!"
    else
      "Mismatched externally managed EMU teams found. See Splunk search #{EXTERNAL_GROUP_TEAM_SPLUNK_SEARCH_URL}"
    end
    GitHub::Chatterbox.client.say!("#external-identities-ops", message) unless GitHub.enterprise?

    businesses_avail = businesses_available_licenses(external_group_teams: mismatched_teams)

    mismatched_teams.each_slice(BATCH_SIZE) do |egts|
      egts.each do |egt|
        # Skip teams that don't belong to an organization
        # All EMU teams should belong to an organization
        # unless team is a business team
        next if !egt.team&.business_team? && !egt.team&.organization

        instrument_mismatch_event(external_group_team: egt, businesses_available_licenses: businesses_avail)

        ExternalGroupTeamReconcileJob.set(wait: interval.minutes).perform_later(external_group_id: egt.external_group_id, team_id: egt.team_id, caller: self.class.name)
      end

      interval += INTERVAL_OFFSET
    end

    [interval, mismatched_teams]
  end

  # When skip_ability_count is enabled, bypass the expensive Abilities table query entirely.
  # Instead, scope to teams whose sync_status is already not in_sync (the stuck-team population
  # this job is meant to recover) and enqueue a reconcile job for each. The reconcile job is
  # idempotent and will no-op for teams that are already in sync via calculate_memberships_in_sync?.
  #
  # This intentionally drops drift detection for teams whose sync_status is in_sync but actually
  # out of sync. Drift detection should be addressed separately (see follow-up issue) since the
  # Abilities count query that previously provided it has been crashing the job for weeks.
  def perform_external_group_team_reconcile_all(interval)
    scope = ExternalGroupTeam.not_in_sync.joins(:team).includes(team: :organization, external_group: { provider: :business })
    team_count = scope.count
    message = if team_count == 0
      "No out-of-sync EMU External Group Teams found (skip_ability_count enabled)."
    else
      "Found #{team_count} out-of-sync EMU External Group Teams. Enqueuing reconcile (skip_ability_count enabled). See Splunk search #{EXTERNAL_GROUP_TEAM_SPLUNK_SEARCH_URL}"
    end
    GitHub::Chatterbox.client.say!("#external-identities-ops", message) unless GitHub.enterprise?

    batch_count = 0
    enqueued_count = 0
    skipped_count = 0
    max_wait_minutes = T.let(0, Integer)
    scope.find_each do |egt|
      if !egt.team&.business_team? && !egt.team&.organization
        skipped_count += 1
        next
      end

      instrument_mismatch_event(external_group_team: egt, skip_counts: true)
      max_wait_minutes = interval
      ExternalGroupTeamReconcileJob.set(wait: interval.minutes).perform_later(
        external_group_id: egt.external_group_id, team_id: egt.team_id, caller: self.class.name
      )

      enqueued_count += 1
      batch_count += 1
      if batch_count % BATCH_SIZE == 0
        interval += INTERVAL_OFFSET
      end
    end

    GitHub.dogstats.increment("external_identities.scan_emu_external_teams.enqueued", by: enqueued_count)
    GitHub.dogstats.increment("external_identities.scan_emu_external_teams.skipped", by: skipped_count)
    GitHub.logger.info(
      "info.message" => "Scan EMU external teams enqueue summary",
      "code.namespace" => self.class.name,
      "code.function" => "perform_external_group_team_reconcile_all",
      "gh.external_group_teams.not_in_sync.count" => team_count,
      "gh.external_group_teams.enqueued.count" => enqueued_count,
      "gh.external_group_teams.skipped.count" => skipped_count,
      "gh.external_group_teams.max_wait_minutes" => max_wait_minutes,
    )

    [interval, []]
  end

  def perform_external_group_team_delete(interval)
    external_group_teams = ExternalGroupTeam.left_joins(:team).where(team: { id: nil })

    businesses_available_licenses = businesses_available_licenses(external_group_teams: external_group_teams)

    external_group_teams.each_slice(BATCH_SIZE) do |egts|
      egts.each do |egt|
        instrument_delete_event(external_group_team: egt, businesses_available_licenses: businesses_available_licenses)

        ExternalGroupTeamReconcileJob.set(wait: interval.minutes).perform_later(external_group_id: egt.external_group_id, team_id: egt.team_id, caller: self.class.name)
      end

      interval += INTERVAL_OFFSET
    end

    external_group_teams
  end

  def check_all_out_of_sync_external_group_teams(external_group_teams_to_skip)
    ExternalGroupTeam.where.not(sync_status: :in_sync).where.not(id: external_group_teams_to_skip.pluck(:id)).find_each do |external_group_team|
      external_group_team.update_sync_status
      external_group_team.reload

      unless external_group_team.in_sync?
        ExternalGroupTeamReconcileJob.enqueue_external_group_team_once_per_interval(external_group_team, self.class.name)
      end
    end
  end

  # Bounded drift detection for ExternalGroupTeam rows stuck at sync_status = in_sync while their
  # actual membership has drifted. Only meaningful when skip_ability_count is enabled (which removes
  # the abilities-count drift detection for the in_sync population). Sweeps a rolling window of
  # in_sync rows ordered by id, using a KV-persisted cursor for deterministic eventual coverage with
  # a hard per-run bound. Each row is checked with calculate_memberships_in_sync? (direct membership
  # comparison, no abilities table query), and drifted rows are enqueued for reconcile (deduped via
  # enqueue_external_group_team_once_per_interval).
  def perform_in_sync_drift_detection
    cursor = drift_detection_cursor

    rows = ExternalGroupTeam.in_sync
      .where("external_group_teams.id > ?", cursor)
      .order(:id)
      .limit(DRIFT_DETECTION_BATCH_SIZE)
      .includes(:external_group, team: :organization)
      .to_a

    checked_count = 0
    drifted_count = 0
    skipped_count = 0
    last_id = T.let(nil, T.nilable(Integer))

    rows.each do |egt|
      last_id = egt.id

      # Skip orphaned/teamless rows (handled by the delete pass) and rows with a missing external
      # group: the reconcile job would no-op on a nil external group, causing a detect -> no-op ->
      # detect loop that never advances.
      if egt.external_group.nil? || (!egt.team&.business_team? && !egt.team&.organization)
        skipped_count += 1
        next
      end

      begin
        checked_count += 1
        next if egt.calculate_memberships_in_sync?

        drifted_count += 1
        instrument_mismatch_event(external_group_team: egt, skip_counts: true)
        ExternalGroupTeamReconcileJob.enqueue_external_group_team_once_per_interval(egt, self.class.name)
      rescue ActiveRecord::QueryCanceled
        # Systemic timeout: let it propagate so the job's retry_on(ActiveRecord::QueryCanceled) fires.
        raise
      rescue => error
        # A single pathological row must not crash the sweep and stall the cursor.
        GitHub.dogstats.increment("external_identities.scan_emu_external_teams.drift_detection.error")
        GitHub.logger.error(
          "exception.message" => error.message,
          "exception.class" => error.class.name,
          "code.namespace" => self.class.name,
          "code.function" => "perform_in_sync_drift_detection",
          "gh.external_group_team.id" => egt.id,
        )
      end
    end

    # Advance the cursor to the last id examined. When we fetched fewer rows than the batch size we
    # have reached the end of the in_sync population, so wrap back to the start for the next run.
    next_cursor = rows.size < DRIFT_DETECTION_BATCH_SIZE ? 0 : (last_id || 0)
    update_drift_detection_cursor(next_cursor)

    GitHub.dogstats.increment("external_identities.scan_emu_external_teams.drift_detection.checked", by: checked_count)
    GitHub.dogstats.increment("external_identities.scan_emu_external_teams.drift_detection.drifted", by: drifted_count)
    GitHub.dogstats.increment("external_identities.scan_emu_external_teams.drift_detection.skipped", by: skipped_count)
    GitHub.logger.info(
      "info.message" => "Scan EMU external teams drift detection summary",
      "code.namespace" => self.class.name,
      "code.function" => "perform_in_sync_drift_detection",
      "gh.external_group_teams.drift_detection.cursor_start" => cursor,
      "gh.external_group_teams.drift_detection.cursor_end" => next_cursor,
      "gh.external_group_teams.drift_detection.checked.count" => checked_count,
      "gh.external_group_teams.drift_detection.drifted.count" => drifted_count,
      "gh.external_group_teams.drift_detection.skipped.count" => skipped_count,
    )
  end

  # Private: Read the drift-detection sweep cursor (last scanned ExternalGroupTeam id). Returns 0
  # (start of table) on a miss or if KV is unavailable.
  def drift_detection_cursor
    ExternalIdentities::KV.get(DRIFT_DETECTION_CURSOR_KEY).value { "0" }.to_i
  rescue GitHub::KV::UnavailableError
    0
  end

  # Private: Persist the drift-detection sweep cursor. Best-effort: if KV is unavailable we simply
  # re-scan the same window next run rather than failing the job.
  def update_drift_detection_cursor(value)
    with_write do
      ExternalIdentities::KV.set(DRIFT_DETECTION_CURSOR_KEY, value.to_s, expires: DRIFT_DETECTION_CURSOR_TTL.from_now)
    end
  rescue GitHub::KV::UnavailableError
    nil
  end

  def instrument_mismatch_event(external_group_team:, businesses_available_licenses: {}, skip_counts: false)
    external_group = external_group_team.external_group
    team = external_group_team.team
    business = external_group&.provider&.business
    organization = team&.organization
    business ||= organization&.business
    log_data = {
      "info.message" => "Mismatched EMU External Group Team",
      "code.namespace" => self.class.name,
      "code.function" => "perform",
      "gh.business.slug" => business&.slug,
      "gh.business.id" => business&.id,
      "gh.organization.name" => organization&.name,
      "gh.organization.id" => organization&.id,
      "gh.external_group.name" => external_group&.display_name,
      "gh.external_group.id" => external_group&.id,
      "gh.team.class" => team&.class.name,
      "gh.team.name" => team&.name,
      "gh.team.id" => team&.id,
      "gh.external_group_team.id" => external_group_team.id,
      "gh.business.available_licenses" => businesses_available_licenses[business&.id],
    }

    unless skip_counts
      log_data["gh.external_group.size"] = external_group&.active_user_ids.count
      log_data["gh.team.size"] = team&.member_ids.count
    end

    GitHub.logger.info(log_data)
  end

  def instrument_delete_event(external_group_team:, businesses_available_licenses:)
    external_group = external_group_team.external_group
    business = external_group&.provider&.business
    business ||= external_group_team.team&.organization&.business
    GitHub.logger.info(
      "info.message" => "Orphaned EMU External Group Team",
      "code.namespace" => self.class.name,
      "code.function" => "perform",
      "gh.business.slug" => business&.slug,
      "gh.business.id" => business&.id,
      "gh.external_group.name" => external_group&.display_name,
      "gh.external_group.id" => external_group&.id,
      "gh.external_group.size" => external_group&.active_user_ids.count,
      "gh.external_group_team.id" => external_group_team.id,
      "gh.team.id" => external_group_team.team_id,
      "gh.business.available_licenses" => businesses_available_licenses[business&.id],
    )
  end

  def businesses_available_licenses(external_group_teams:)
    businesses_available_licenses = {}
    external_group_teams.each do |egt|
      business = egt.external_group&.provider&.business
      business ||= egt.team&.organization&.business
      next unless business
      businesses_available_licenses[business.id] ||= business.available_invitable_licenses
    end
    businesses_available_licenses
  end

  # Builds the Ability count query, optionally applying optimizer hints and execution time limit
  # when the :scan_emu_ability_query_hints feature flag is enabled.
  def ability_team_count_query(ids, subject_type)
    scope = Ability.where(subject_id: ids, subject_type: subject_type, actor_type: "User", priority: Ability.priorities[:direct])

    if FeatureFlag.vexi.enabled?(:scan_emu_ability_query_hints, default: false)
      scope = scope.limit_execution_time(limit_ms: 5_000).optimizer_hints("INDEX(abilities subject_and_actor_and_priority_and_action)")
    end

    scope.group(:subject_id).count("DISTINCT actor_id")
  end

  # Returns the batch size for Ability queries. Tiered flags allow tuning in production
  # without redeploying. Checked smallest-first so the most conservative flag wins.
  def ability_query_batch_size
    if FeatureFlag.vexi.enabled?(:scan_emu_ability_batch_500, default: false)
      500
    elsif FeatureFlag.vexi.enabled?(:scan_emu_ability_batch_1000, default: false)
      1000
    elsif FeatureFlag.vexi.enabled?(:scan_emu_ability_batch_2500, default: false)
      2500
    else
      DEFAULT_ABILITY_BATCH_SIZE
    end
  end
end
