# typed: true
# frozen_string_literal: true

class Orgs::ActionsSettings::RunnersController < Orgs::Controller
  include Actions::RunnersHelper
  include Actions::RunnerGroupsHelper
  include Actions::LargerRunnersHelper
  include Actions::LargerRunners::DefaultRunnersHelper

  before_action :login_required
  before_action :ensure_user_has_runners_and_runner_groups_access
  before_action :ensure_trade_restrictions_allows_org_settings_access
  before_action :ensure_can_use_org_runners, except: [:runners]
  before_action :ensure_tenant_exists, only: [:add_new_runner, :runners]
  before_action :sudo_filter, only: [:delete_runner_modal, :delete_runner]

  javascript_bundle :settings

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:runners],
    optional: true

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    ApplicationRecord::Billing,
    ApplicationRecord::Copilot,
    only: [:add_new_runner]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Billing,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql5,
    only: [:add_runner_instructions]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Billing,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Repositories,
    only: [:runners]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Repositories,
    ApplicationRecord::Billing,
    only: [:runner_details]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Billing,
    ApplicationRecord::Copilot,
    ApplicationRecord::Repositories,
    only: [:hosted_runners]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:runner_details],
    optional: true

  def list_runners # rubocop:todo GitHub/UseRestfulActions
    redirect_to settings_org_actions_runners_path
  end

  def runners # rubocop:todo GitHub/UseRestfulActions
    force_launch = should_force_launch?(owner: current_organization, params: params)
    runner_groups = Actions::RunnerGroup.for_entity(
      current_organization,
      include_runners: true,
      include_runner_scale_sets: true,
      include_hosted_runner_groups: !current_organization.business.present?,
      is_ui_read: true,
      force_launch: force_launch
    )
    page = (params.fetch(:page) { 1 }).to_i
    per_page = (params.fetch(:per_page) { 25 }).to_i

    filtered_runners = []
    hosted_runner_group = T.let(nil, T.untyped)
    filter_level = restricted_plan_for_runner_groups?(current_organization) ? nil : "All"
    query, filter_level = get_filter_info_from_query(filter_level, params[:qr])
    query, label_filters = get_labels_from_query(query)
    query, public_ip_filter = get_public_ip_filter_from_query(query)

    # show the hosted group?
    if query.blank? && page == 1 && (filter_level == "All" || filter_level.nil?) && label_filters.empty?
      runner_groups.select { |group| group.hosted? }.each do |group|
        if !group.inherited?
          # only use the organization level hosted group to prevent leaking data across org boundaries
          hosted_runner_group = group
        end
      end
    end

    runner_groups.each do |group|
      if !group.hosted?
        if filter_level == "All" || (filter_level == "Enterprise" && group.inherited?) || (filter_level == "Organization" && !group.inherited?) || (filter_level.nil? && group.default?)
          group.runners.each do |runner|
            if query.blank? || runner.name.downcase.include?(query.downcase)
              if label_filters.empty? || label_filters.all? { |filter| runner.labels.any? { |label| label.name.downcase == filter.downcase } }
                runner.group = group
                runner.group_name = group.name
                runner.scoped_runner_group_id = group.id
                runner.inherited = group.inherited?
                filtered_runners.append(runner)
              end
            end
          end

          group.runner_scale_sets.each do |scale_set|
            if query.blank? || scale_set.name.downcase.include?(query.downcase)
              if label_filters.empty? || label_filters.all? { |filter| scale_set.labels.any? { |label| label.name.downcase == filter.downcase } }
                scale_set.inherited = group.inherited?
                filtered_runners.append(scale_set)
              end
            end
          end

        end
      end
    end

    runners_include_larger_runner = false
    larger_runners_enabled = current_organization.can_use_larger_runners?
    if larger_runners_enabled
      larger_runners = Actions::LargerRunner.larger_runners_for(entity: current_organization)

      if filter_level == "Enterprise" && current_organization.business.present?
        larger_runners = larger_runners.select { |runner| runner.inherited }
      elsif filter_level == "Organization"
        larger_runners = larger_runners.select { |runner| !runner.inherited }
      end

      runners_include_larger_runner = larger_runners.any?

      larger_runners.each do |larger_runner|
        if query.blank? || larger_runner.name.downcase.include?(query.downcase)
          if (label_filters.empty? || label_filters.all? { |filter| larger_runner.labels.any? { |label| label.name.downcase == filter.downcase } }) &&
            (public_ip_filter.nil? || larger_runner.is_public_ip_enabled == public_ip_filter)
            group = runner_groups.detect { |runner_group| runner_group.id == larger_runner.runner_group_id }
            larger_runner.group = group if larger_runner.group.nil?
            filtered_runners.append(larger_runner)
          end
        end
      end
    end

    filtered_runners = filtered_runners.sort_by { |runner| runner.view_priority }

    paginated_runners = WillPaginate::Collection.create(page, per_page, filtered_runners.length) do |runner|
      runner.replace(filtered_runners[((page - 1) * per_page), per_page] || [])
    end

    should_display_default_runners_banner = !runners_include_larger_runner && should_display_default_runners_banner?(entity: current_organization, user: current_user)

    log_access_metrics

    render "settings/organization/actions/runners", locals: {
      can_use_entity_selection: can_use_entity_selection?,
      can_use_org_runners: can_use_org_runners?,
      runners: paginated_runners,
      inherited_runners: [],
      hosted_runner_group: hosted_runner_group,
      filter_level: filter_level,
      filter_query: query,
      can_create_runner_groups: !restricted_plan_for_runner_groups?(current_organization),
      runner_experience_enabled: true,
      larger_runners_enabled: larger_runners_enabled,
      runners_include_larger_runner: runners_include_larger_runner,
      should_display_default_runners_banner: should_display_default_runners_banner
    }
  end

  def add_new_runner # rubocop:todo GitHub/UseRestfulActions
    render "settings/organization/actions/add_runner", locals: {
      platform: add_runner_data[:platform],
      os: add_runner_data[:os],
      architecture: add_runner_data[:architecture],
      downloads: add_runner_data[:downloads],
      platform_options: add_runner_data[:platform_options],
      token: add_runner_data[:token],
      selected_download: add_runner_data[:selected_download]
    }
  end

  def update_runner # rubocop:todo GitHub/UseRestfulActions
    runner_group_id = params[:runner_group_id]&.to_i
    runner_id = params[:id].to_i

    runner = Actions::Runner.get(current_organization, runner_id, is_ui_read: true)
    runner_group = Actions::RunnerGroup.get(current_organization, id: runner_group_id, include_runners: false, is_ui_read: true)
    unless runner_group.present? && runner.present?
      flash[:error] = "Failed to move runner."
      redirect_to settings_org_actions_update_runner_path(id: runner_id)
      return
    end

    resp, destination = add_runners_for(current_organization, id: runner_group_id, runners_ids: [runner_id])
    if resp.value&.runner_group.present?
      flash[:notice] = "Moved runner to #{resp.value&.runner_group.name}."
    else
      flash[:error] = "Failed to move runner."
    end

    redirect_to settings_org_actions_update_runner_path(id: runner_id, written_to: destination)
  end

  def add_runner_instructions # rubocop:todo GitHub/UseRestfulActions
    return head 404 unless request.xhr?
    return head 202 if add_runner_data[:downloads].empty?

    render partial: "actions/settings/add_runner_instructions", locals: {
      platform: add_runner_data[:platform],
      os: add_runner_data[:os],
      architecture: add_runner_data[:architecture],
      downloads: add_runner_data[:downloads],
      platform_options: add_runner_data[:platform_options],
      token: add_runner_data[:token],
      selected_download: add_runner_data[:selected_download],
      registration_url: "#{GitHub.url}/#{current_organization}"
    }
  end

  def runner_details # rubocop:todo GitHub/UseRestfulActions
    force_launch = should_force_launch?(owner: current_organization, params: params)
    runner = Actions::Runner.get(current_organization, params[:id].to_i, is_ui_read: true, force_launch: force_launch)

    return render_404 unless runner.present?

    runner_group = Actions::RunnerGroup.get(current_organization, id: runner.runner_group_id, is_ui_read: true, force_launch: force_launch)
    return render_404 unless runner_group.present?

    if runner.check_run_global_id.present?
      check_run = Checks.domain.check_runs.unsafe_for_id(Platform::Helpers::NodeIdentification.from_global_id(runner.check_run_global_id)[1].to_i)
    end

    render "settings/organization/actions/runner_details", locals: {
      runner: runner,
      check_run: check_run,
      runner_group: runner_group,
      owner_settings: Actions::OrgRunnersView.new(settings_owner: current_organization, current_user: current_user)
    }
  end

  def delete_runner_modal # rubocop:todo GitHub/UseRestfulActions
    scope = current_organization.runner_deletion_token_scope
    token = current_user.signed_auth_token(scope: scope, expires: 1.hour.from_now)

    respond_to do |format|
      format.html do
        render partial: "settings/organization/actions/delete_runner_modal",
               locals: { token: token, runner_id: params[:id], runner_os: params[:os] }
      end
    end
  end

  def delete_runner # rubocop:todo GitHub/UseRestfulActions
    delete_status, destination = delete_runner_for(current_organization, id: params[:id].to_i, actor: current_user)

    if delete_status == "deleted"
      flash[:notice] = "Runner successfully deleted."
    else
      flash[:error] = "Sorry, there was a problem deleting your runner."
    end

    redirect_to settings_org_actions_runners_path(written_to: destination)
  end

  def hosted_runners # rubocop:todo GitHub/UseRestfulActions
    return render_404 if current_organization.business.present?

    runner_groups = Actions::RunnerGroup.for_entity(
      this_organization,
      include_hosted_runner_groups: true,
      is_ui_read: true,
      force_launch: true,
    )

    runners_with_check_runs = []
    hosted_runner_group = runner_groups.find { |group| group.hosted? && !group.inherited? }

    if hosted_runner_group.nil?
      return render_404
    end

    runners = get_hosted_runners_with_assigned_request(entity: this_organization, pool_id: hosted_runner_group.id)
    jobs = get_runner_jobs(runners: runners)
    paginated_jobs = get_paginated_jobs(jobs: jobs)

    render "settings/organization/actions/hosted_runners", locals: {
      jobs: jobs,
      paginated_jobs: paginated_jobs,
      hosted_runner_group: hosted_runner_group,
      concurrency_limit: runners.count
    }
  end

  private

  # Metrics as part of https://github.com/github/actions-sudo/issues/475
  # Tracking how many users are accessing settings as non admins
  def log_access_metrics
    if current_organization.adminable_by?(current_user)
      GitHub.dogstats.increment("actions.org.settings.runners_controller", tags: ["admin:true"])
    else
      GitHub.dogstats.increment("actions.org.settings.runners_controller", tags: ["admin:false"])
    end
  end

  def add_runner_data # rubocop:todo GitHub/ControllersShouldUseMemoizeForMemoization
    return @add_runner_data if defined?(@add_runner_data)

    downloads = downloads_for(current_organization, is_ui_read: true)

    scope = current_organization.runner_creation_token_scope
    expires_at = 1.hour.from_now
    token = current_user.signed_auth_token(scope: scope, expires: expires_at)

    @add_runner_data = runner_options(downloads: downloads, token: token)
  end

  def ensure_tenant_exists_when_ghes
    ensure_tenant_exists if GitHub.enterprise?
  end

  def ensure_tenant_exists
    if current_organization.business
      result = Launch::Twirp.deployer_client.setup_tenant(current_organization.business)
      raise Timeout::Error, "Timeout fetching tenant" unless result.call_succeeded?
    end

    result = Launch::Twirp.deployer_client.setup_tenant(current_organization)
    raise Timeout::Error, "Timeout fetching tenant" unless result.call_succeeded?
  end

  def can_use_entity_selection?
    Billing::ActionsPermission.new(current_organization).status[:error][:reason] != "PLAN_INELIGIBLE" || GitHub.enterprise?
  end
end
