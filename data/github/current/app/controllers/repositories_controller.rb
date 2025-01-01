# typed: false
# frozen_string_literal: true

class RepositoriesController < AbstractRepositoryController
  map_to_service :star, only: [:watchers, :stargazers, :stargazers_you_know] # rubocop:todo GitHub/MapToService
  map_to_service :repos_insights, only: [:pulse, :pulse_committer_data, :pulse_diffstat_summary] #rubocop:todo GitHub/MapToService

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Configurations,
    ApplicationRecord::Spokes,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Memex,
    ApplicationRecord::Billing,
    ApplicationRecord::Iam,
    only: [:stargazers]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::Spokes,
    ApplicationRecord::Mysql2,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Memex,
    only: [:stargazers_you_know]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Spokes,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Memex,
    only: [:pulse]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    ApplicationRecord::Billing,
    only: [:index]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Repositories,
    ApplicationRecord::Permissions,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Billing,
    only: [:new]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Spokes,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Memex,
    ApplicationRecord::Billing,
    ApplicationRecord::Iam,
    only: [:watchers]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Billing,
    ApplicationRecord::Iam,
    only: [:packages_list]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    only: [:contributors]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    only: [:used_by_list]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Spokes,
    ApplicationRecord::IssuesPullRequests,
    only: [:pulse_committer_data]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Spokes,
    ApplicationRecord::IssuesPullRequests,
    only: [:pulse_diffstat_summary]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Spokes,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    only: [:compact_associated_pulls]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Spokes,
    ApplicationRecord::Configurations,
    only: [:deployments_environment_state]

  depends_on_clusters ApplicationRecord::Mysql1,
    only: [:go_metatag]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Spokes,
    ApplicationRecord::Mysql2,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Ballast,
    ApplicationRecord::Memex,
    ApplicationRecord::Billing,
    only: [:no_content_tabs]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Repositories,
    only: [:no_content]

  depends_on_clusters ApplicationRecord::Configurations,
    ApplicationRecord::Ballast,
    ApplicationRecord::Memex,
    ApplicationRecord::Mysql5,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Spokes,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    only: [:no_content],
    optional: true

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Spokes,
    only: [:full_associated_pulls]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [
      :contributors,
      :deployments_environment_state,
      :index,
      :new,
      :pulse_committer_data,
      :pulse_diffstat_summary,
      :pulse,
      :stargazers_you_know,
      :stargazers,
      :watchers,
      :no_content_tabs,
      :packages_list,
    ],
    optional: true

  CONDITIONAL_ACCESS_BYPASS_ACTIONS = %w(check_name).freeze
  CONDITIONAL_ACCESS_BYPASS_PUBLIC_REPO_ACTIONS = %w(packages_list contributors_list used_by_list sponsors_list environment_status).freeze
  STARGAZERS_PER_PAGE = 48

  include BillingSettingsHelper
  include ReactHelper
  include TradeControlsHelper
  include OrganizationsHelper
  include SecurityAnalysisSettingsHelper
  include Registry::QueryHelper
  include RepositoriesDefaultSelectionHelper
  include TradeControlsHelper
  include Repos::OwnerRepoSelectionsPayloadHelper
  include RepositoryAnalyticsHelper
  include DeploymentsHelper
  include ApplicationController::VerifiedFetchDependency
  include GitHub::Memoizer
  include ApplicationController::JsonDependency
  include Orgs::CustomPropertiesHelper

  if GitHub.enterprise?
    skip_before_action :ask_the_gatekeeper, only: [:go_metatag]
    skip_before_action :enforce_private_mode, only: [:go_metatag]
    skip_before_action :privacy_check, only: [:go_metatag]
    skip_before_action :network_privilege_check, only: [:go_metatag]
    before_action :ensure_repository_specified, only: [:go_metatag]
  end

  skip_before_action :ask_the_gatekeeper, only: [:my_forks_menu_content]
  skip_before_action :authorization_required
  before_action :login_required, only: %w(create check_name)
  before_action :login_required_with_redirect, only: :new
  before_action :content_authorization_required, only: %w(create new)
  before_action :enforce_plan_supports_insights, only: :pulse

  before_action :network_privilege_for_opt_in, only: %w(opt_in_to_view)
  before_action :network_privilege_check, except: %w(opt_in_to_view)
  before_action :parse_json_params, only: [:create]

  layout "repository"
  javascript_bundle :repositories

  allow_verified_fetch only: [:create, :repository_templates_for_current_user, :check_name]

  def self.react_bundle_name
    "repo-creation"
  end

  def index
    return render_404 if params[:organization_id]

    respond_to do |format|
      format.html do
        if GitHub.enterprise?
          render "repositories/recent", layout: "application"
        else
          redirect_to "/trending"
        end
      end
      format.atom do
        render "repositories/index", layout: false
      end
    end
  end

  def new
    title = "New repository"
    context_region_title(title) unless params[:organization_id]

    add_csrf_token(repository_check_name_path, :post)

    tags = ["form:create"]
    tags << "defer_owners_list:#{current_user.organizations.size > Repositories::CreateView::ORG_COUNT_DEFER_LIMIT}"
    payload = GitHub.dogstats.distribution_time("repos_form.payload.time", tags: tags) do
      if GitHub.create_repo_perf?
        context_region_title title
        prepare_new_view(seed_name: params[:profile_readme] ? current_user&.display_login : nil)
        return render "repositories/new", layout: "application"
      end

      owner_items = initial_owner_items_payload(cap_filter, current_user)
      initial_owner_selection = initial_owner_or_default_payload(params[:owner], cap_filter, current_user, current_organization)
      has_template_repos = current_user.quick_has_repository_templates?(current_user)
      name_is_restricted = false
      if current_organization.present? && current_organization.feature_enabled?(:member_privilege_rulesets)
        name_is_restricted = RulesEngine::RepositoryActionEvaluator.organization_is_protected?(current_organization, ["restrict_repository_name"])
      end

      if params[:template_owner].present? && params[:template_name].present?
        repo = Repository.nwo(params[:template_owner], params[:template_name])
        selected_template = {
          id: repo.id,
          nameWithDisplayOwner: repo.name_with_display_owner,
          ownerDisplayLogin: repo.owner.display_login,
          avatarUrl: repo.owner.primary_avatar_url,
        } if repo && repo.template? && repo.readable_by?(current_user) && (repo.public? || required_external_identity_session_present?(target: repo.owner))
      end

      {
        repoCreate: Repos::ReactPayload.repo_create_payload(owner_items, cap_filter, current_user),
        initialOwnerSelection: initial_owner_selection,
        currentUserLogin: current_user.display_login,
        suggestedRepoName: Repository::SuggestedName.generate,
        privateModeEnabled: GitHub.private_mode_enabled?,
        isGithubEnterprise: GitHub.enterprise?,
        tradeControlsPrivateRepoCreationWarning: trade_controls_private_repo_creation_warning,
        tradeControlsUserPrivateRepoCreationWarning: trade_controls_user_private_repo_creation_warning,
        hasTemplateRepos: has_template_repos || !selected_template.nil?,
        selectedTemplate: selected_template,
        licenses: License.sorted_list.map do |license|
          {
            id: license.key,
            text: license.name,
          }
        end,
        publicReposAvailable: GitHub.public_repositories_available?,
        repositoryImportLinkDataAttributes: GitHub.porter_available? ? repository_import_link_data_attributes : nil,
        nameIsRestricted: name_is_restricted,
      }
    end

    page_data = { send_vitals: true }
    page_data[:selected_link] = :repositories if params[:organization_id]

    add_client_feature_flag(:custom_properties_edit_modal)

    render_react_app(
      title: title,
      layout: "application",
      payload: payload,
      page_data: page_data,
      ssr: feature_enabled_globally_or_for_current_user?(:repos_forms_ssr),
    )
  end

  def repository_templates_for_current_user # rubocop:todo GitHub/UseRestfulActions
    template_repos = current_user.repository_templates_for(current_user, cap_filter: cap_filter).map do |repo|
      {
        id: repo.id,
        nameWithDisplayOwner: repo.name_with_display_owner,
        ownerDisplayLogin: repo.owner.display_login,
        avatarUrl: repo.owner.primary_avatar_url,
      }
    end

    respond_to do |format|
      format.json do
        render json: {
          templateRepos: template_repos,
        }
      end
    end
  end

  private def visibility_from_params
    return repository_params[:visibility] if repository_params[:visibility]
    return "public" if repository_params[:public]&.to_s == "true"
    "private"
  end

  def create
    requested_owner = User.find_by_login(params[:owner])

    return render_404 unless requested_owner
    visibility = visibility_from_params
    unless requested_owner.can_create_repository?(current_user, visibility: visibility)
      visibility_flash_error = "Members of that org can not create #{visibility} repositories."
      return render(json: { data: { error: visibility_flash_error }, code: 422 }, status: :unprocessable_entity)
    end

    # Honor SAML auth for template repo's org _before_ we create a new empty repo.
    if template_repository && !template_repository.public && !required_external_identity_session_present?(target: template_repository.owner)
      render_external_identity_session_required(target: template_repository.owner)
      return
    end

    owner_has_billing = requested_owner.has_valid_payment_method?
    reflog_data = request_reflog_data(requested_owner, computed_repository_params.to_h, "initial commit")
    result = create_repository(requested_owner, reflog_data, custom_properties: custom_properties_from_params)

    if requested_owner&.organization?
      required_properties_present = CustomProperties::Public.definitions_manager(T.cast(requested_owner, Organization)).get_definitions.count { |definition| definition.required } > 0
    end

    tags = ["form:create"]
    tags << "template:#{params[:template_repository_id].present?}"
    tags << "include_all_branches:#{params[:include_all_branches] == "1"}"
    tags << "auto_init:#{computed_repository_params[:auto_init] || 'false'}"
    tags << "license:#{value_or_none(computed_repository_params[:license_template])}"
    tags << "gitignore:#{value_or_none(computed_repository_params[:gitignore_template])}"
    tags << "custom_properties:#{custom_properties_from_params.present?}"
    tags << "required_properties_present:#{required_properties_present}"
    tags << "error:#{!result.success?}"
    GitHub.dogstats.increment("repos_form_submit", tags: tags)

    if result.success?
      track_ga_event(result.repository, owner_has_billing)

      flash[:just_created] = true

      unless params[:template_repository_id].blank?
        orchestration = RepositoryOrchestration.clone_template(
          template_repository: template_repository,
          actor: current_user,
          new_repository: result.repository,
          copy_branches: params[:include_all_branches] == "1",
        )

        if orchestration.valid?
          orchestration.execute!

          flash[:warn] = "Could not clone: #{orchestration.error_message}" if orchestration.failed?
        else
          flash[:warn] = "Could not clone: #{orchestration.errors.full_messages.join(", ")}"
        end
      end

      if result.template_hook_failure
        flash[:error] = "A pre-receive hook prevented content from being added to your new repository: #{result.template_hook_failure}"
      end

      if result.repository.user_configuration_repository?
        requested_owner.profile_readme_opt_in = true
        requested_owner.profile.save
      end

      install_selected_marketplace_apps(requested_owner, result.repository)

      respond_to do |format|
        format.html do
          redirect_to clean_repository_path(result.repository)
        end
        format.json do
          render(json: { data: { redirect: clean_repository_path(result.repository) } }, status: :ok)
        end
      end
    else
      @repository = result.repository
      @owner = @repository&.owner ? @repository.owner : requested_owner
      @experiment_form = params[:experiment_form].present?
      return_to_on_error = params[:return_to_on_error]

      if return_to_on_error.present?
        flash[:error] = result.error_message.to_s || "Repository cannot be created."
        return safe_redirect_to return_to_on_error
      end

      if !result.privatization_billing_error? || current_user.has_any_trade_restrictions?
        post_create_error = result.error_message.to_s
        return render(json: { data: { error: post_create_error }, code: 422 }, status: :unprocessable_entity)
      end

      render(json: { data: { error: "Repository cannot be created." }, code: 400 }, status: :bad_request)
    end
  end

  def install_selected_marketplace_apps(requested_owner, new_repository) # rubocop:todo GitHub/UseRestfulActions
    manual_install = params[:quick_install][requested_owner.display_login] if params[:quick_install]
    manual_install ||= {}

    manual_install_successes = []
    manual_install_failures = []
    auto_install_successes = []

    Marketplace::Listing.quick_installable_for(requested_owner).each do |listing, auto_install|
      if auto_install
        auto_install_successes << listing
      elsif manual_install[listing.id.to_s].present?
        installation = requested_owner.integration_installations.find_by(integration_id: listing.listable_id)

        install_result = IntegrationInstallation::RepositoryEditor.perform(
          installation,
          action: :add,
          repositories: [new_repository],
          editor: current_user,
          entry_point: :repositories_controller_install_selected_marketplace_apps
        )

        if install_result.success?
          manual_install_successes << listing
        else
          manual_install_failures << listing
        end
      end
    end

    install_successes = auto_install_successes + manual_install_successes

    if install_successes.any?
      verb = "was".pluralize(install_successes.size)
      flash[:notice] = "#{install_successes.map(&:name).to_sentence} #{verb} installed on this repository"
    end
    if manual_install_failures.any?
      failed_apps = manual_install_failures.map(&:name).to_sentence(two_words_connector: " or ", last_word_connector: " or ")
      flash[:error] = "Unable to install #{failed_apps} on this repository"
    end

    if install_successes.any? || manual_install_failures.any?
      GlobalInstrumenter.instrument("marketplace.new_repo_quick_install", {
        user:  current_user,
        action: :installed,
        repository: new_repository,
        categorized_listings: {
          auto_install_listings: auto_install_successes,
          manual_install_listings: manual_install_successes,
          failed_manual_install_listings: manual_install_failures
        },
      })
    end
  end

  # Used for the autochecker on the new repository form and from the rename
  # repository form to validate repository names on the fly.
  def check_name # rubocop:todo GitHub/UseRestfulActions
    if params[:owner]
      owner = User.find_by_login(params[:owner])
      return render_404 unless owner
    else
      owner = current_user
    end

    return render_404 unless owner.can_create_repository?(current_user) || can_rename_repository?(owner)

    if params[:current_name].present? &&
      repo = owner.find_repo_by_name(params[:current_name])
      repo.name = params[:value]
    else
      repo = owner.repositories.build(name: params[:value])
    end
    repo.valid?

    # appends to repo.errors
    RulesEngine::RepositoryActionEvaluator.can_rename_repository?(repo, current_user, false)

    json_response = params[:json_response]

    respond_to do |format|
      format.html_fragment do
        if repo.errors[:name].any?
          if json_response
            return render json: { repo: repo.name, errors: repo.errors[:name].to_sentence }, status: 422
          end
          return render partial: "repositories/check_name_error",
                 locals: { repository: repo },
                 status: :unprocessable_entity,
                 formats: :html
        elsif params[:value] != repo.name
          if json_response
            return render json: { repo: repo.name }
          end
          return render partial: "repositories/check_name_warning",
                 locals: { repository: repo, user_input_name: params[:value], margin: params[:margin] },
                 status: :accepted,
                 formats: :html
        else
          if json_response
            return render json: { repo: repo.name }
          end
          return render html: "#{repo.name} is available."
        end
      end
    end
  end

  def watchers # rubocop:todo GitHub/UseRestfulActions
    @watchers_response = current_repository.watchers(current_page, 51)
    @watchers = @watchers_response.value
    render "repositories/watchers"
  end

  def stargazers # rubocop:todo GitHub/UseRestfulActions
    stars = current_repository
      .stars
      .filter_spam_for(current_user)
      .includes(user: :profile)
      .order("stars.created_at DESC, stars.user_hidden DESC, stars.id DESC")
      .simple_paginate(page: current_page, per_page: STARGAZERS_PER_PAGE)

    if logged_in?
      stargazers = stars.filter_map(&:user)
      GitHub::PrefillAssociations.prefill_batch_method(stargazers, :followed_by?, current_user)
    end

    render "repositories/stargazers", locals: {
      stars: stars,
    }
  end

  def stargazers_you_know # rubocop:todo GitHub/UseRestfulActions
    return redirect_to_login(stargazers_you_know_url) unless logged_in?
    @stargazers_you_know = User.following_starred(current_user.id, current_repository.id)
      .includes(:profile)
      .simple_paginate(page: current_page, per_page: STARGAZERS_PER_PAGE)

    GitHub::PrefillAssociations.prefill_batch_method(@stargazers_you_know, :followed_by?, current_user)

    render "repositories/stargazers_you_know"
  end

  def contributors # rubocop:todo GitHub/UseRestfulActions
    redirect_to contributors_graph_url
  end

  def packages_list # rubocop:todo GitHub/UseRestfulActions
    # `Files::SidebarListComponent` actually allows displaying one more package than `MAX_COUNT`.
    # This means that we need to fetch up to `MAX_COUNT + 1` packages to ensure that we can display all of them.
    # If we only provide `MAX_COUNT` packages, the user will not see the package but also not see a "more" button.
    # Only if there are more than `MAX_COUNT + 2` packages, we will show a "more" button.
    per_page = Files::SidebarListComponent::MAX_COUNT + 1

    results, packages = packages_for_query(
      current_user: current_user,
      user_session: user_session,
      owner: current_repository.owner,
      repo_id: current_repository.id,
      sort: SORT_TO_QUERY_PARAM["downloads_desc"],
      page: 1,
      per_page: per_page,
      fail_fast: true,
      use_cached_versions: true
    )

    if results.total == 0
      GitHub.dogstats.increment("repositories.packages_sidebar.no_packages_found")
    else
      GitHub.dogstats.increment("repositories.packages_sidebar.packages_found")
    end

    respond_to do |format|
      format.html do
        render partial: "files/sidebar/packages_list", locals: {
          packages: packages,
          repository_packages_count: results.total,
          repository_writable: current_repository.writable_by?(current_user),
        }
      end
    end
  end

  def contributors_list # rubocop:todo GitHub/UseRestfulActions
    items_to_show = params[:items_to_show].to_i
    respond_to do |format|
      format.html do
        render partial: "files/sidebar/contributors_list", locals: {
          items_to_show: items_to_show,
          contributors: current_repository.top_contributors(
            limit: items_to_show,
            viewer: current_user,
            skip_bots: user_feature_enabled?(:contributors_testing_skip_bots)
          )
        }
      end
    end
  end

  # On-demand list of forks rendered in the Fork dropdown button
  def my_forks_menu_content # rubocop:todo GitHub/UseRestfulActions
    # can_fork is a visual change only, so it's fine to pass in from the other request. the actual logic
    # is checked on the create fork page. default to true for anonymous users for that reason.
    render(Repositories::ForkButtonContentComponent.new(
      repository: current_repository,
      can_fork: params[:can_fork] != "false",
      ), layout: false)
  end

  DEPENDENTS_LIMIT = 8
  HIDE_USED_BY = 100
  def used_by_list # rubocop:todo GitHub/UseRestfulActions
    result = Platform::Loaders::Dependencies.load_packages({
      package_filter: {
        repository_id: current_repository.id,
        first: 1,
        package_id: current_repository.used_by_package_id,
        preview: current_repository.dependency_graph_preview?,
      },
      dependents_filter: {
        type: :repository,
        first: DEPENDENTS_LIMIT,
      },
      include_dependents: true,
    }).sync

    package = result.ok? ? result.value!.first : nil
    package&.load_dependent_repositories(current_user)
    num_dependents = package&.repository_dependents_count || 0

    respond_to do |format|
      format.html_fragment do
        if package
          if num_dependents < HIDE_USED_BY
            render plain: ""
          else
            render partial: "files/sidebar/used_by_list",
                   locals: {
                     package: package,
                     dependents_limit: DEPENDENTS_LIMIT,
                     repository_dependents_count: num_dependents
                   },
                   formats: :html
          end
        else
          render plain: ""
        end
      end
    end
  end

  def sponsors_list # rubocop:todo GitHub/UseRestfulActions
    sponsorables = current_repository.funding_links.sponsorable_users
    if sponsorable_org = current_repository.funding_links.sponsorable_org
      sponsorables << sponsorable_org
    end

    GitHub::PrefillAssociations.prefill_batch_method(sponsorables, :sponsored_by_viewer?, current_user)
    GitHub::PrefillAssociations.prefill_batch_method(sponsorables, :async_sponsorable_by?, current_user)

    respond_to do |format|
      format.html do
        render partial: "files/sidebar/sponsors_list", locals: {
          block_button: params[:block_button] == "true",
          sponsorables: sponsorables
        }
      end
    end
  end

  def environment_status # rubocop:todo GitHub/UseRestfulActions
    deployment = current_repository.deployments.unscoped.where(repository_id: current_repository.id, latest_environment: params[:environment]).order(created_at: :desc).first

    respond_to do |format|
      format.html do
        render partial: "files/sidebar/deployment_status", locals: { deployment: deployment, environment_name: params[:environment] }
      end
    end
  end

  def pulse # rubocop:todo GitHub/UseRestfulActions
    respond_to do |format|
      format.html do
        details_view = Repositories::DetailsView.new(
          repository: current_repository,
          repository_is_offline: repository_offline?,
          cap_view_filter: cap_view_filter,
          viewer_can_read_repo: current_user_can_read_repo?,
        )
        render "repositories/pulse", locals: { forking_allowed: details_view.forking_allowed? }
      end
    end
  end

  def pulse_committer_data # rubocop:todo GitHub/UseRestfulActions
    render json: current_repository.activity_summary(viewer: current_user, period: params[:period]).authors_with_commits
  end

  def pulse_diffstat_summary # rubocop:todo GitHub/UseRestfulActions
    view = Repositories::PulseView.new(current_repository, params[:period], current_user)

    respond_to do |format|
      format.html do
        render partial: "repositories/pulse/diffstat_summary",
               locals: { view: view }
      end
    end
  end

  def deployments_environment_state # rubocop:todo GitHub/UseRestfulActions
    return render_404 unless request.xhr?

    deployments = load_deployments(environments: params[:environment], limit: 10)
    latest_active = deployments.find(&:active?)
    return render_404 unless latest_active

    commit = Platform::Loaders::GitObject.load(current_repository, latest_active.sha, expected_type: :commit).sync

    respond_to do |format|
      format.html do
        render partial: "repositories/deployments_environment_state", locals: {
          deployment: latest_active,
          commit: commit,
        }
      end
    end
  end

  def full_associated_pulls # rubocop:todo GitHub/UseRestfulActions
    deployment, commit, pull_requests = load_deployment_pull_request_data

    respond_to do |format|
      format.html do
        render partial: "repositories/full_associated_pulls", locals: {
          deployment: deployment,
          commit: commit,
          pull_requests: pull_requests,
        }
      end
    end
  end

  def compact_associated_pulls # rubocop:todo GitHub/UseRestfulActions
    deployment, commit, pull_requests = load_deployment_pull_request_data

    respond_to do |format|
      format.html do
        render partial: "repositories/compact_associated_pulls", locals: {
          deployment: deployment,
          commit: commit,
          pull_requests: pull_requests,
        }
      end
    end
  end

  # handle requests from the Go language tooling to determine location and type of VCS of a Go import path.
  # Valid requests must have a query string of ?go-get=1 (https://golang.org/cmd/go/#hdr-Remote_import_paths)

  if GitHub.enterprise?
    def go_metatag # rubocop:todo GitHub/UseRestfulActions
      render_404 unless params["go-get"] == "1"
      repopath = "/" + params[:user_id] + "/" + params[:repository]
      prefix = GitHub.host_name + repopath
      reporoot = GitHub.url + repopath + ".git"
      render "repositories/go_metatag", locals: {
        prefix: prefix,
        reporoot: reporoot,
      }, status: 200, layout: false
    end
  end

  def opt_in_to_view # rubocop:todo GitHub/UseRestfulActions
    return_to = params[:return_to]

    begin
      GitHub.kv.set(opt_in_kv_key, "1", expires: 30.days.from_now) # rubocop:todo GitHub/DoNotUseGlobalKv
    rescue GitHub::KV::UnavailableError
      # If KV unavailable we default to showing the interstitial, so override via query param instead
      uri = Addressable::URI.parse(return_to)
      uri.query_values = (uri.query_values || {}).merge({ opt_in_to_view: 1 })
      return_to = uri.to_s
    end

    GitHub.dogstats.increment("network_privileges.opt_in_to_view")

    safe_redirect_to return_to
  end

  def dismiss_content_warning_banner # rubocop:todo GitHub/UseRestfulActions
    return redirect_to_login unless logged_in?

    begin
      # rubocop:todo GitHub/DoNotUseGlobalKv
      GitHub.kv.set(dismiss_content_warning_banner_kv_key, "1", expires: 30.days.from_now)
      # rubocop:enable GitHub/DoNotUseGlobalKv
    rescue GitHub::KV::UnavailableError
      # no-op
    end

    GitHub.dogstats.increment("network_privileges.dismiss_content_warning_banner")

    safe_redirect_to params[:return_to]
  end

  # Debugging performance around repository layouts
  def no_content # rubocop:todo GitHub/UseRestfulActions
    render "repositories/no_content"
  end

  # Debugging performance around repository layouts
  def no_content_tabs # rubocop:todo GitHub/UseRestfulActions
    render "repositories/no_content_tabs"
  end

  private

  def template_repository
    if params[:template_repository_id]
      Repository.active.filter_spam_and_disabled_for(current_user).
                 find_by(id: params[:template_repository_id])
    end
  end

  memoize def computed_repository_params
    repository_params.merge auto_init: repository_params[:auto_init] == "1"
  end

  def repository_params
    return ActionController::Parameters.new unless params.key?(:repository)

    permitted_fields = %i[
      name
      description
      homepage
      public
      visibility
      license_template
      gitignore_template
      team_id
      auto_init
      template
    ]
    params.require(:repository).permit(permitted_fields)
  end

  def custom_properties_from_params
    return nil unless params.key?(:custom_properties)

    params.fetch(:custom_properties).permit!.to_h
  end

  def value_or_none(value)
    value.present? ? value : "none"
  end

  def login_required_with_redirect
    redirect_to_login(request.url) unless logged_in?
  end

  def current_repositories # rubocop:todo GitHub/ControllersShouldUseMemoizeForMemoization
    @repositories ||= Repository.find_all_public(current_page).
      includes([:mirror, :primary_language, :owner, :parent, :topics])
  end
  helper_method :current_repositories

  def stargazers_you_know_count # rubocop:todo GitHub/ControllersShouldUseMemoizeForMemoization
    @stargazers_you_know_count ||= current_user.following_starred(current_repository.id).count
  end
  helper_method :stargazers_you_know_count

  # Handle auth specifics for feed requests.
  include GitHub::Authentication::Feed

  # Private: Actions that can response to atom requests.
  #
  # Returns an Array or Strings.
  def feed_actions
    %w(index)
  end

  def track_ga_event(repo, owner_has_billing)
    ga_label = {
      target: repo.owner.type,
      billing: owner_has_billing,
      repo: (repo.public? ? "public" : "private"),
    }

    analytics_event(
      category: "Repository",
      action: "create",
      label: ga_label,
    )
  end

  # Private - Create a new repository for the requested owner
  #
  # requested_owner - a User/Organization object that will own the new repo.
  # reflog_data     - Reflog data
  # custom_properties - Custom properties to be set on the repository
  #
  # Returns a Repository::Creatable::Result object indicating the success of the
  # repository creation operation.
  def create_repository(requested_owner, reflog_data, custom_properties: nil)
    Repository.handle_creation(
      current_user,
      requested_owner.login, # rubocop:disable GitHub/DoNotAllowLogin login used for creation
      computed_repository_params.to_h,
      reflog_data,
      payment_details,
      custom_properties: custom_properties
    )
  end

  def content_authorization_required
    authorize_content(:repo)
  end

  def request_reflog_data(owner, repository, via)
    {
      real_ip: request.remote_ip,
      repo_name: "#{owner.display_login}/#{repository[:name]}",
      user_login: current_user.display_login,
      user_agent: request.user_agent,
      from: GitHub.context[:from],
      via: via,
    }
  end

  def target_for_conditional_access
    target =
      if action_name == "new"
        params[:organization_id] || params[:user_id] || params[:owner]
      elsif action_name == "create"
        params[:owner] || params[:user_id] || params[:organization_id]
      else
        params[:user_id] || params[:organization_id] || params[:owner]
      end

    user = User.find_by_login(target)
    return user if user
    return current_organization if current_organization
    return current_user if current_user
    return current_repository.target_for_conditional_access if current_repository
    :no_target_for_conditional_access # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
  end

  # For actions like `index`, `new`, and `create` there is no `current_repository`
  # which would otherwise be used as `resource_for_conditional_access`.
  #
  # See logic in ApplicationController#perform_conditional_access_checks.
  def resource_for_conditional_access
    return self if %w(index new create).include?(action_name)
    super
  end

  def prepare_new_view(seed_name: nil)
    @owner = current_organization || current_user
    repo_private = @owner.private_repo_by_default?
    if params[:profile_readme] && @owner.organization?
      seed_name = params[:profile_readme] == "member" ? @owner.config_private_repo_name : @owner.config_repo_name
      repo_private = params[:profile_readme] == "member"
    end
    @repository = Repository.new(private: repo_private)
    @repository.name = seed_name if seed_name.present?
  end

  def ensure_repository_specified
    render_404 unless repository_specified?
  end

  def stateless_request?
    action_name == "go_metatag" || super
  end

  def can_rename_repository?(owner)
    return false unless params[:current_name]

    repository = owner.find_repo_by_name(params[:current_name])
    repository&.adminable_by?(current_user)
  end

  def load_deployment_pull_request_data
    deployment = current_repository.deployments.find(params[:deployment_id])
    commit = Platform::Loaders::GitObject.load(current_repository, deployment.sha, expected_type: :commit).sync
    pull_requests = if commit
      commit.async_associated_pull_requests(
        order_by: { field: "created_at", direction: "ASC" },
        viewer: current_user
      ).sync.take(5)
    else
      []
    end

    [deployment, commit, pull_requests]
  end

  def load_deployments(environments:, limit:, page: nil) # rubocop:todo GitHub/UseRestfulActions
    deployments = current_repository.deployments
    deployments = deployments.where(latest_environment: environments) if environments.present?
    deployments = deployments.reorder(created_at: :desc, id: :desc)

    if page
      collection = deployments.select(:id).simple_paginate(per_page: limit, page: page)
      ids = collection.map(&:id)
    else
      ids = deployments.limit(limit).pluck(:id)
    end

    records = Deployment.where(id: ids).to_a

    # Preserve ordering from ids query that ordered by created at
    records.sort_by! { |record| ids.index(record.id) }

    if collection
      collection.replace(records)
      collection
    else
      records
    end
  end

end
