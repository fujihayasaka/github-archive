# typed: false
# frozen_string_literal: true

class Businesses::Actions::RunnersController < Businesses::BusinessController
  include ::Actions::RunnersHelper
  include ::Actions::RunnerGroupsHelper
  include Actions::LargerRunnersHelper
  include Actions::LargerRunners::DefaultRunnersHelper

  before_action :business_owner_required
  before_action :ensure_actions_enabled
  before_action :ensure_tenant_exists
  before_action :business_not_downgraded_to_free_plan_required
  before_action :sudo_filter, only: [:destroy]
  before_action :business_full_plan_required

  javascript_bundle :settings

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    ApplicationRecord::Copilot,
    ApplicationRecord::Billing,
    only: [:runner_details]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    only: [:delete_runner_modal]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    ApplicationRecord::Copilot,
    ApplicationRecord::Billing,
    only: [:index]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    ApplicationRecord::Copilot,
    ApplicationRecord::Billing,
    only: [:new]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    ApplicationRecord::Copilot,
    ApplicationRecord::Billing,
    only: [:hosted_runners]

  def index
    page = (params.fetch(:page) { 1 }).to_i
    per_page = (params.fetch(:per_page) { 25 }).to_i

    query, label_filters = get_labels_from_query(params[:qr])
    query, public_ip_filter = get_public_ip_filter_from_query(query)

    filtered_runners = []
    hosted_runner_group = nil
    runner_groups.each do |group|
      if !group.hosted?
        group.runners.each do |runner|
          if query.blank? || runner.name.include?(query)
            if label_filters.empty? || label_filters.all? { |filter| runner.labels.any? { |label| label.name.downcase == filter.downcase } }
              runner.group_name = group.name
              runner.group = group
              runner.inherited = group.inherited?
              filtered_runners.append(runner)
            end
          end
        end

        group.runner_scale_sets.each do |scale_set|
          if query.blank? || scale_set.name.downcase.include?(query.downcase)
            if label_filters.empty? || label_filters.all? { |filter| scale_set.labels.any? { |label| label.name.downcase == filter.downcase } }
              filtered_runners.append(scale_set)
            end
          end
        end

      elsif page == 1 && query.blank? && label_filters.empty?
        hosted_runner_group = group
      end
    end

    runners_include_larger_runner = false
    larger_runners_enabled = this_business.can_use_larger_runners?
    if larger_runners_enabled
      larger_runners = Actions::LargerRunner.larger_runners_for(entity: this_business)
      runners_include_larger_runner = larger_runners.any?

      larger_runners.each do |larger_runner|
        if query.blank? || larger_runner.name.downcase.include?(query.downcase)
          group = runner_groups.detect { |runner_group| runner_group.id == larger_runner.runner_group_id }
          larger_runner.group = group
          if (label_filters.empty? || label_filters.all? { |filter| larger_runner.labels.any? { |label| label.name.downcase == filter.downcase } }) &&
            (public_ip_filter.nil? || larger_runner.is_public_ip_enabled == public_ip_filter)
            filtered_runners.append(larger_runner)
          end
        end
      end
    end

    filtered_runners = filtered_runners.sort_by { |runner| runner.view_priority }

    paginated_runners = WillPaginate::Collection.create(page, per_page, filtered_runners.length) do |group|
      group.replace(filtered_runners[((page - 1) * per_page), per_page] || [])
    end

    should_display_default_runners_banner = !runners_include_larger_runner && should_display_default_runners_banner?(entity: this_business, user: current_user)

    render "businesses/settings/actions/runners", locals: {
      runners: paginated_runners,
      hosted_runner_group: hosted_runner_group,
      runner_experience_enabled: true,
      larger_runners_enabled: larger_runners_enabled,
      runners_include_larger_runner: runners_include_larger_runner,
      should_display_default_runners_banner: should_display_default_runners_banner,
      should_display_custom_images_tab: is_custom_images_enabled?(entity: this_business)
    }
  end

  def new
    render "businesses/settings/actions/add_runner", locals: {
      platform: add_runner_data[:platform],
      os: add_runner_data[:os],
      architecture: add_runner_data[:architecture],
      downloads: add_runner_data[:downloads],
      platform_options: add_runner_data[:platform_options],
      token: add_runner_data[:token],
      selected_download: add_runner_data[:selected_download]
    }
  end

  def runner_details # rubocop:todo GitHub/UseRestfulActions
    runner = Actions::Runner.get(this_business, params[:id].to_i)

    return render_404 unless runner.present?

    runner_group = Actions::RunnerGroup.get(this_business, id: runner.runner_group_id)
    return render_404 unless runner_group.present?

    if runner.check_run_global_id.present?
      check_run = Checks.domain.check_runs.unsafe_for_id(Platform::Helpers::NodeIdentification.from_global_id(runner.check_run_global_id)[1].to_i)
    end

    render "businesses/settings/actions/runner_details", locals: {
      runner: runner,
      check_run: check_run,
      runner_group: runner_group,
      owner_settings: Actions::EnterpriseRunnersView.new(settings_owner: this_business, current_user: current_user)
    }
  end

  def update
    runner_group_id = params[:runner_group_id]&.to_i
    runner_id = params[:id].to_i

    runner = Actions::Runner.get(this_business, runner_id)
    runner_group = Actions::RunnerGroup.get(this_business, id: runner_group_id, include_runners: false)
    unless runner_group.present? && runner.present?
      flash[:error] = "Failed to move runner."
      redirect_to settings_actions_update_runner_enterprise_path(id: runner_id)
      return
    end

    runner_group = add_runners_for(this_business, id: runner_group_id, runners_ids: [runner_id])
    if runner_group.present?
      flash[:notice] = "Moved runner to #{runner_group.name}."
    else
      flash[:error] = "Failed to move runner."
    end

    redirect_to settings_actions_update_runner_enterprise_path(id: runner_id)
  end

  def destroy
    delete_status = delete_runner_for(this_business, id: params[:id].to_i, actor: current_user)

    if delete_status == "deleted"
      flash[:notice] = "Runner successfully deleted."
    else
      flash[:error] = "Sorry, there was a problem deleting your runner."
    end

    redirect_to settings_actions_runners_enterprise_path
  end

  def delete_runner_modal # rubocop:todo GitHub/UseRestfulActions
    scope = this_business.runner_deletion_token_scope
    token = current_user.signed_auth_token(scope: scope, expires: 1.hour.from_now)

    respond_to do |format|
      format.html do
        render(Actions::Runners::DeleteModalComponent.new(
          owner_settings: Actions::EnterpriseRunnersView.new(settings_owner: this_business, current_user: current_user),
          runner_id: params[:id],
          runner_os: params[:os],
          token: token,
        ), layout: false)
      end
    end
  end

  def hosted_runners # rubocop:todo GitHub/UseRestfulActions
    hosted_runner_group = runner_groups.find { |group| group.hosted? }

    if hosted_runner_group.nil?
      return render_404
    end

    runners = get_runners_with_assinged_request(entity: this_business, pool_id: hosted_runner_group.id)
    jobs = get_runner_jobs(runners: runners)
    paginated_jobs = get_paginated_jobs(jobs: jobs)

    render "businesses/settings/actions/hosted_runners", locals: {
      jobs: jobs,
      paginated_jobs: paginated_jobs,
      hosted_runner_group: hosted_runner_group,
      concurrency_limit: runners.count
    }
  end

  private

  def ensure_actions_enabled
    render_404 unless GitHub.actions_enabled?
  end

  def ensure_tenant_exists
    result = Launch::Twirp.deployer_client.setup_tenant(this_business)

    raise Timeout::Error, "Timeout fetching tenant" unless result.call_succeeded?
  end

  def add_runner_data # rubocop:todo GitHub/ControllersShouldUseMemoizeForMemoization
    return @add_runner_data if defined?(@add_runner_data)

    downloads = downloads_for(this_business)

    scope = this_business.runner_creation_token_scope
    expires_at = 1.hour.from_now
    token = current_user.signed_auth_token(scope: scope, expires: expires_at)

    @add_runner_data = runner_options(downloads: downloads, token: token)
  end

  def runner_groups # rubocop:todo GitHub/ControllersShouldUseMemoizeForMemoization
    @runner_groups ||= Actions::RunnerGroup.for_entity(
      this_business,
      include_runners: true,
      include_hosted_runner_groups: true,
      include_runner_scale_sets: true,
    )
  end
end
