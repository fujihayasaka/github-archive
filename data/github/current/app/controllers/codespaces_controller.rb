# typed: true
# frozen_string_literal: true

class CodespacesController < ApplicationController
  extend T::Sig
  include ResilienceHelper
  include ReactHelper

  # Why is this here? GLAD YOU ASKED! Apparently for some reason ReactHelper (included above to use render_react_partial)
  # is adding a nilable type signature to request. Rather than adding safe navigation operators everwhere we can just
  # override the method to force a non-nil value. I can't think of any way request would be nil in a controller.
  # Why don't we also do this for `current_user`? Because that method is called by `logged_in?` and is EXPECTED to sometimes
  # be nil so we can't `T.must` it like this without causing errors for logged out checks.
  sig { override.returns(ActionDispatch::Request) }
  def request
    T.must(super)
  end

  include ApplicationController::CodespaceDependency

  CLUSTER_DEPENDENCIES_ALLOWED_NON_GET_REQUESTS = [
    "CodespacesController#create",
  ]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Collab,
    ApplicationRecord::Repositories,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Configurations,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Authnd,
    ApplicationRecord::Billing,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Ballast,
    ApplicationRecord::Iam,
    only: [:index]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IssuesPullRequests,
    only: [:index],
    optional: true

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Repositories,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Billing,
    only: [:destroy_confirmation]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Billing,
    only: [:dotfiles_repository_select]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Repositories,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Billing,
    only: [:exported]

  depends_on_clusters ApplicationRecord::IssuesPullRequests,
    only: [:exported, :provisioned, :provisioned_vscode, :destroy_confirmation, :published],
    optional: true

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Spokes,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Collab,
    ApplicationRecord::Billing,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Iam,
    only: [:new]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Ballast,
    ApplicationRecord::RepositoriesPushes,
    only: [:new],
    optional: true

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Ballast,
    ApplicationRecord::Billing,
    ApplicationRecord::Collab,
    ApplicationRecord::Commits,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Configurations,
    ApplicationRecord::Repositories,
    ApplicationRecord::Permissions,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Iam,
    ApplicationRecord::Lodge,
    only: [:create]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql5,
    only: [:prebuild_availability]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Repositories,
    ApplicationRecord::Permissions,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Billing,
    ApplicationRecord::Lodge,
    only: [:provisioned]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Repositories,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Billing,
    only: [:provisioned_vscode]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Collab,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Billing,
    ApplicationRecord::Iam,
    only: [:repository_select]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Billing,
    only: [:trusted_repository_select]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::Repositories,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Permissions,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Billing,
    only: [:show]

  depends_on_clusters ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::NotificationsEntries,
    only: [:show],
    optional: true

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Repositories,
    ApplicationRecord::Configurations,
    ApplicationRecord::Billing,
    only: [:skus]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::Repositories,
    ApplicationRecord::IamAbilities,
    only: [:published]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Repositories,
    ApplicationRecord::Configurations,
    only: [:allow_settings_sync]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Collab,
    ApplicationRecord::Repositories,
    ApplicationRecord::Configurations,
    ApplicationRecord::IssuesPullRequests,
    only: [:templates]

  # Our dependence on Spokes should be optional
  depends_on_clusters ApplicationRecord::Spokes, only: [
    :index,
    :prebuild_availability,
    :provisioned,
    :exported,
    :create,
    :repository_select,
    :show,
    :skus,
    :templates
  ], optional: true

  depends_on_clusters ApplicationRecord::Copilot, only: [
    :allow_settings_sync,
    :destroy_confirmation,
    :index,
    :new,
    :show,
    :skus,
    :templates
  ], optional: true

  # Unless explicitly allowlisted in one of the constants below, every action does feature checks
  # against the current repo.

  # These actions either require no feature check or do it themselves.
  NO_FEATURE_GATE = %i(create destroy destroy_refresh destroy_confirmation skus repository_select trusted_repository_select dotfiles_repository_select toggle_dev_flags allow_permissions close_window_prompt prebuild_availability badge templates allow_settings_sync update_settings_sync)

  # The feature check without a repo context is potentially expensive. Only endpoints in this allowlist perform it.
  ANY_REPO_FEATURE_GATE = %i(new)

  # We REALLY need these to be first to ensure we can catch all errors that would lead to a 500
  prepend_around_action :ensure_create_async_operation_created, only: :create
  prepend_around_action :ensure_start_async_operation_created, only: :show

  skip_before_action :login_required, only: [:badge]

  before_action :require_feature_for_current_repo, except: NO_FEATURE_GATE + ANY_REPO_FEATURE_GATE + [:index]
  before_action :require_feature_for_any_repo, only: ANY_REPO_FEATURE_GATE

  with_options except: [
    :index,
    :new,
    :repository_select,
    :trusted_repository_select,
    :dotfiles_repository_select,
    :create,
    :toggle_dev_flags,
    :skus,
    :allow_permissions,
    :close_window_prompt,
    :prebuild_availability,
    :badge,
    :templates,
    :allow_settings_sync,
    :update_settings_sync,
  ] do
    before_action :require_codespace
    before_action :verify_authorization
    before_action :set_codespace_context
  end
  before_action :require_pullable_repo, except: [
    :index,
    :new,
    :repository_select,
    :trusted_repository_select,
    :dotfiles_repository_select,
    :create,
    :update,
    :destroy,
    :destroy_refresh,
    :destroy_confirmation,
    :show,
    :export,
    :exported,
    :provisioned,
    :provisioned_vscode,
    :toggle_dev_flags,
    :skus,
    :export_control,
    :suspend,
    :allow_permissions,
    :close_window_prompt,
    :prebuild_availability,
    :badge,
    :templates,
    :published,
    :allow_settings_sync,
    :update_settings_sync,
  ]

  around_action :aggressive_client_timeouts, only: :create
  before_action :set_path_and_name, only: [:new]

  javascript_bundle :codespaces
  javascript_bundle "codespaces-branch-selector"
  stylesheet_bundle :codespaces

  # List of all flags that can be toggled through Codespaces Dev Tools
  TOGGLEABLE_FLAGS = ::Codespaces::Vscs::OWNER_FEATURE_FLAGS
    # get symbols
    .map(&:to_sym)
    # don't render the non-toggleable flags
    .without(:codespaces_developer)
    # add the offboarding force limit flag
    .push(:codespaces_offboarding_force_limit)

  # #index  - We're CAP filtering the query to retrieve codespaces, so no need to filter page itself
  # #toggle_dev_flags - only ever called from the index page and makes changes at the user level, not for a particular resource
  ACTIONS_EXCLUDED_FROM_CAP_CHECKS = %w(index toggle_dev_flags)

  rescue_from "Codespaces::AsyncOperation::PendingError" do |e|
    T.bind(self, CodespacesController)
    flash[:error] = e.message
    redirect_to codespaces_path
  end

  def index
    if request.xhr?
      index_xhr
    else
      if params[:new]
        redirect_to new_codespace_path(codespace_new_params.except(:new))
      else
        context_region_preset :codespaces
        GitHub.tracer.in_span("codespaces/controller#index", kind: :internal) do |_span|
          query = GitHub.tracer.in_span("codespaces/controller#query_for_dashboard", kind: :internal) do |_span|
            query_for_dashboard
          end

          templates = Codespaces::Template.promoted_templates

          if current_user&.feature_enabled?(:codespaces_copilot_demo_template) && Codespaces::Template.copilot.active?
            templates[:copilot] = Codespaces::Template.copilot
          end

          unpublished = ActiveModel::Type::Boolean.new.cast(params[:unpublished])
          repository_id = ActiveModel::Type::Integer.new.cast(params[:repository_id])
          render "codespaces/index", locals: {
            query: query,
            repository_id: repository_id,
            unpublished: unpublished,
            at_concurrency_limit: !!flash[:at_concurrency_limit],
            templates: (repository_id || unpublished) ? [] : templates
          }
        end
      end
    end
  end

  def index_xhr
    if current_repo.nil?
      return head :not_found
    end

    query = query_for_codespaces_list

    if query.repository_policy.can_attempt_create?
      return render_codespaces_list_component(query: query)
    end

    head 418
  end

  def new
    context_region_preset :codespaces

    repository = current_repo
    if template_slug = params[:template]
      template = Codespaces::Template.with_slug(template_slug)
      repository = template.repository if template
    end
    if template_nwo = params[:template_repository]
      repository = Repository.with_name_with_owner(template_nwo)
      template = Codespaces::Template.for_repository(repository) if repository
    end

    repository = if repository&.pullable_by?(current_user)
      ref_param = params[:ref].presence
      ref = repository.refs.find(ref_param) if ref_param
      ref ||= repository.default_branch_ref
      repository
    else
      nil
    end

    # Always attempt to find a "template" for a repository when we have one
    template ||= Codespaces::Template.for_repository(repository) if repository && params[:template] != "false"

    if repository && params[:pull_id].present? && params[:ref].blank?
      # Only try to find a PR if no ref was provided.
      pull_request = PullRequest.with_number_and_repo(params[:pull_id].to_i, repository)
      # Only set the ref for the standard form if the PR is not currently closed.
      ref = repository.refs.find(pull_request.head_ref) if pull_request && !pull_request.closed?
    end

    query = Codespaces::Query.new(
      current_user:,
      repository:,
      ref:,
      pull_request:,
      cap_filter:,
    )

    if current_user&.feature_enabled?(:codespaces_region_selection_logging)
      GitHub.logger.info("codespaces_region_selection", at: "#new controller params", config_name: config[:name], requested_target: params[:vscs_target], requested_geo: params[:geo], requested_region: params[:location])
    end

    vscs_target = if current_user&.feature_enabled?(:codespaces_fix_vscs_target_on_create)
      vscs_target(input: params[:vscs_target])
    else
      if current_user&.feature_enabled?(:codespaces_developer)
        config = Codespaces::Vscs.target_configs[params[:vscs_target]&.to_sym] || Codespaces::Vscs.default_target_config
        config[:name]
      else
        Codespaces::Vscs.default_target
      end
    end

    available_geos = Codespaces::Locations::Geo.where(vscs_target:).map(&:id)
    begin
      region = Codespaces::GetRegionForUser.call(
        user: current_user,
        repository: repository,
        requested_region: Codespaces::Locations::Region.where(vscs_target:).find(params[:location]),
        requested_geo: Codespaces::Locations::Geo.where(vscs_target:).find(params[:geo]),
        vscs_target: vscs_target
      )
    rescue Codespaces::Locations::Region::UnavailableError
      flash[:error] = "The region you have selected or the region that was automatically selected is not available."
      redirect_to codespaces_path and return
    end
    # TODO: We'd avoid this a bit if we GetRegionForUser wasn't returning a string for backwards compatibility but we are for now.
    geo = Codespaces::VscsServiceStamp.find(region:, vscs_target:).geo.id
    if repository.present?
      repo_policy = Codespaces::RepositoryPolicy.async_with_prefill(current_user, repository).sync
      billable_owner = repo_policy.billable_owner
      if billable_owner
        config = Codespaces::NetworkConfiguration.for(repository:, billable_owner:, actor: T.must(current_user))
        if config.present?
          available_geos = available_geos & config.geo_ids
        end
      end
    end

    sku_availability_contexts = []
    base_image_valid = true

    if repository && ref && geo.presence
      repository_policy = Codespaces::RepositoryPolicy.async_with_prefill(current_user, repository).sync
      # Soon we will use parameterized devcontainer instead.
      ref_for_oid = Codespaces::GetTargetRef.call(repository: repository, name_or_oid: ref.name)
      oid = ref_for_oid&.target_oid

      devcontainers = Codespaces::DevContainer.list_dev_containers(repository, oid)

      if active_devcontainer = devcontainers.find { |dc| dc.path == params[:devcontainer_path] }
        devcontainer_path = active_devcontainer.path
      end

      # Yep we also have this in addition to the `active_devcontainer` above. It's only used for Sku stuff though and
      # no I'm not sure why we have both.
      devcontainer = Codespaces::DevContainer.new(repository: repository, oid: oid, filepath: devcontainer_path)

      sku_availability_contexts = Codespaces::Skus.sku_availability_contexts_for_display(
        repository_policy,
        vscs_target: vscs_target,
        vscs_target_url: params[:vscs_target_url]&.to_str,
        location: region,
        ref: ref.name,
        dev_container: devcontainer,
        preferred_default: params[:machine].presence,
        fetch_prebuild_availability: false
      )
      base_image_valid = Codespaces::ImagePolicy.image_allowed?(
        image_name: devcontainer.image,
        repository: repository_policy.repository,
        billable_owner: repository_policy.billable_owner
      )
    end

    enabled_skus = sku_availability_contexts.select(&:enabled)
    selected_sku = (enabled_skus.find(&:default) || enabled_skus.first)&.sku

    force_templates_to_quickstart = user_feature_enabled?(:codespaces_templates_use_quickstart) && template.present? && !params[:skip_quickstart]
    if (force_templates_to_quickstart || params[:quickstart].present? || params[:quick_start].present? || params[:resume].present?) && repository.present?
      template_repository = template&.repository
      if pull_request.blank?
        # params[:ref] is only set if the branch was valid (on GitHub) otherwise the full path is left in params[:name]
        # We need to look at that because the specified ref may _only_ exist in a codespace at this point (so invalid
        # from a GitHub perspective but valid from our perspective).
        quickstart_ref = params[:ref].presence || params[:name].presence || repository.default_branch
      end
      quickstart_codespace = Codespaces::QuickStart::FindOrBuild.call(
        owner: current_user,
        repository:,
        template_repository:,
        ref: quickstart_ref,
        pull_request:,
        devcontainer_path:
      )
      render "codespaces/quickstart", locals: { quickstart_codespace:, auto_init: params[:auto_init] }
    else
      view = create_view_model(
        Codespaces::NewView,
        layout: false,
        repository: repository,
        ref: ref,
        pull_request: pull_request,
        fix_suggestion: params[:fix_suggestion],
        query: query,
        user_settings: user_settings,
        hide_repo_select: repository && ActiveModel::Type::Boolean.new.cast(params[:hide_repo_select]),
        vscs_target: params[:vscs_target],
        sku: selected_sku,
        vscs_target_url: params.dig(:codespace, :vscs_target_url),
        sku_availability_contexts: sku_availability_contexts,
        geos: available_geos,
        geo: geo,
        region_for_skus: region,
        show_prebuild_availability: Codespaces::Prebuilds.configured?(repository),
        pickable_devcontainers: devcontainers,
        active_devcontainer:,
        devcontainer_path:,
        show_response_error: ActiveModel::Type::Boolean.new.cast(params[:response_error]),
        base_image_valid: base_image_valid,
        template: template,
      )
      render "codespaces/advanced_options", locals: { view: view }, layout: !request.xhr?
    end
  end

  def repository_select
    respond_to do |format|
      format.any(:html, :html_fragment) do
        view = create_view_model(
          Codespaces::RepositorySelectView,
          layout: false,
          selected_repository: current_repo,
          phrase: params[:q],
          remote_ip: request.remote_ip,
          cap_filter: cap_filter,
          user_repos_first: true,
          form_name: params[:form_name],
        )
        render "codespaces/new/repository_select", locals: { view: view, experimental: params[:experimental], trusted_repositories: params[:trusted_repositories] }, layout: false, formats: [:html, :html_fragment]
      end
    end
  end

  def trusted_repository_select
    render partial: "codespaces/trusted_repository_select", locals: {
      experimental: params[:experimental],
      view: create_view_model(
        Codespaces::RepositorySelectView,
        layout: false,
        selected_repository: current_repo,
        phrase: params[:q],
        remote_ip: request.remote_ip,
        repos_owned_by: params[:repos_owned_by]&.to_i,
        cap_filter: cap_filter,
      )
    }, formats: :html
  end

  def dotfiles_repository_select
    respond_to do |format|
      format.any(:html, :html_fragment) do
        render partial: "codespaces/dotfiles_repository_select", locals: {
          experimental: params[:experimental],
          view: create_view_model(
            Codespaces::RepositorySelectView,
            layout: false,
            selected_repository: current_repo,
            phrase: params[:q],
            remote_ip: request.remote_ip,
            repos_owned_by: params[:repos_owned_by]&.to_i,
            cap_filter: cap_filter,
          )
        }, formats: [:html, :html_fragment]
      end
    end
  end

  def create
    operation = Codespaces::AsyncOperation.create!(user: current_user, operation: :create_codespace, vscs_target: codespace_params[:vscs_target])
    request.env["codespaces.async_operation_created"] = true
    if template = Codespaces::Template.for_repository(current_repo)
      if !template[:active]
        operation.mark_as_ended
        flash[:error] = "Sorry, we don't know how to build that kind of project."
        redirect_to codespaces_path and return
      end
    end

    if params[:secrets_data].present?
      begin
        secrets_data = GitHub::JSON.parse(params[:secrets_data])
        result = Codespaces::AddDeclarativeSecrets.call(user: current_user, repository: current_repo, secrets_data: secrets_data)
        if !result.values.all?
          operation.mark_as_ended
          flash[:error] = "There was an error adding your secrets. Please try again."
          redirect_back(fallback_location: codespaces_path) and return
        end
      rescue Yajl::ParseError => e
        operation.mark_as_ended
        flash[:error] = "Invalid secrets data received. Please try again."
        redirect_back(fallback_location: codespaces_path) and return
      rescue => e # rubocop:disable Lint/GenericRescue
        operation.mark_as_failed(failure_reason: e)
        raise
      end
    end

    if current_repo&.empty?
      if current_user&.feature_enabled?(:codespaces_empty_repo_init) && params[:auto_init] && current_repo.pushable_by?(current_user)
        # Act as if the owner had checked the auto_init checkbox when they originally created the repository
        initialized_repo = Codespaces::InitializeRepository.call(repository: current_repo, actor: current_user)
        if !initialized_repo && !request.xhr?
          operation.mark_as_ended
          flash[:error] = "Failed to initialize empty repository."
          redirect_to codespaces_path and return
        end
      elsif !request.xhr?
        # Otherwise we need to bail out because we can't create a codespace for an empty repository.
        # We can only do this for non-XHR requests to prevent the Javascript in the codespaces/new view from breaking.
        # For XHR requests we'd wind up rendering advanced options and relying on the CreateNoticeComponent to show the error.
        operation.mark_as_ended
        flash[:error] = "Codespaces cannot be created on empty repositories."
        redirect_to codespaces_path and return
      end
    end

    open_in_deeplink = ActiveModel::Type::Boolean.new.cast(params[:open_in_deeplink])

    error_message, error_type = nil, nil

    has_opted_out = ActiveModel::Type::Boolean.new.cast(params[:multi_repo_permissions_opt_out])

    begin
      Codespaces::WriteAllowedPermissions.call(
        user: current_user,
        repository: current_repo,
        ref: codespace_params[:ref].presence || PullRequest.find(codespace_params[:pull_request_id]).head_ref,
        opt_out: has_opted_out,
        owner_permissions: params[:owner_permissions],
        repository_permissions: params[:repository_permissions],
        devcontainer_path: codespace_params[:devcontainer_path].presence,
        category: "browser"
      )

    rescue ActiveModel::ValidationError => e
      operation.mark_as_ended
      GitHub.dogstats.increment("codespaces.allow_permissions.error.count", tags: ["category:browser", "error_type:#{e.class.name}"])
      error_message = "Could not write requested permissions: #{e.model.errors.full_messages.to_sentence}"
    rescue Codespaces::Error => e
      operation.mark_as_ended
      GitHub.dogstats.increment("codespaces.allow_permissions.error.count", tags: ["category:browser", "error_type:#{e.class.name}"])
      error_message = e.message
    rescue => e # rubocop:disable Lint/GenericRescue
      operation.mark_as_failed(failure_reason: e)
      raise
    end

    unless error_message
      if current_user&.feature_enabled?(:codespaces_region_selection_logging)
        GitHub.logger.info("codespaces_region_selection", at: "#create controller params", requested_target: codespace_params[:vscs_target], requested_geo: params[:geo], requested_region: codespace_params[:location])
      end

      vscs_target = if current_user&.feature_enabled?(:codespaces_fix_vscs_target_on_create)
        vscs_target(input: codespace_params[:vscs_target])
      else
        codespace_params[:vscs_target]&.to_sym || Codespaces::Vscs.default_target
      end

      begin
        location = Codespaces::GetRegionForUser.call(
          user: current_user,
          repository: current_repo,
          requested_geo: params[:geo],
          requested_region: codespace_params[:location],
          client: :dotcom,
          vscs_target: vscs_target
        )

        # The environment will be nil here unless we were able to provision synchronously.
        result = Codespaces::Create.call(
          attributes: codespace_params
            .merge(owner: current_user, location: location)
            .reject { |k, _| k == "geo" }
            .reject { |k, v| k == "devcontainer_path" && !Codespaces::DevContainer.valid_path?(v) },
          user_session: user_session,
          expected_billable_owner_id: ActiveModel::Type::Integer.new.cast(params[:expected_billable_owner_id]),
          request_cascade_token: true,
          entry_point: :codespaces_controller_create,
          operation:,
        )
        codespace = result.codespace
        environment = result.env
        github_token = result.github_token
        github_token_valid_after = result.github_token_valid_after
      rescue ActiveModel::ValidationError => e
        operation.mark_as_ended
        error_message = "Codespace could not be created: #{e.model.errors.full_messages.to_sentence}"
        error_type = e.model.errors.full_messages.include?("Billable owner has changed") ? :billable_owner_safety_error : nil
      rescue ActiveRecord::RecordInvalid => e
        operation.mark_as_ended
        error_message = "Codespace could not be created: #{e.record.errors.full_messages.to_sentence}"
        error_type = e.record.errors.full_messages.include?("Billable owner has changed") ? :billable_owner_safety_error : nil
      rescue Codespaces::Plan::PlanNotFoundForLocation => e
        operation.mark_as_failed(failure_reason: e)
        Codespaces::ErrorReporter.report(e) unless GitHub.flipper[:codespaces_automated_testing].enabled?(current_user)
        error_message = "Codespace could not be created for that location"
      rescue Codespaces::Client::BadResponseError => e
        if e.unprocessable_entity?
          operation.mark_as_ended
        else
          operation.mark_as_failed(failure_reason: e.status)
          Codespaces::ErrorReporter.report(e)
        end
        error_message = "Codespace could not be created"
      rescue Codespaces::Error => e
        operation.mark_as_failed(failure_reason: e)
        Codespaces::ErrorReporter.report(e) unless GitHub.flipper[:codespaces_automated_testing].enabled?(current_user)
        error_message = "Codespace could not be created"
      rescue Codespaces::VscsClient::SecretDataTooLarge => e
        operation.mark_as_ended
        error_message = "Unable to create codespace: #{e.message}. Please reduce "\
          "the number or length of codespaces secrets associated with the given "\
          "repository."
      rescue Codespaces::ConcurrencyLimitError, Codespaces::RateLimitError => e
        operation.mark_as_ended
        error_message = e.message
        error_type = :concurrency_limit_error
      rescue Codespaces::VscsClient::TierCapacityUnavailableError => e
        operation.mark_as_failed(failure_reason: e)
        Codespaces::ErrorReporter.report(e) unless GitHub.flipper[:codespaces_automated_testing].enabled?(current_user)
        error_message = e.message
      rescue Codespaces::Locations::Region::UnavailableError => e
        operation.mark_as_ended
        error_message = e.message
      rescue Codespaces::Locations::Geo::InvalidError => e
        operation.mark_as_ended
        error_message = e.message
      rescue Codespaces::Locations::Region::InvalidError => e
        operation.mark_as_ended
        error_message = e.message
      rescue Codespaces::Tokens::Error => e
        if e.message.include?("repository_not_found")
          operation.mark_as_ended
          error_message = "The repository could not be found."
        else
          operation.mark_as_failed(failure_reason: e)
          error_message = e.message
        end
      rescue => e # rubocop:disable Lint/GenericRescue
        operation.mark_as_failed(failure_reason: e)
        raise
      end
    end

    connection_ready = environment&.has_connection? && codespace&.provisioned?

    if open_in_deeplink
      if connection_ready
        render json: { codespace_url: codespace_url_from_editor_preferences(codespace: codespace, user: current_user) }
      elsif error_message
        render json: { error: error_message, error_type: error_type }, status: :unprocessable_entity
      else
        render json: { loading_url: provisioned_vscode_codespace_path(codespace.name) }
      end
    else
      if connection_ready
        # We can connect to the codespace immediately via the hot pool of environments when using the web editor.
        # The VS Code extension will need to be able to handle the environment's connection details in order to do the same.
        editor = current_user&.codespace_preferred_editor if should_add_editor_query_parameter?

        render "codespaces/show", layout: "layouts/codespaces/fullscreen", locals: {
          codespace:,
          connection: environment.connection,
          user_settings: user_settings,
          github_token:,
          github_token_valid_after:,
          current_user:,
          cascade_token: environment.cascade_token,
          repository: codespace.repository,
          start_async: false,
          from_template: false,
          editor:
        }
      else
        if error_message
          case error_type
          when :concurrency_limit_error
            flash[:at_concurrency_limit] = true
            redirect_to codespaces_path
          when :billable_owner_safety_error
            flash[:error] = "The entity paying for codespaces usage with this repository may have changed, please refresh the page and try again."
            redirect_back(fallback_location: codespaces_path)
          else
            flash[:error] = error_message
            redirect_to codespaces_path
          end
        else
          redirect_to codespace_path(codespace)
        end
      end
    end
  rescue => e # rubocop:disable Lint/GenericRescue
    operation&.mark_as_failed(failure_reason: e) if !operation&.ended?
    raise
  end

  def update
    if codespace_update_params[:sku_name]
      begin
        Codespaces::UpdateSettings.call(codespace: current_codespace, sku_name: codespace_update_params[:sku_name])
        if current_codespace.pending_async_operations.any?
          flash[:notice] = "Your codespace \"#{current_codespace.safe_display_name}\" will be updated to use machine type with a different amount of storage: \"#{Codespaces::Skus.sku_by_name(codespace_update_params[:sku_name]).display_name}\". Your codespace will be stopped and unavailable during the update."
        else
          flash[:notice] = "Your codespace \"#{current_codespace.safe_display_name}\" has been updated to use machine type: \"#{Codespaces::Skus.sku_by_name(current_codespace.reload.sku_name).display_name}\". Changes will take effect the next time your codespace restarts."
        end
        redirect_back(fallback_location: codespaces_path)
      rescue Codespaces::UpdateSettings::FailedToUpdate
        flash[:error] = "There was a problem updating your codespace, please try again."
        redirect_back(fallback_location: codespaces_path)
      rescue Codespaces::UpdateSettings::CodespacesStillProvisioningError
        flash[:error] = "Codespace machine type cannot be updated while codespace is still provisioning."
        redirect_back(fallback_location: codespaces_path)
      end
    elsif codespace_update_params[:keep]
      if codespace_update_params[:keep] == "true" && Codespaces::Keep.call(current_codespace)
        flash[:notice] = "Your codespace \"#{current_codespace.safe_display_name}\" will no longer be auto-deleted."
      elsif Codespaces::Unkeep.call(current_codespace)
        flash[:notice] = "Your codespace \"#{current_codespace.safe_display_name}\" will be deleted after it has been shutdown for #{Codespaces::RetentionExpirationComponent.new(retention_expires_at: current_codespace.retention_period.from_now).time_until_deletion}."
      end

      redirect_back(fallback_location: codespaces_path)
    else
      begin
        if current_codespace.update(codespace_update_params)
          flash[:notice] = "Your codespace \"#{current_codespace.safe_display_name}\" has been updated."
          return redirect_back(fallback_location: codespaces_path)
        else
          error = current_codespace.errors.full_messages.to_sentence
        end
      rescue ActiveRecord::StatementInvalid => e
        if e.message.match?(/Incorrect string value.+for column 'display_name'/)
          error = "Sorry, codespace display names cannot currently support emoji."
        else
          raise e
        end
      end
      flash[:error] = error
      redirect_back(fallback_location: codespaces_path)
    end
  end

  def destroy
    # Check for unpushed changes
    if safe_to_deprovision?
      # Either we have no unpushed changes OR we have confirmed we want to anyways.
      current_codespace.deprovision!

      respond_to do |format|
        format.html_fragment do
          headers["Cache-Control"] = "no-cache, no-store"
          render_codespaces_list_component(query: query_for_codespaces_list)
        end
        format.html do
          flash[:notice] = "Codespace \"#{current_codespace.safe_display_name}\" deleted"
          redirect_back(fallback_location: codespaces_path)
        end
      end
    else
      # Warn about unpushed changes!
      respond_to do |format|
        format.html_fragment do
          headers["Cache-Control"] = "no-cache, no-store"
          render_codespaces_list_component(query: query_for_codespaces_list)
        end
        format.html do
          flash[:notice] = "Codespace \"#{current_codespace.safe_display_name}\" has unpushed changes. Please confirm deletion below."
          redirect_back(fallback_location: codespaces_path)
        end
      end
    end
  end

  def destroy_refresh
    current_codespace.deprovision!

    flash[:notice] = "Codespace \"#{current_codespace.safe_display_name}\" deleted."
    redirect_back(fallback_location: codespaces_path)
  end

  def destroy_confirmation
    render partial: "codespaces/destroy_confirmation_modal", layout: false, locals: { codespace: current_codespace }
  end

  def show
    operation = ActiveRecord::Base.connected_to(role: :writing) do
      Codespaces::AsyncOperation.ensure_no_blocking_pending!(current_codespace)
      Codespaces::AsyncOperation.create!(codespace: current_codespace, operation: :start_codespace)
    end
    request.env["codespaces.async_operation_created"] = true

    if Codespaces::Policy.codespace_user_spammy?(current_codespace)
      operation&.mark_as_ended
      flash[:error] = "Unable to start codespace."
      redirect_to codespaces_path and return
    end

    if GitHub.flipper[:codespaces_disable_starts].enabled?(current_codespace.owner)
      operation&.mark_as_ended
      flash[:error] = "Starting codespaces is temporarily disabled. Please try again later."
      redirect_to codespaces_path and return
    end

    result = if current_codespace.provisioned?
      begin
        start_command = Codespaces::Start.new(
          current_codespace,
          user: current_user,
          session: user_session,
          cap_filter: cap_filter,
          require_connection: false,
          request_cascade_token: true,
          entry_point: :codespaces_controller_show,
          operation: operation,
        )
        start_command.call
      rescue ActiveModel::ValidationError => e
        operation&.mark_as_ended
        flash[:error] = e.model.errors.full_messages.join(" ")
        return redirect_to codespaces_path
      rescue Codespaces::Client::BadResponseError => e
        if e.unprocessable_entity?
          operation&.mark_as_ended
          T.must(start_command).result
        else
          operation&.mark_as_failed(failure_reason: e.status)
          Codespaces::ErrorReporter.report(e) unless GitHub.flipper[:codespaces_automated_testing].enabled?(current_user)
          if T.must(current_user).feature_enabled?(:codespaces_controller_bad_response_error_redirect)
            flash[:error] = "Unable to start codespace. Please try again later."
            return redirect_to codespaces_path
          else
            T.must(start_command).result
          end
        end
      rescue Codespaces::ConcurrencyLimitError
        operation&.mark_as_ended
        flash[:at_concurrency_limit] = true
        return redirect_to codespaces_path
      rescue Codespaces::RateLimitError => e
        operation&.mark_as_ended
        flash[:error] = e.message
        return redirect_to codespaces_path
      rescue Codespaces::VscsClient::TierCapacityUnavailableError => e
        operation&.mark_as_failed(failure_reason: e)
        Codespaces::ErrorReporter.report(e) unless GitHub.flipper[:codespaces_automated_testing].enabled?(current_user)
        flash[:error] = e.message
        return redirect_to codespaces_path
      rescue Codespaces::Start::InaccessibleError
        operation&.mark_as_ended
        return render_404
      rescue Codespaces::Client::RequestError => e
        operation&.mark_as_failed(failure_reason: e)
        Codespaces::ErrorReporter.report(e) unless GitHub.flipper[:codespaces_automated_testing].enabled?(current_user)
        flash[:error] = "Unable to start codespace. Please try again later."
        return redirect_to codespaces_path
      rescue => e # rubocop:disable Lint/GenericRescue
        operation&.mark_as_failed(failure_reason: e)
        raise
      end
    else
      # If we aren't provisioned for whatever reason we won't even call start and thus have nothing to really do here.
      operation&.mark_as_ended
      nil
    end

    headers["Cache-Control"] = "no-cache, no-store"

    # Make sure the provided editor is valid
    editor = params[:editor] if Codespaces::Settings::EDITORS.include?(params[:editor])

    render "codespaces/show", layout: "layouts/codespaces/fullscreen", locals: {
      codespace: current_codespace,
      connection: result&.connection,
      github_token: result&.github_token,
      github_token_valid_after: result&.github_token_valid_after,
      current_user:,
      user_settings:,
      repository: current_codespace.repository,
      cascade_token: result&.cascade_token,
      from_template: !!params[:template],
      editor:
    }
  rescue => e # rubocop:disable Lint/GenericRescue
    operation&.mark_as_failed(failure_reason: e) if !operation&.ended?
    raise
  end

  def export_control
    if request.xhr?
      render partial: "codespaces/export_branch_button", locals: {
        codespace: current_codespace,
        needs_fork: ActiveModel::Type::Boolean.new.cast(params[:needs_fork])
      }
    else
      render_404
    end
  end

  # Exports codespace to a branch. See Codespaces::Export for more info.
  # For unpublished codespaces, we first publish them to a new repository.
  def export
    encrypted_token, key_version = Codespaces::Tokens.mint_encrypted_github_token(current_user, current_codespace)

    if current_codespace.published? && ActiveModel::Type::Boolean.new.cast(params[:fork])
      forked, _ = Codespaces::ForkRepo.call(current_codespace, current_codespace.export_branch_name, entry_point: :codespaces_controller_export)
      repo_is_ready = true
      new_repository_origin = forked.clone_url
    elsif current_codespace.published?
      repo_is_ready = true
      new_repository_origin = nil
    elsif params[:name] && params[:visibility]
      result = Codespaces::PublishToRepository.call(
        codespace: current_codespace,
        name: params[:name],
        is_private: params[:visibility] == "private",
      )
      repo_is_ready = result.success?
      new_repository_origin = result.repository.clone_url if repo_is_ready
    end

    if repo_is_ready && current_codespace.export!(encrypted_token, key_version: key_version, actor: current_user, new_repository_origin: new_repository_origin)
      head :accepted
    else
      flash[:error] = "Unable to export codespace."
      redirect_to codespaces_path
    end
  end

  def exported
    if current_codespace.fresh_export_exists?
      head :ok
    elsif current_codespace.stuck_exporting?
      flash[:error] = "Your codespace export did not complete. Please try again."
      head :request_timeout
    elsif !current_codespace.exporting?
      flash[:error] = "Your codespace does not appear to be exporting. Please try again."
      head :too_early
    else
      head :accepted
    end
  end

  def published
    redirect_to repository_path(current_codespace.repository)
  end

  def provisioned
    if current_codespace.provisioned?
      github_token, github_token_valid_after  = Codespaces::Tokens.mint_github_token_with_estimated_validity(T.must(current_user), current_codespace)
      render(Codespaces::WorkbenchFormComponent.new(
        codespace: current_codespace,
        github_token:,
        github_token_valid_after:,
        user: current_user,
        user_settings:,
        already_loading: true,
      ), layout: false)
    elsif current_codespace.failed?
      Codespaces::ErrorReporter.report(StandardError.new("Codespace provisioned failed"), codespace: current_codespace)
      render partial: "codespaces/advance_loading_state",
        locals: { state: "failed" }
    elsif current_codespace.stuck_provisioning?
      Codespaces::ErrorReporter.report(StandardError.new("Codespace stuck provisioning"), codespace: current_codespace)
      render partial: "codespaces/advance_loading_state",
        locals: { state: "stuck" }
    else
      Codespaces::ErrorReporter.report(StandardError.new("Codespace not provisioned"), codespace: current_codespace)
      head :accepted
    end
  end

  def provisioned_vscode
    if current_codespace.provisioned?
      render partial: "codespaces/vscode_forwarder", locals: { codespace_url: current_codespace.vscode_url }
    elsif current_codespace.failed? || current_codespace.stuck_provisioning?
      head :service_unavailable
    else
      head :accepted
    end
  end

  def skus
    codespace = Codespace.find_by(id: params[:codespace_id])
    return render_404 unless codespace

    repository_policy = Codespaces::RepositoryPolicy.async_with_prefill(current_user, codespace.repository).sync
    return render_404 unless repository_policy.can_attempt_create?
    devcontainer_path = codespace.devcontainer_path.presence
    devcontainer = Codespaces::DevContainer.new(repository: codespace.repository, oid: codespace.oid, filepath: devcontainer_path)
    recs = Codespaces::Skus.sku_availability_contexts_for_display(
      repository_policy,
      codespace: codespace,
      dev_container: devcontainer,
      vscs_target_url: params[:vscs_target_url]&.to_str
    )

    selectable_skus = recs.filter_map { |r| r.sku if r.enabled }
    current_sku = codespace.sku_name&.to_sym
    current_sku_disallowed = !Codespaces::Skus.valid_sku_for_existing_codespace?(codespace.sku_name, codespace)

    render partial: "codespaces/sku_select_with_recommendations",
      locals: {
        sku_recommendations: recs,
        selectable_skus: selectable_skus,
        current_sku: current_sku,
        current_sku_disallowed: current_sku_disallowed,
        cannot_change_from_current_sku: current_sku && selectable_skus.none? { |sku| sku.name != current_sku },
        codespace_name: codespace.name,
      },
      layout: false,
      formats: :html
  end

  def suspend
    if current_codespace.suspended?
      flash[:notice] = "Codespace \"#{current_codespace.safe_display_name}\" is already stopped."
      redirect_back_or_to codespaces_path and return
    end

    if current_codespace.suspendable?
      begin
        current_codespace.suspend!(current_user)
        flash[:notice] = "Codespace \"#{current_codespace.safe_display_name}\" stopped."
      rescue Codespaces::Client::BadResponseError => e
        Codespaces::ErrorReporter.report(e, codespace: current_codespace)
        flash[:error] = "Failed to stop codespace \"#{current_codespace.safe_display_name}\". Try again or delete the codespace instead."
      end
    else
      flash[:error] = "The codespace \"#{current_codespace.safe_display_name}\" is not in a stoppable state. Try again later or delete the codespace instead."
    end
    redirect_back_or_to codespaces_path
  end

  # Dev Tools endpoint to be used by our VSCS friends to toggle flags.
  def toggle_dev_flags
    return render_404 unless current_user_feature_enabled?(:codespaces_developer)

    TOGGLEABLE_FLAGS.each do |flag|
      if params.include?(flag)
        if !current_user&.feature_enabled?(flag.to_sym)
          GitHub.flipper[flag].enable(current_user)
        end
      elsif current_user&.feature_enabled?(flag.to_sym) && !GitHub.flipper[flag].enabled? # Don't bother if globally enabled.
        GitHub.flipper[flag].disable(current_user)
      end
    end

    flash[:notice] = "Successfully saved dev tools settings"
    redirect_back(fallback_location: codespaces_path)
  end

  # opt-out of 2FA
  def two_factor_enforceable
    return :no if ACTIONS_EXCLUDED_FROM_CAP_CHECKS.include?(action_name)
    :yes
  end

  # Opt-out of IP allowlist enforcement
  def ip_allowlist_enforceable
    return :no if ACTIONS_EXCLUDED_FROM_CAP_CHECKS.include?(action_name)
    super
  end

  # Opt-out of external conditional access enforcement
  def external_conditional_access_policy_enforceable
    return :no if ACTIONS_EXCLUDED_FROM_CAP_CHECKS.include?(action_name)
    super
  end

  # opt-out of SAML
  def require_active_external_identity_session?
    return false if ACTIONS_EXCLUDED_FROM_CAP_CHECKS.include?(action_name)
    super
  end

  def allow_permissions
    #TODO: redirect to create if devcontainer doesn't need allow permissions?
    repository = if current_repo&.pullable_by?(current_user)
      ref = current_repo.refs.find(params[:ref]) if params[:ref].present?
      ref = PullRequest.find_by(id: codespace_params[:pull_request_id])&.head_ref unless ref.present?
      ref ||= current_repo.default_branch_ref
      current_repo
    else
      nil
    end
    query = Codespaces::Query.new(
      current_user: current_user,
      repository: repository,
      ref: ref,
      cap_filter: cap_filter,
    )

    if params[:expected_billable_owner_id] && query.build_codespace.billable_owner_id != ActiveModel::Type::Integer.new.cast(params[:expected_billable_owner_id])
      flash[:error] = "The entity paying for codespaces usage with this repository may have changed, please refresh the page and try again."
      redirect_back(fallback_location: codespaces_path)
      return
    end

    codespace = Codespace.new(codespace_params.merge(owner: current_user))
    devcontainer = build_devcontainer(codespace)

    if devcontainer.diff_all_repository_permissions.present?
      # rubocop:todo GitHub/DontCallAssociatedRepositoryIdsUnbounded
      repo_readable_by_user_count = Repository.where(id: codespace.owner&.associated_repository_ids(organization: codespace.repository&.owner, min_action: :read)).size
    end

    render "codespaces/allow_permissions", locals: {
      open_in_deeplink: user_settings.prefers_non_web_editor?,
      codespace: codespace,
      devcontainer: devcontainer,
      repo_readable_by_user_count: repo_readable_by_user_count,
      create_button_params: {
        user_settings: user_settings,
        data_attributes: helpers.create_codespace_attributes(codespace: codespace, target: "allow_permissions"),
        at_limit: query.at_limit?(codespace.billable_owner),
        user_codespace_limit: query.codespace_limit,
      }
    }, formats: :html
  end

  def allow_settings_sync
    codespace = nil
    if codespace_name = params[:codespace_name].presence
      codespace = current_user&.codespaces&.find_by(name: codespace_name)
      return render_404 unless codespace.present?
    end

    dangerous = current_user&.codespaces_repository_authorization == Configurable::CodespacesRepositoryAuthorization::ALL_REPOSITORIES

    render "codespaces/allow_settings_sync", locals: {
      codespace: codespace,
      dangerous: dangerous,
    }, formats: :html
  end

  def update_settings_sync
    if params[:unsafe].present? && params[:unsafe] == "false"
      current_user&.update_codespaces_repository_authorization(Configurable::CodespacesRepositoryAuthorization::SELECTED_REPOSITORIES, actor: current_user)
    end
    if current_user&.codespaces_settings_sync_authorization == Configurable::CodespacesSettingsSyncAuthorization::DISABLED
      current_user&.update_codespaces_settings_sync_authorization(Configurable::CodespacesSettingsSyncAuthorization::ENABLED, actor: current_user)
    end

    if codespace_name = params[:codespace_name].presence
      codespace = current_user&.codespaces&.find_by(name: codespace_name)
      return render_404 unless codespace.present?

      authorization = current_user&.trusted_repository_authorizations&.find_by(repository_id: codespace.repository&.id)
      if authorization.nil?
        Codespaces::TrustedRepositoryAuthorization.create!(user: current_user, repository: codespace.repository)
      end
    end

    render "codespaces/allow_settings_sync_flow_completed", formats: :html
  end

  def close_window_prompt
    render partial: "codespaces/close_window_prompt", formats: :html
  end

  def prebuild_availability
    return head :not_found unless request.xhr?

    repository = Repositories::Public.find_active!(params[:repository_id])
    return head :not_found unless repository.present?

    begin
      prebuild_availability = Codespaces::FetchPrebuildModeAvailability.call(
        repository: repository,
        location: params[:location],
        devcontainer_path: params[:devcontainer_path].presence,
        ref_name: params[:ref_name],
        vscs_target: params[:vscs_target].present? ? params[:vscs_target] : Codespaces::Vscs.default_target,
        codespace_owner: current_user,
      )

      render json: prebuild_availability
    rescue ActiveModel::ValidationError, Codespaces::Plan::PlanNotFoundForLocation => e
      Failbot.report(
        e,
        "gh.repo.id" => repository.id,
        "gh.codespaces.vscs_target" => params[:vscs_target],
        "gh.codespaces.region" => params[:location],
      )

      render json: { error: e.message }, status: :unprocessable_entity
    end
  end

  def badge
    respond_to do |format|
      format.svg { render partial: "codespaces/open_in_codespaces_badge" }
    end
  end

  def templates
    query = query_for_dashboard
    templates = Codespaces::Template.active
    if current_user&.feature_enabled?(:codespaces_copilot_demo_template) && Codespaces::Template.copilot.active?
      templates[:copilot] = Codespaces::Template.copilot
    end

    valid_targets = Codespaces::Vscs.target_configs.values
    region_config = valid_targets.each_with_object({}) do |config, hash|
      vscs_target = config[:name]
      hash[vscs_target] = Codespaces::VscsServiceStamp.where(vscs_target:).map do |stamp|
        { name: stamp.region.id, display_name: stamp.region.name }
      end
    end

    render "codespaces/templates", locals: {
      templates: templates,
      query: query,
      at_concurrency_limit: !!flash[:at_concurrency_limit],
      vscs_target_configs: valid_targets,
      region_config: region_config,
    }
  end

  private

  def ensure_create_async_operation_created(&block)
    ensure_async_operation_created(:create_codespace, &block)
  end

  def ensure_start_async_operation_created(&block)
    ensure_async_operation_created(:start_codespace, &block)
  end

  def ensure_async_operation_created(operation)
    yield
  rescue => e # rubocop:disable Lint/GenericRescue
    if !request.env["codespaces.async_operation_created"]
      codespaces_automated_testing = begin
        GitHub.flipper[:codespaces_automated_testing].enabled?(current_user)
      rescue # rubocop:disable Lint/GenericRescue
        false
      end
      if ignored_async_error?(e)
        Codespaces::AsyncOperation.report_ended(operation:, codespaces_automated_testing:)
      else
        Codespaces::AsyncOperation.report_failure(operation:, codespaces_automated_testing:, failure_reason: e)
      end
    end
    raise
  end

  def ignored_async_error?(e)
    # ActionController::InvalidAuthenticityToken is a Rails security mechanism and does not indicate anything wrong with the service itself so we do not
    # count it as a failure. Codespaces::AsyncOperation::PendingError is a normal safeguard to prevent starting codespaces while their storage
    # is being updated and similarly does not indicate a failure.
    [ActionController::InvalidAuthenticityToken, Codespaces::AsyncOperation::PendingError].any? { |klass| e.instance_of? klass }
  end

  def aggressive_client_timeouts(&block)
    # Some of our endpoints make one or more API requests synchronously now
    # so we need to be more aggressive with our client timeouts to prevent the
    # web request itself from timing out and being killed.
    Codespaces::Client.with_timeouts({ open_timeout: 2, timeout: 5 }, &block)
  end

  def safe_to_deprovision?
    (params[:force_destroy_id].to_i == current_codespace.id) ||
      !Codespaces::HasUnpushedChanges.call(
        codespace: current_codespace,
        user: current_user
      )
  end

  def query_for_dashboard
    query = Codespaces::Query.new(
      current_user: current_user,
      codespaces_context: Codespaces::Query::ACCESSIBLE_CODESPACES,
      cap_filter: cap_filter
    )
    with_database_error_fallback(fallback: false) { Codespace.prefill_associations_for_dashboard(query.codespaces) }

    query
  end

  def query_for_codespaces_list
    pull_request = with_database_error_fallback(fallback: nil) do
      PullRequest.find_by(id: codespace_params[:pull_request_id]) if params[:codespace] && codespace_params[:pull_request_id]
    end
    ref = codespace_params[:ref].presence if params[:codespace]
    query = Codespaces::Query.new(
      current_user: current_user,
      repository: current_repo,
      ref: ref,
      pull_request: pull_request,
      codespaces_context: params[:context].presence,
      cap_filter: cap_filter
    )
    with_database_error_fallback(fallback: false) do
      Codespace.prefill_associations_for_dashboard(query.codespaces)
    end
    query
  end

  def render_codespaces_list_component(query:)
    show_actions = ActiveModel::Type::Boolean.new.cast(params.fetch(:show_actions, true))

    return render_404 unless current_repo

    render(Codespaces::DropdownListComponent.new(
      query: query,
      user_settings: user_settings,
      event_target: params[:event_target],
      pr_dropdown: ActiveModel::Type::Boolean.new.cast(params[:pr_dropdown]),
      show_actions: show_actions,
      current_branch: params[:current_branch],
      missing_head_repo: ActiveModel::Type::Boolean.new.cast(params[:missing_head_repo]), # In this case, the query's repo is going to be the PR base repo
      missing_head_ref: ActiveModel::Type::Boolean.new.cast(params[:missing_head_ref]),
      available_skus: Codespaces::Skus.allowed_skus_with_owner_and_billable_owner(current_user, query.repository_policy.billable_owner)
    ), layout: false)
  end

  def codespace_new_params
    params.permit(:new, :hide_repo_select, :repo, :ref, :machine, :location, :fix_suggestion)
  end

  def codespace_update_params
    params.require(:codespace).permit(:sku_name, :display_name, :keep)
  end

  def identifier
    params[:identifier]
  end

  def require_pullable_repo
    render_404 unless current_repo&.pullable_by?(current_user)
  end

  def user_settings # rubocop:todo GitHub/ControllersShouldUseMemoizeForMemoization
    @user_settings ||= Codespaces::Settings.for_user(current_user)
  end

  def render_external_identity_session_required
    respond_to do |format|
      format.html_fragment { head :unauthorized }
      format.any { super }
    end
  end

  def build_devcontainer(codespace)
    ref = codespace.ref.presence || codespace.pull_request&.head_ref
    ref_for_oid = Codespaces::GetTargetRef.call(repository: codespace.repository, name_or_oid: ref) if ref.present?
    target_oid = ref_for_oid&.target_oid

    return unless target_oid

    devcontainer_path = codespace.devcontainer_path.presence

    Codespaces::DevContainer.new(
      repository: codespace.repository,
      oid: target_oid,
      filepath: devcontainer_path,
      user: current_user
    )
  end

  def vscs_target(input:)
    if current_user&.feature_enabled?(:codespaces_developer)
      config = Codespaces::Vscs.target_configs[input&.to_sym] || Codespaces::Vscs.default_target_config
      config[:name]
    else
      Codespaces::Vscs.default_target
    end
  end
end
