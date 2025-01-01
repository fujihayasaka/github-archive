# typed: false
# frozen_string_literal: true

require "github-launch"
require "github/launch_client"

module Actions::RunnersHelper
  extend ActiveSupport::Concern
  include Actions::RunnersClientHelper

  included do
    before_action :ensure_actions_enabled
  end

  private

  OS_TO_PLATFORM_MAPPING = { "win" => "Windows", "osx" => "macOS", "linux" => "Linux" }
  DEFAULT_REPOSITORY_VISIBILITY = :PRIVATE_REPOSITORIES

  def delete_runner_for(owner, id:, actor:)
    resp = delete_runner_helper(owner, id, actor:)
    resp.value&.status
  end

  def downloads_for(owner)
    resp = list_runner_downloads(owner, use_runner_admin: use_runner_admin?(owner), do_experiment: do_runner_admin_experiment?(owner))
    resp.value&.downloads || []
  end

  def labels_for(owner)
    if use_runner_admin?(owner)
      runner_admin_client = GitHub.build_runner_admin_client(owner)
      resp = runner_admin_client.list_labels(owner: owner)
    else
      resp = Launch::Twirp.self_hosted_runners_client.list_labels(owner)
    end

    labels = resp.value&.labels || []

    # Fake filtering out system variables. This would otherwise be:
    #   labels.select { |label| label.type == "user" }
    system_labels = %w[self-hosted macos windows linux x64 x32]

    labels.reject { |label| system_labels.include?(label.name.downcase) || label.name.start_with?("_runnersvcpool-") }
  end

  def create_label_for(owner, name:)
    if use_runner_admin?(owner)
      GitHub::ActionsRunnerAdmin::Api::V1::Label.new(name: name, type: "user")
    else
      resp = Launch::Twirp::self_hosted_runners_client.create_label(owner, name)
      resp.value&.label
    end
  end

  def update_label_for(owner, runner_id:, labels:)

    using_runner_admin = use_runner_admin?(owner)
    if using_runner_admin
      runner_admin_client = GitHub.build_runner_admin_client(owner)
      resp = runner_admin_client.set_labels(
        owner: owner,
        runner_id: runner_id.to_i,
        labels: labels,
      )

      if updated_runner = resp&.value&.runner
        Actions::Runner.from_rpc_object(updated_runner, owner: owner, using_runner_admin: using_runner_admin)
      end
    else
      resp = Launch::Twirp::self_hosted_runners_client.replace_runner_labels(
        owner,
        runner_id: runner_id.to_i,
        label_ids: labels.map(&:to_i),
      )
      if updated_runner = resp&.value&.runners&.first
        Actions::Runner.from_rpc_object(updated_runner, owner: owner, using_runner_admin: using_runner_admin)
      end
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
    query = nil

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
    query = nil
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
    filter = nil
    query = nil

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

  def get_runners_with_assinged_request(entity:, pool_id:)
    # TODO: Call Runner Admin when the FF is enabled (https://github.com/github/actions-fusion/issues/2118)
    resp = Launch::Twirp.self_hosted_runners_client.list_runners(entity, pool_id: pool_id, include_assigned_request: true)

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
