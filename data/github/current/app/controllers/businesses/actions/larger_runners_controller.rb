# typed: true
# frozen_string_literal: true

class Businesses::Actions::LargerRunnersController < Businesses::BusinessController
  include ::Actions::RunnersHelper
  include ::Actions::RunnerGroupsHelper
  include ::Actions::LargerRunnersHelper
  include ::Actions::LargerRunnersControllerHelper
  include ::Actions::LargerRunners::DefaultRunnersHelper
  include ApplicationController::VerifiedFetchDependency

  preload_features [:actions_custom_image], only: [:new, :create]
  preload_features [:larger_runners_custom_image_generation], only: [:new, :runner_details]

  allow_verified_fetch only: [:create, :update, :get_public_ip_details]

  before_action :business_owner_required
  before_action :business_not_downgraded_to_free_plan_required
  before_action do
    T.bind(self, Businesses::Actions::LargerRunnersController)
    ensure_larger_runners_enabled(entity: current_business, actor: current_user, this_entity: this_business)
    ensure_tenant_exists(entity: current_business)
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
    only: [:edit, :new, :runner_details, :delete_larger_runner_modal, :get_public_ip_details]

  depends_on_clusters ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    only: [:edit, :new, :runner_details, :delete_larger_runner_modal]

  depends_on_clusters ApplicationRecord::Copilot,
    ApplicationRecord::Billing,
    only: [:edit, :new, :runner_details]

  depends_on_clusters ApplicationRecord::Billing,
    only: [:edit, :new, :runner_details, :get_public_ip_details]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:delete_larger_runner_modal], optional: true

  depends_on_clusters ApplicationRecord::RepositoriesActionsChecks,
    only: [:runner_details]

  def new
    this_business.plan_subscription&.synchronize_later

    is_public_ip_allowed = is_public_ip_allowed_for_entity?(this_business)

    # Render React-based UI for larger runner creation 🚀
    render_react_app(
      payload: build_new_runner_react_payload(
        owner: this_business,
        runner_list_path: settings_actions_runners_enterprise_path(this_business.slug),
        is_public_ip_allowed: is_public_ip_allowed,
        public_ip_info_path: settings_actions_get_public_ip_details_enterprise_url(this_business),
      ),
      title: "Add new GitHub-hosted runner · " + this_business.name,
      layout: "react_business",
      page_data: { selected_link: :business_actions_settings_add_larger_runner, sidebar: :policies },
      custom_tags: build_custom_tags(T.must(request)),
    )
  end

  def runner_details # rubocop:todo GitHub/UseRestfulActions
    larger_runner_id = params[:id]&.to_i
    return render_404 unless larger_runner_id.present?

    larger_runner = Actions::LargerRunner.get_larger_runner(this_business, pool_id: larger_runner_id)

    return render_404 unless larger_runner.present?

    network_config_name = ""
    runner_group_id = larger_runner.runner_group_id
    begin
      network_configuration = network_config_client.list_configurations(this_business, "actions", runner_group_id.to_s, true)
      if !network_configuration.empty? && !network_configuration[0].nil?
        network_config_name = network_configuration[0].name
      else
        network_config_name = "Disabled"
      end
    rescue ::NetworkBundle::NetworkConfigurationsException
      # Ignore these errors
    end

    check_run_ids = Actions::LargerRunner.get_check_runs_for_pool(this_business, pool_id: larger_runner_id)
    total_check_runs = check_run_ids.count
    check_run_ids = check_run_ids.slice(((page - 1) * per_page), per_page)

    if check_run_ids.nil?
      redirect_to Actions::EnterpriseRunnersView.new(settings_owner: this_business, current_user: current_user).larger_runner_details_path(id: larger_runner_id, viewing_from_runner_group: viewing_from_runner_group?); return
    end

    check_runs = T.must(check_run_ids).map do |cr|
      CheckRun.includes(:workflow_job_run, check_suite: [:workflow_run], repository: [:owner]).find(cr)
    end

    paginated_check_runs = WillPaginate::Collection.create(page, per_page, total_check_runs) { |p| p.replace(check_runs) }

    render "businesses/settings/actions/larger_runner_details", locals: {
      larger_runner: larger_runner,
      owner_settings: Actions::EnterpriseRunnersView.new(settings_owner: this_business, current_user: current_user),
      check_runs: paginated_check_runs,
      viewing_from_runner_group: viewing_from_runner_group?,
      network_configuration_name: network_config_name,
      image_generation_feature_enabled: is_custom_image_generation_enabled?(entity: this_business),
    }
  end

  def edit
    larger_runner_id = params[:id]&.to_i
    larger_runner = Actions::LargerRunner.get_larger_runner(this_business, pool_id: larger_runner_id)

    return render_404 unless larger_runner.present? && larger_runner.is_in_editable_state?

    is_public_ip_allowed = is_public_ip_allowed_for_entity?(this_business)

    # Render React-based UI for larger runner editing 🚀
    render_react_app(
      payload: build_edit_runner_react_payload(
        owner: this_business,
        larger_runner: larger_runner,
        runner_list_path: settings_actions_runners_enterprise_path(this_business.slug),
        is_public_ip_allowed: is_public_ip_allowed,
        public_ip_info_path: settings_actions_get_public_ip_details_enterprise_url(this_business),
      ),
      title: "Edit GitHub-hosted runner " + larger_runner.name + " · " + this_business.name,
      layout: "react_business",
      page_data: { selected_link: :enterprise_actions_settings_runners },
      custom_tags: build_custom_tags(T.must(request)),
    )
  end

  def create
    body = JSON.parse(request&.body.read)
    runner_group_id = body["runnerGroupId"].to_i

    # Check if the runner_group got deleted while we were creating the runners
    if is_runner_group_id_missing?(entity: this_business, runner_group_id: runner_group_id)
      return render_validation_error(error: error_invalid_group)
    end

    machine_spec = submitted_machine_spec(body["machineSpecId"], this_business)
    if machine_spec.nil?
      return render_validation_error(error: error_larger_runner_is_invalid)
    end

    if machine_spec.is_gpu_spec? && should_disable_gpu_runners_for_untrusted?(this_business)
      return render_validation_error(error: error_larger_runner_is_invalid)
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
      persistent_os_disk: is_custom_images_enabled?(entity: this_business) && body["isImageGenerationEnabled"],
      image_sas_uri: is_custom_image_uploading_enabled?(entity: this_business) ? body["imageSasUri"] : ""
    )

    if is_vnet_and_public_ip_enabled(entity: this_business, is_public_ip_enabled: larger_runner.is_public_ip_enabled, runner_group_id: runner_group_id)
      return render_validation_error(error: error_public_ip_vnet_conflict)
    end

    if is_public_ip_creation_forbidden?(entity: this_business, is_public_ip_enabled: larger_runner.is_public_ip_enabled)
      return render_validation_error(error: error_invalid_public_ip)
    end

    if !larger_runner.maximum_runners_valid?(gpu_limit: gpu_maximum_runners_for(entity: this_business))
      return render_validation_error(error: error_maximum_runner_is_invalid)
    end

    if !larger_runner.valid?(:create)
      return render_validation_error(error: error_larger_runner_is_invalid)
    end

    begin
      result = create_larger_runners_for(this_business, larger_runner: larger_runner, actor: current_user)
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

    larger_runner_being_updated = Actions::LargerRunner.get_larger_runner(this_business, pool_id: larger_runner_id)

    body = JSON.parse(request&.body.read)

    runner_group_id = body["runnerGroupId"].to_i

    if larger_runner_being_updated.nil?
      return render_validation_error(error: error_larger_runner_is_missing)
    end

    # Check if the runner_group got deleted while we were creating the runners
    if is_runner_group_id_missing?(entity: this_business, runner_group_id: runner_group_id)
      return render_validation_error(error: error_invalid_group(is_update: true))
    end

    larger_runner = Actions::LargerRunner.new(
      id: larger_runner_id,
      name: body["name"],
      runner_group_id: runner_group_id,
      maximum_runners: body["maximumConcurrentJobs"],
      machine_spec_id: body["machineSpecId"].present? ? body["machineSpecId"] : larger_runner_being_updated.machine_spec_id,
      machine_spec: submitted_machine_spec(body["machineSpecId"], this_business),
      is_public_ip_enabled: body["isPublicIpEnabled"],
      image: Actions::LargerRunner::ImageKey.new(
        source: larger_runner_being_updated.image&.source,
        id: body["imageId"].to_s.present? ? body["imageId"].to_s : larger_runner_being_updated.image&.id,
        version: body["imageVersion"].present? ? body["imageVersion"] : larger_runner_being_updated.image&.version
      ),
    )

    if is_vnet_and_public_ip_enabled(entity: this_business, is_public_ip_enabled: larger_runner.is_public_ip_enabled, runner_group_id: runner_group_id)
      return render_validation_error(error: error_public_ip_vnet_conflict)
    end

    is_public_ip_change_forbidden = is_public_ip_change_forbidden?(entity: this_business, enable_public_ip: larger_runner.is_public_ip_enabled, runner_id: larger_runner_id)
    if is_public_ip_change_forbidden
      return render_validation_error(error: error_invalid_public_ip(is_update: true))
    end

    if !larger_runner.maximum_runners_valid?(gpu_limit: gpu_maximum_runners_for(entity: this_business))
      return render_validation_error(error: error_maximum_runner_is_invalid)
    end

    if !larger_runner.valid?
      return render_validation_error(error: error_larger_runner_is_invalid(is_update: true))
    end

    begin
      result = update_larger_runners_for(this_business, larger_runner: larger_runner, actor: current_user)
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

    result = delete_larger_runners_for(this_business, id: larger_runner_id&.to_i, actor: current_user)

    if !result.call_succeeded?
      # TODO: in the future, we can use result&.options&.fetch(:message, nil) when the launch error messaging improves
      message = "Failed to delete GitHub-hosted runner. Please try again. If the problem persists, we recommend you check https://www.githubstatus.com/ to see the service status of actions or contact support at #{GitHub.contact_support_url} for additional information or help."
      # TODO: Runner deletes but error is thrown from service
      flash[:error] = message
    else
      flash[:notice] = "GitHub-hosted runner deleted."
    end

    runner_group_id = viewing_from_runner_group? ? result.value&.pool&.runner_group_id : nil
    if runner_group_id.present?
      redirect_to settings_actions_runner_group_enterprise_path(this_business.slug, id: runner_group_id)
    else
      redirect_to settings_actions_runners_enterprise_path(this_business.slug)
    end
  end

  def delete_larger_runner_modal # rubocop:todo GitHub/UseRestfulActions
    larger_runner_id = params[:id]
    return render_404 unless larger_runner_id.present?

    scope = this_business.runner_deletion_token_scope
    token = T.must(current_user).signed_auth_token(scope: scope, expires: 1.hour.from_now)

    respond_to do |format|
      format.html do
        render(Actions::LargerRunners::LargerRunnerDeleteModalComponent.new(
          owner_settings: Actions::EnterpriseRunnersView.new(settings_owner: this_business, current_user: current_user),
          larger_runner_id: params[:id].to_i,
          token: token,
          viewing_from_runner_group: viewing_from_runner_group?,
        ), layout: false)
      end
    end
  end

  def check_name # rubocop:todo GitHub/UseRestfulActions
    if params[:value].match(/[a-zA-Z0-9\-\_.]{1,64}/).to_s != params[:value].to_s
      render partial: "businesses/settings/actions/check_name_error", status: :unprocessable_entity, formats: :html
    else
      head :ok, content_type: "text/html"
    end
  end

  def setup_default_runners # rubocop:todo GitHub/UseRestfulActions
    GitHub.dogstats.increment("actions_larger_runners_default_setup_modal")
    runner_group_id = ensure_default_runners_group_exists_and_get_id(entity: current_business)

    if runner_group_id.nil?
      flash[:error] = "Failed to create runner group for Default Larger Runners. We recommend you check https://www.githubstatus.com/ to see the service status of actions or contact support at #{GitHub.contact_support_url} for additional information or help."
      redirect_to settings_actions_runners_enterprise_path(current_business)
      return
    end

    all_runners_created_successfully, at_least_one_runner_created_successfully = create_default_larger_runners(entity: current_business, group_id: runner_group_id, actor: T.must(current_user))

    # making sure banner will not be displayed again if customer deletes runners
    if at_least_one_runner_created_successfully
      T.must(current_user).dismiss_business_notice(DEFAULT_RUNNERS_BANNER_NOTICE_NAME, business_id: this_business.id, for_whole_business: true)
    end

    if all_runners_created_successfully
      flash[:notice] = "Default Larger Runners provisioning"
    else
      flash[:error] = "Failed to create some Default Larger Runners. We recommend you check https://www.githubstatus.com/ to see the service status of actions or contact support at #{GitHub.contact_support_url} for additional information or help."
      GitHub::Logger.info({
        msg: "failed to create some default larger runners",
        "entity.login": current_business.slug,
        "entity.class": current_business.class.to_s })
    end

    redirect_to settings_actions_runner_group_enterprise_path(current_business, id: runner_group_id)
  end

  def get_public_ip_details # rubocop:todo GitHub/UseRestfulActions
    runners_with_public_ip = Actions::LargerRunner.larger_runners_for(entity: this_business, is_public_ip_enabled: true)
    total_ip_count = public_ip_usage_limit_for(this_business)
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

  def determine_update_redirect_path(larger_runner, redirect_to_details: true)
    redirect_path = ""
    if viewing_from_runner_group?
      redirect_path = settings_actions_runner_group_enterprise_path(this_business.slug, id: larger_runner.runner_group_id)
    else
      redirect_path = settings_actions_larger_runner_details_enterprise_path(this_business.slug, id: larger_runner.id) unless !redirect_to_details
      redirect_path = settings_actions_runners_enterprise_path unless redirect_to_details
    end
    redirect_path
  end

  def viewing_from_runner_group?
    params[:viewing_from_runner_group] == "true"
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

  def network_config_client
    NetworkBundle::NetworkConfigurationClient.create
  end

  def render_validation_error(error:)
    render json: { error: error, error_category: "known" }, status: :unprocessable_entity
  end
end
