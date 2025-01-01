# typed: false
# frozen_string_literal: true

class SettingOrganizationOrchestration < SettingOrchestration
  BATCH_SIZE = 100

  job_start

  step :assign_ungrouped_repos do
    return if group_path.present?

    # If this orchestrations targets the root group, assign any ungrouped repos to it first
    root_group = RepositoryGroup.find_or_create_group(owner: organization, group_path: "")
    ungrouped = RepositoryGroup.repositories_with_no_group(organization).in_batches(of: 1000) do |batch|
      # bulk insert repository_group_map records to assign these repos to the root group
      payload = batch.pluck(:id).map do |id|
        {
          repository_id: id,
          repository_group_id: root_group.id
        }
      end

      # Bulk insert the group maps.
      # Skip duplicate rows which would mean the repo just got assigned a group elsewhere
      RepositoryGroupMap.insert_all(payload)
    end
  end

  step :initialize_counts do
    # calculate the number of repos affected by this orchestration
    group = RepositoryGroup.find_by(owner: organization, group_path:)
    data[:total] = group.repositories_under.count
    data[:in_progress] = 0
    data[:succeeded] = 0
    data[:failed] = 0
  end

  step :update_status do
    # This step is run before every batch,
    # and again at the end, before we realize we have no batches left

    data[:succeeded] = data[:succeeded] + data[:in_progress]
    data[:in_progress] = 0

    update_metrics(:in_progress)
  end

  step :organization_fanout do
    watermark = data[:watermark] || 0

    group = RepositoryGroup.find_by(owner: organization, group_path:)
    repo_ids, new_watermark = group.repository_batch(watermark: watermark, batch_size: batch_size)

    # check if we're done
    return if repo_ids.empty?

    # sanity check that we are making forward progress
    return :failed, "Invalid watermark: #{new_watermark} <= #{watermark}" if new_watermark <= watermark

    # bulk insert does not execute the orchestration#populate method, so populate the data here
    payload = repo_ids.map do |id|
      {
        repository_id: id,
        parent_id: self.id,
        state: :created,
        attempts: 0,
        step_name: SettingRepositoryOrchestration.all_steps[0].name,
        data: data
      }
    end

    # bulk insert our child orchestrations
    SettingRepositoryOrchestration.insert_all!(payload)

    # load them into memory so they will be executed when we leave this step
    @blocking_orchestrations = SettingRepositoryOrchestration.created.where(parent_id: self.id)

    # update the watermark and in_progress counts
    data[:watermark] = new_watermark
    data[:in_progress] = repo_ids.size

    # set the next step back to the :update_status step
    set_next_step(:update_status)
  end

  step :finish do
    update_metrics(:finished)

    if failed_orchestrations.any?
      return :failed, "#{failed_orchestrations.size} child orchestration(s) failed: #{failed_orchestrations.first(5)}"
    end
  end

  def update_metrics(state)
    status =
    {
      state: state,
      total: data[:total],
      succeeded: data[:succeeded],
      failed: data[:failed]
    }

    channel = GitHub::WebSocket::Channels.setting_orchestration_status(self)
    GitHub::WebSocket.notify_setting_orchestration_status_channel(self, channel, status)
  end

  def batch_size
    # The FF percentage, if present, map to thresholds of 1 - 1000 repos
    # Must be an integer.
    percentage = GitHub.flipper[:setting_orchestration_batch_size].percentage_of_time_value
    size = percentage > 0 ? (percentage * 10).to_i : BATCH_SIZE
  end

  def skip_repository_id_validation
    # We don't have a repository here, we are targeting an Organization
    true
  end

  def target_uniqueness_condition_on_start
    # We don't have a repository here, we are targeting an Organization,
    # so we cannot validate we are targeting a unique repository
  end

  # Fail if another orchestration is in progress for the same organization
  def validate_no_duplicates
    orchestrations = self.class.active
    existing = orchestrations.find { |o| o.data[:organization_id] == data[:organization_id] }
    errors.add(:base, :duplicate, message: "orchestration in progress #{existing.id}") if existing
  end

  def stop_after_waiting?(failed_children)
    # Record any failures but don't stop now
    # We'll assess our success/failure state when we get through all batches
    if failed_children.any?
      failures = data[:failed_orchestrations] ||= []
      failures += failed_children.map(&:id)
      data[:failed_orchestrations] = failures.uniq
      data[:failed] += failed_children.size
      data[:in_progress] -= failed_children.size
    end
    false
  end

  def failed_orchestrations
    data[:failed_orchestrations] ||= []
  end
end
