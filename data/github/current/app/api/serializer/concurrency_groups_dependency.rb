# typed: strict
# frozen_string_literal: true

module Api::Serializer::ConcurrencyGroupsDependency
  extend T::Helpers

  requires_ancestor { Api::Serializer }

  # Serialize the response for list-concurrency-groups-for-repository.
  sig do
    params(
      data: T::Hash[Symbol, T.untyped],
      options: T.any(T.nilable(T::Hash[Symbol, T.untyped]), GitHub::Options)
    ).returns(T::Hash[Symbol, T.untyped])
  end
  def concurrency_groups_list_hash(data, options = {})
    repo = data[:repo]
    groups = data[:groups] || []

    {
      total_count: data[:total_count].to_i,
      concurrency_groups: groups.map do |group|
        {
          group_name: group.group_name,
          group_url: url("/repos/#{repo.name_with_owner_for_api}/actions/concurrency_groups/#{ERB::Util.url_encode(group.group_name)}"),
          last_acquired_at: group.last_acquired_at ? time(Time.at(group.last_acquired_at.seconds).utc.to_datetime) : nil,
        }
      end,
    }
  end

  # Serialize the response for get-concurrency-group-for-repository.
  sig do
    params(
      data: T::Hash[Symbol, T.untyped],
      options: T.any(T.nilable(T::Hash[Symbol, T.untyped]), GitHub::Options)
    ).returns(T::Hash[Symbol, T.untyped])
  end
  def concurrency_group_hash(data, options = {})
    repo = data[:repo]
    instances = data[:instances] || []

    {
      group_name: data[:group_name],
      group_url: url("/repos/#{repo.name_with_owner_for_api}/actions/concurrency_groups/#{ERB::Util.url_encode(data[:group_name])}"),
      total_count: data[:total_count].to_i,
      group_members: instances.map { |item| item_hash(item, repo) },
    }
  end

  # Serialize the response for list-concurrency-groups-for-workflow-run.
  sig do
    params(
      data: T::Hash[Symbol, T.untyped],
      options: T.any(T.nilable(T::Hash[Symbol, T.untyped]), GitHub::Options)
    ).returns(T::Hash[Symbol, T.untyped])
  end
  def run_concurrency_groups_hash(data, options = {})
    repo = data[:repo]
    groups = data[:groups] || []

    {
      total_count: data[:total_count].to_i,
      concurrency_groups: groups.map do |group|
        {
          group_name: group[:group_name],
          group_url: url("/repos/#{repo.name_with_owner_for_api}/actions/concurrency_groups/#{ERB::Util.url_encode(group[:group_name])}"),
          group_members: (group[:items] || []).map { |inst| run_item_hash(inst, repo, group[:group_name]) },
        }
      end,
    }
  end

  private

  # Serialize a resolved item from resolve_queue_items output.
  sig { params(item: T::Hash[Symbol, T.untyped], repo: Repository).returns(T::Hash[Symbol, T.untyped]) }
  def item_hash(item, repo)
    nwo = repo.name_with_owner_for_api
    hash = {
      run_id: item[:workflow_run_id],
      run_name: item[:workflow_run_name],
      run_url: item[:workflow_run_id] ? url("/repos/#{nwo}/actions/runs/#{item[:workflow_run_id]}") : nil,
      run_html_url: item[:workflow_run_url] ? html_url(item[:workflow_run_url]) : nil,
      status: item[:acquired] ? "in_progress" : "pending",
    }

    if item[:display_type] == "job" || item[:display_type] == "reusable_workflow"
      hash[:job_id] = item[:check_run_id]
      hash[:job_name] = item[:display_name]
      hash[:job_url] = item[:check_run_id] ? url("/repos/#{nwo}/actions/jobs/#{item[:check_run_id]}") : nil
      hash[:job_html_url] = item[:url] ? html_url(item[:url]) : nil
    end

    hash
  end

  # Serialize an item entry from list-concurrency-groups-for-workflow-run's local data.
  sig { params(inst: T::Hash[Symbol, T.untyped], repo: Repository, group_name: String).returns(T::Hash[Symbol, T.untyped]) }
  def run_item_hash(inst, repo, group_name)
    nwo = repo.name_with_owner_for_api
    encoded_group = ERB::Util.url_encode(group_name)
    hash = {
      run_id: inst[:run_id],
      run_name: inst[:run_name],
      run_url: inst[:run_id] ? url("/repos/#{nwo}/actions/runs/#{inst[:run_id]}") : nil,
      run_html_url: inst[:run_url] ? html_url(inst[:run_url]) : nil,
      status: inst[:status],
    }

    hash[:position] = inst[:position].to_i

    if inst[:job_id]
      hash[:job_id] = inst[:job_id]
      hash[:job_name] = inst[:job_name]
      hash[:job_url] = url("/repos/#{nwo}/actions/jobs/#{inst[:job_id]}")
      hash[:job_html_url] = inst[:job_url] ? html_url(inst[:job_url]) : nil
    end

    # Choose the position_url query shape from the lease level so it round-trips
    # against get-concurrency-group-for-repository (ahead_of_run= rejects
    # job/reusable_workflow leases, and ahead_of_job= rejects workflow leases).
    # build_run_instance drops items whose check_run cannot be resolved, so by
    # the time we get here job_id is guaranteed present for job/reusable_workflow
    # leases.
    hash[:position_url] =
      case inst[:level]
      when "workflow"
        url("/repos/#{nwo}/actions/concurrency_groups/#{encoded_group}?ahead_of_run=#{inst[:run_id]}")
      when "job", "reusable_workflow"
        url("/repos/#{nwo}/actions/concurrency_groups/#{encoded_group}?ahead_of_job=#{inst[:job_id]}")
      end

    hash
  end
end
