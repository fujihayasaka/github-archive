# typed: false
# frozen_string_literal: true

require "github-launch"
require "github/launch_client"

module Actions::RunnersHelper
  extend ActiveSupport::Concern
  include Actions::RunnersClientHelper
  include Api::App::ActionsRunnerAdminHelper
  include Actions::RunnersClientHelper

  included do
    before_action :ensure_actions_enabled
  end

  private

  Entity = T.type_alias { T.any(Organization, Business, Repository) }

  OS_TO_PLATFORM_MAPPING = { "win" => "Windows", "osx" => "macOS", "linux" => "Linux" }
  DEFAULT_REPOSITORY_VISIBILITY = :PRIVATE_REPOSITORIES

  def delete_runner_for(owner, id:, actor:)
    resp, destination = delete_runner_helper(owner, id, use_runner_admin: use_runner_admin?(owner, is_write: true), actor: actor)
    [resp.value&.status, destination]
  end

  def downloads_for(owner, is_ui_read: false)
    resp = list_runner_downloads(owner, use_runner_admin: use_runner_admin?(owner, is_ui_read: is_ui_read), do_experiment: do_runner_admin_experiment?(owner))
    resp.value&.downloads || []
  end

  sig { params(owner: T.untyped, is_ui_read: T::Boolean).returns(T.untyped) }
  def labels_for(owner, is_ui_read: false)
    resp = list_labels(
      owner,
      use_runner_admin: use_runner_admin?(owner, is_ui_read: is_ui_read),
      do_experiment: do_runner_admin_experiment?(owner),
    )

    labels = resp.value&.labels || []

    # Fake filtering out system variables. This would otherwise be:
    #   labels.select { |label| label.type == "user" }
    system_labels = %w[self-hosted macos windows linux x64 x32]

    labels.reject { |label| system_labels.include?(label.name.downcase) || label.name.start_with?("_runnersvcpool-") }
  end

  def create_label_for(owner, name:)
    if use_runner_admin?(owner, is_write: true)
      runner_admin_client = GitHub.build_runner_admin_client(owner)
      result = runner_admin_client.get_runner_v2_flow_status(owner: owner)
      use_v2_flow = result.value.use_v2_flow if result.call_succeeded?

      if use_v2_flow.nil?
        Rails.logger.error("Failed to determine if runner admin v2 flow is enabled, defaulting to v1 flow")
        use_v2_flow = false
      end

      if !use_v2_flow
        resp = Launch::Twirp::self_hosted_runners_client.create_label(owner, name)
        return resp.value&.label if resp.call_succeeded?
      end
      GitHub::ActionsRunnerAdmin::Api::V1::Label.new(name: name, type: "user")
    else
      resp = Launch::Twirp::self_hosted_runners_client.create_label(owner, name)
      resp.value&.label
    end
  end

  sig { params(owner: Entity, runner_id: Integer, labels: T::Array[T.untyped]).returns([T.nilable(Actions::Runner), T.nilable(String)]) }
  def update_label_for(owner, runner_id:, labels:)
    # Try runner admin first if available
    if use_runner_admin?(owner, is_write: true)
      resp = GitHub.build_runner_admin_client(owner).set_labels(
        owner: owner,
        runner_id: runner_id.to_i,
        labels: labels,
      )

      # Check if we got a 403 status - if so, fall through to pipelines
      if resp.respond_to?(:status) && resp.status == 403
        Rails.logger.info("Runner admin returned 403, falling back to pipelines")
      elsif updated_runner = resp&.value&.runner
        return [Actions::Runner.from_rpc_object(updated_runner, owner: owner), Actions::RunnerGroupsClientHelper::WRITTEN_TO_RUNNER_ADMIN]
      end
    end

    # Try pipelines
    resp = Launch::Twirp::self_hosted_runners_client.replace_runner_labels(
      owner,
      runner_id: runner_id.to_i,
      label_ids: labels.map(&:to_i),
    )
    if updated_runner = resp.value&.runners&.first
      [Actions::Runner.from_rpc_object(updated_runner, owner: owner), Actions::RunnerGroupsClientHelper::WRITTEN_TO_LAUNCH]
    end
  end

  def ensure_actions_enabled
    render_404 unless GitHub.actions_enabled?
  end

  def ensure_can_use_org_runners
    render_404 unless can_use_org_runners?
  end

  def can_use_org_runners?(org = current_organization)
    Billing::ActionsPermission.new(org).status[:error][:reason] != "PLAN_INELIGIBLE"
  end

  def runner_options(downloads:, token:)
    os_options = downloads.map { |d| d.os }.uniq

    if params[:os].blank? && params[:arch].blank?
      browser = Browser.new(request.user_agent)
      if browser.known?
        os_param = "osx" if browser.platform.mac?
        os_param = "linux" if browser.platform.linux?
        os_param = "win" if browser.platform.windows?
      end
    end

    os_param ||= params[:os].to_s.downcase
    os = os_options.include?(os_param) ? os_param : "linux"
    platform = OS_TO_PLATFORM_MAPPING[os]

    architecture_options = downloads.find_all { |d| d.os == os }.map { |d| d.architecture }

    arch_param = (params[:arch] || "").downcase
    architecture = architecture_options.include?(arch_param) ? arch_param : "x64"

    selected_download = downloads.find { |d| d.os == os && d.architecture == architecture }
    platform_options = os_options.map { |d| { os: d, platform: OS_TO_PLATFORM_MAPPING[d] } }

    {
      os: os,
      platform: platform,
      architecture: architecture,
      platform_options: platform_options,
      downloads: downloads,
      selected_download: selected_download,
      token: token
    }
  end

  def get_filter_info_from_query(filter_level, q)
    query = T.let(nil, T.nilable(String))

    if q.present?
      arr = Search::ParsedQuery.parse(q, terms: [:level])
      arr.each do |parsed|
        if parsed.is_a? String
          query = parsed
        elsif parsed[0] == :level
          filter_level = parsed[1]
        end
      end
    end
    [query, filter_level]
  end

  def get_labels_from_query(q)
    query = T.let(nil, T.nilable(String))
    labels = []
    if q.present?
      arr = Search::ParsedQuery.parse(q, terms: [:label])
      arr.each do |parsed|
        if parsed.is_a? String
          query = parsed
        elsif parsed[0] == :label
          labels.append(parsed[1])
        end
      end
    end
    [query, labels]
  end

  def get_public_ip_filter_from_query(q)
    filter = T.let(nil, T.nilable(T::Boolean))
    query = T.let(nil, T.nilable(String))

    if q.present?
      arr = Search::ParsedQuery.parse(q, terms: [:public_ip])
      arr.each do |parsed|
        if parsed.is_a? String
          query = parsed
        elsif parsed[0] == :public_ip
          if parsed[1].downcase == "enabled"
            filter = true
          elsif parsed[1].downcase == "disabled"
            filter = false
          end
        end
      end
    end
    [query, filter]
  end

  sig { params(entity: T.untyped, pool_id: Integer).returns(T::Array[Actions::Runner]) }
  def get_hosted_runners_with_assigned_request(entity:, pool_id:)
    # Don't call runner admin since this is for hosted runners only
    resp = list_runners_helper(entity, use_runner_admin: false, pool_id:, include_assigned_request: true)

    contents = resp.value&.runners
    contents.present? ? Actions::Runner.from_rpc_collection(Array.new(contents)) : []
  end

  def get_runner_jobs(runners:)
    runners_with_check_runs = runners.select { |runner| runner.check_run_global_id.present? }
    jobs = runners_with_check_runs.map do |runner|
      check_run = Checks.domain.check_runs.unsafe_for_id(Platform::Helpers::NodeIdentification.from_global_id(runner.check_run_global_id)[1].to_i)
      {
        check_run:,
        os: runner.os
      }
    end.compact
    jobs
  end

  def get_paginated_jobs(jobs:)
    page = (params.fetch(:page) { 1 }).to_i
    per_page = (params.fetch(:per_page) { 25 }).to_i
    paginated_jobs = WillPaginate::Collection.create(page, per_page, jobs.length) do |pj|
      pj.replace(jobs[((page - 1) * per_page), per_page] || [])
    end
    paginated_jobs
  end

end
