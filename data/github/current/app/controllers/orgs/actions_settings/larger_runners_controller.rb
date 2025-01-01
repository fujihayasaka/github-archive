# typed: true
# frozen_string_literal: true

class Orgs::ActionsSettings::LargerRunnersController < Orgs::Controller
  include Actions::RunnersHelper
  include Actions::RunnerGroupsHelper
  include Actions::LargerRunnersHelper
  include Actions::LargerRunnersControllerHelper
  include Actions::LargerRunners::DefaultRunnersHelper
  include ApplicationController::VerifiedFetchDependency
  require "network_bundle/network_configuration_client"

  preload_features [:actions_custom_image], only: [:new, :create]
  preload_features [:larger_runners_custom_image_generation], only: [:new, :create, :runner_details]

  allow_verified_fetch only: [:create, :update, :get_public_ip_details]

  before_action :login_required
  before_action :ensure_user_has_runners_and_runner_groups_access
  before_action :ensure_trade_restrictions_allows_org_settings_access
  before_action :ensure_can_use_org_runners
  before_action do
    T.bind(self, Orgs::ActionsSettings::LargerRunnersController)
    ensure_larger_runners_enabled(entity: current_organization, actor: current_user, this_entity: this_organization)
    ensure_tenant_exists(entity: current_organization)
  end
  before_action :sudo_filter, only: [:destroy]
  around_action :record_metrics

  javascript_bundle :settings

  sig { returns(String) }
  def self.react_bundle_name
    "github-hosted-runners-settings" # match JS package name in /ui/packages, else you'll see a "key not found" error
  end

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Billing,
    only: [:new, :edit, :runner_details, :delete_larger_runner_modal, :get_public_ip_details]

  depends_on_clusters ApplicationRecord::Mysql5,
    only: [:new, :edit, :runner_details, :delete_larger_runner_modal]

  depends_on_clusters ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Repositories,
    ApplicationRecord::Copilot,
    only: [:new, :edit, :runner_details]

  def new
    current_organization.plan_subscription&.synchronize_later

    is_public_ip_allowed = is_public_ip_allowed_for_entity?(current_organization)

    # Render React-based UI for larger runner creation 🚀
    render_react_app(
      payload: build_new_runner_react_payload(
        owner: current_organization,
        runner_list_path: settings_org_actions_runners_path,
        is_public_ip_allowed: is_public_ip_allowed,
        public_ip_info_path: settings_org_actions_get_public_ip_details_path(current_organization),
      ),
      title: "Add new GitHub-hosted runner · " + current_organization.name,
      layout: "layouts/settings/actions_org_react",
      page_data: { selected_link: :organization_actions_settings_runners },
      custom_tags: build_custom_tags(T.must(request)),
    )
  end

  def runner_details # rubocop:todo GitHub/UseRestfulActions
    larger_runner_id = params[:id]&.to_i
    larger_runner = Actions::LargerRunner.get_larger_runner(current_organization, pool_id: larger_runner_id)

    return render_404 unless larger_runner.present?

    network_config_name = ""

    begin
      runner_group_id = larger_runner.runner_group_id
      network_configuration = network_config_client.list_configurations(current_organization, "actions", runner_group_id.to_s, true)
      if !network_configuration.empty? && !network_configuration[0].nil?
        network_config_name = network_configuration[0].name
      else
        network_config_name = "Disabled"
      end
    rescue ::NetworkBundle::NetworkConfigurationsException
      # Ignore these errors
    end

    check_run_ids = Actions::LargerRunner.get_check_runs_for_pool(current_organization, pool_id: larger_runner_id)
    total_check_runs = check_run_ids.count
    check_run_ids = check_run_ids.slice(((page - 1) * per_page), per_page)

    if check_run_ids.nil?
      redirect_to Actions::OrgRunnersView.new(settings_owner: current_organization, current_user: current_user).larger_runner_details_path(id: larger_runner_id, viewing_from_runner_group: viewing_from_runner_group?); return
    end

    check_runs = T.must(check_run_ids).map do |cr|
      run = Checks.domain.check_runs.unsafe_for_id(cr)
      raise ActiveRecord::RecordNotFound unless run
      run
    end

    paginated_check_runs = WillPaginate::Collection.create(page, per_page, total_check_runs) { |p| p.replace(check_runs) }

    render "settings/organization/actions/larger_runner_details",
      locals: {
        larger_runner: larger_runner,
        owner_settings: Actions::OrgRunnersView.new(settings_owner: current_organization, current_user: current_user),
        check_runs: paginated_check_runs,
        viewing_from_runner_group: viewing_from_runner_group?,
        image_generation_feature_enabled: is_custom_image_generation_enabled?(entity: current_organization),
        network_configuration_name: network_config_name,
      }
  end

  def edit
    larger_runner_id = params[:id]&.to_i
    larger_runner = Actions::LargerRunner.get_larger_runner(current_organization, pool_id: larger_runner_id)

    return render_404 unless larger_runner.present? && larger_runner.is_in_editable_state?

    is_public_ip_allowed = is_public_ip_allowed_for_entity?(current_organization)

    # Render React-based UI for larger runner editing 🚀
    render_react_app(
      payload: build_edit_runner_react_payload(
        owner: current_organization,
        larger_runner: larger_runner,
        runner_list_path: settings_org_actions_runners_path,
        is_public_ip_allowed: is_public_ip_allowed,
        public_ip_info_path: settings_org_actions_get_public_ip_details_path(current_organization),
      ),
      title: "Edit GitHub-hosted runner " + larger_runner.name + " · " + current_organization.name,
      layout: "layouts/settings/actions_org_react",
      page_data: { selected_link: :organization_actions_settings_runners },
      custom_tags: build_custom_tags(T.must(request)),
    )
  end

  def create
    body = JSON.parse(request&.body.read)
    runner_group_id = body["runnerGroupId"].to_i

    # Check if the runner_group got deleted while we were creating the runners
    if is_runner_group_id_missing?(entity: current_organization, runner_group_id: runner_group_id)
      return render_validation_error(error: error_invalid_group)
    end

    machine_spec = submitted_machine_spec(body["machineSpecId"], current_organization)
    if machine_spec.nil?
      return render_validation_error(error: error_larger_runner_is_invalid)
    end

    if machine_spec.is_gpu_spec? && should_disable_gpu_runners_for_untrusted?(current_organization)
      return render_validation_error(error: error_larger_runner_is_invalid)
    end

    # Verify the policy is enabled when asking for a runner that can create custom images
    is_image_gen_enabled = body["isImageGenerationEnabled"]
    if HostedRunnersHelper::is_custom_images_policy_feature_enabled?(entity: current_organization)
      if is_image_gen_enabled && !HostedRunnersHelper::is_custom_images_permitted?(current_organization)
        return render_validation_error(error: error_custom_image_generation_disabled)
      end
    end

    larger_runner = Actions::LargerRunner.new(
      name: body["name"],
      platform: body["platform"],
      runner_group_id: runner_group_id,
      labels: body["labels"],
      maximum_runners: body["maximumConcurrentJobs"],
      image: convert_to_image_key(source: body["imageSource"], image_id: body["imageId"].to_s, version: body["imageVersion"]),
      machine_spec_id: body["machineSpecId"],
      machine_spec: machine_spec,
      is_public_ip_enabled: body["isPublicIpEnabled"],
      persistent_os_disk: is_custom_images_enabled?(entity: current_organization) && is_image_gen_enabled,
      image_sas_uri: is_custom_image_uploading_enabled?(entity: current_organization) ? body["imageSasUri"] : ""
    )

    if is_vnet_and_public_ip_enabled(entity: current_organization, is_public_ip_enabled: larger_runner.is_public_ip_enabled, runner_group_id: runner_group_id)
      return render_validation_error(error: error_public_ip_vnet_conflict)
    end

    if is_public_ip_creation_forbidden?(entity: current_organization, is_public_ip_enabled: larger_runner.is_public_ip_enabled)
      return render_validation_error(error: error_invalid_public_ip)
    end

    if !larger_runner.maximum_runners_valid?(gpu_limit: gpu_maximum_runners_for(entity: current_organization))
      return render_validation_error(error: error_maximum_runner_is_invalid)
    end

    if !larger_runner.valid?(:create)
      return render_validation_error(error: error_larger_runner_is_invalid)
    end

    begin
      result = create_larger_runners_for(current_organization, larger_runner: larger_runner, actor: current_user)
      if !result.call_succeeded?
        error_message = result.options[:message] || unknown_failure_message
        render json: { success: false, errors: [error_message], data: {} }, status: result.status
      else
        render json: { success: true, errors: [], data: { runnerId: result.value.pool.id } }, status: :ok
      end
    end
  end

  def update
    larger_runner_id = params[:id]&.to_i
    return render_404 unless larger_runner_id.present?

    larger_runner_being_updated = Actions::LargerRunner.get_larger_runner(current_organization, pool_id: larger_runner_id)

    body = JSON.parse(request&.body.read)
    runner_group_id = body["runnerGroupId"].to_i

    if larger_runner_being_updated.nil?
      return render_validation_error(error: error_larger_runner_is_missing)
    end

    # Check if the runner_group got deleted while we were creating the runners
    if is_runner_group_id_missing?(entity: current_organization, runner_group_id: runner_group_id)
      return render_validation_error(error: error_invalid_group(is_update: true))
    end

    larger_runner = Actions::LargerRunner.new(
      id: larger_runner_id,
      name: body["name"],
      runner_group_id: runner_group_id,
      maximum_runners: body["maximumConcurrentJobs"],
      machine_spec_id: body["machineSpecId"].present? ? body["machineSpecId"] : larger_runner_being_updated.machine_spec_id,
      machine_spec: submitted_machine_spec(body["machineSpecId"], current_organization),
      is_public_ip_enabled: body["isPublicIpEnabled"],
      image: Actions::LargerRunner::ImageKey.new(
        source: larger_runner_being_updated.image&.source,
        id: body["imageId"].to_s.present? ? body["imageId"].to_s : larger_runner_being_updated.image&.id,
        version: body["imageVersion"].present? ? body["imageVersion"] : larger_runner_being_updated.image&.version
      ),
    )

    if is_vnet_and_public_ip_enabled(entity: current_organization, is_public_ip_enabled: larger_runner.is_public_ip_enabled, runner_group_id: runner_group_id)
      return render_validation_error(error: error_public_ip_vnet_conflict)
    end

    is_public_ip_change_forbidden = is_public_ip_change_forbidden?(entity: current_organization, enable_public_ip: larger_runner.is_public_ip_enabled, runner_id: larger_runner_id)
    if is_public_ip_change_forbidden
      return render_validation_error(error: error_invalid_public_ip(is_update: true))
    end

    if !larger_runner.maximum_runners_valid?(gpu_limit: gpu_maximum_runners_for(entity: current_organization))
      return render_validation_error(error: error_maximum_runner_is_invalid)
    end

    if !larger_runner.valid?
      return render_validation_error(error: error_larger_runner_is_invalid(is_update: true))
    end

    begin
      result = update_larger_runners_for(current_organization, larger_runner: larger_runner, actor: current_user)
      if !result.call_succeeded?
        error_message = result.options[:message] || unknown_failure_message(is_update: true)
        render json: { success: false, errors: [error_message], data: {} }, status: result.status
      else
        render json: { success: true, errors: [], data: { runnerId: result.value.pool.id } }, status: :ok
      end
    end
  end

  def destroy
    larger_runner_id = params[:id]
    return render_404 unless larger_runner_id.present?

    result = delete_larger_runners_for(current_organization, id: larger_runner_id&.to_i, actor: current_user)

    if !result.call_succeeded?
      # TODO: in the future, we can use result&.options&.fetch(:message, nil) when the launch error messaging improves
      message = "Failed to delete GitHub-hosted runner. Please try again. If the problem persists, we recommend you check https://www.githubstatus.com/ to see the service status of actions or contact support at #{GitHub.contact_support_url} for additional information or help."
      #TODO: Runner deletes but error is thrown from service
      flash[:error] = message
    else
      flash[:notice] = "GitHub-hosted runner deleted"
    end

    runner_group_id = viewing_from_runner_group? ? result.value&.pool&.runner_group_id : nil
    if runner_group_id.present?
      redirect_to settings_org_actions_runner_group_path(current_organization, id: runner_group_id)
    else
      redirect_to settings_org_actions_runners_path(current_organization)
    end
  end

  def delete_larger_runner_modal # rubocop:todo GitHub/UseRestfulActions
    larger_runner_id = params[:id]
    return render_404 unless larger_runner_id.present?

    scope = current_organization.runner_deletion_token_scope
    token = T.must(current_user).signed_auth_token(scope: scope, expires: 1.hour.from_now)

    respond_to do |format|
      format.html do
        render(Actions::LargerRunners::LargerRunnerDeleteModalComponent.new(
          owner_settings: Actions::OrgRunnersView.new(settings_owner: current_organization, current_user: current_user),
          larger_runner_id: params[:id].to_i,
          token: token,
          viewing_from_runner_group: viewing_from_runner_group?,
        ), layout: false)
      end
    end
  end

  def check_name # rubocop:todo GitHub/UseRestfulActions
    if params[:value].match(/[a-zA-Z0-9\-\_.]{1,64}/).to_s != params[:value].to_s
      render partial: "settings/organization/actions/check_name_error", status: :unprocessable_entity, formats: :html
    else
      head :ok, content_type: "text/html"
    end
  end

  def setup_default_runners # rubocop:todo GitHub/UseRestfulActions
    GitHub.dogstats.increment("actions_larger_runners_default_setup_modal")
    runner_group_id = ensure_default_runners_group_exists_and_get_id(entity: current_organization)

    if runner_group_id.nil?
      flash[:error] = "Failed to create runner group for Default Larger Runners. We recommend you check https://www.githubstatus.com/ to see the service status of actions or contact support at #{GitHub.contact_support_url} for additional information or help."
      redirect_to settings_org_actions_runners_path(current_organization)
      return
    end

    all_runners_created_successfully, at_least_one_runner_created_successfully = create_default_larger_runners(entity: current_organization, group_id: runner_group_id, actor: T.must(current_user))

    # making sure banner will not be displayed again if customer deletes runners
    if at_least_one_runner_created_successfully
      T.must(current_user).dismiss_organization_notice(DEFAULT_RUNNERS_BANNER_NOTICE_NAME, current_organization, for_whole_org: true)
    end

    if all_runners_created_successfully
      flash[:notice] = "Default Larger Runners provisioning"
    else
      flash[:error] = "Failed to create some Default Larger Runners. We recommend you check https://www.githubstatus.com/ to see the service status of actions or contact support at #{GitHub.contact_support_url} for additional information or help."
      GitHub::Logger.info({
        msg: "failed to create some default larger runners",
        "entity.login": current_organization.display_login,
        "entity.class": current_organization.class.to_s })
    end

    redirect_to settings_org_actions_runner_group_path(current_organization, id: runner_group_id)
  end

  def get_public_ip_details # rubocop:todo GitHub/UseRestfulActions
    runners_with_public_ip = Actions::LargerRunner.larger_runners_for(entity: current_organization, is_public_ip_enabled: true)
    total_ip_count = public_ip_usage_limit_for(current_organization)
    used_ip_count = runners_with_public_ip.count

    render json: {
      usedIpCount: used_ip_count,
      totalIpCount: total_ip_count
    }
  end

  private

  def per_page
    per_page = params[:per_page].to_i
    per_page = per_page.zero? ? 25 : per_page

    per_page.clamp(1, 25)
  end

  def page
    page = params[:page].to_i

    [page, 1].max
  end

  def viewing_from_runner_group?
    params[:viewing_from_runner_group] == "true"
  end

  def viewing_from_details?
    params[:viewing_from_details] == "true"
  end

  def record_metrics
    stats.collect_metrics do
      yield
      response
    end
  end

  def stats
    Actions::LargerRunners::LargerRunnersControllerStats.new(
      controller: controller_name_with_namespace,
      action: action_name,
      method: GitHub::TaggingHelper.request_method(env)
    )
  end

  def render_validation_error(error:)
    render json: { error: error, error_category: "known" }, status: :unprocessable_entity
  end

  def network_config_client
    NetworkBundle::NetworkConfigurationClient.create
  end
end
