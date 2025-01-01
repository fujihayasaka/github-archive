# typed: false
# frozen_string_literal: true

class RegistryTwo::PackagesController < RegistryTwo::Controller
  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::Collab,
    ApplicationRecord::IamAbilities,
    only: [:ecosystem_index]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Collab,
    only: [:index]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Repositories,
    ApplicationRecord::Spokes,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Iam,
    ApplicationRecord::Memex,
    only: [:package_view]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Spokes,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Memex,
    ApplicationRecord::Iam,
    only: [:show]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:show, :package_view],
    optional: true

  UNLINK_REPO_ID = 0
  before_action :redirect_legacy_packages, only: [:show, :package_view_redirect, :package_view]
  before_action :ensure_v2_ui_enabled, only: [:show, :package_view_redirect, :package_view]
  before_action :ensure_supported_ecosystem, only: [:show, :package_view_redirect, :package_view]
  before_action :get_metadata, only: [:show, :package_view_redirect, :repo_dialog, :edit, :commit, :package_view]
  before_action :get_tagged_metadata, only: [:package_view]
  before_action :ensure_can_see_package_view, only: [:package_view_redirect, :package_view, :repo_dialog, :update_repo]
  before_action only: :package_view do
    repo_scoped_redirect(:repo_packages_two_view_path)
  end
  before_action only: :show do
    repo_scoped_redirect(:repo_package_two_path)
  end
  before_action :redirect_latest, only: :show
  before_action :spammy_behaviour_check
  before_action :ensure_package_admin, only: [:restore, :edit]
  skip_before_action :cap_pagination

  stylesheet_bundle :settings

  def index
    # We already have an org_packages path so if we hit this action,
    # it is implied that owner_type is `users`.
    args = "?tab=packages"
    args += "&q=#{params[:q]}" if params[:q].present?
    args += "&repo_name=#{params[:repo_name]}" if params[:repo_name].present?

    redirect_to user_path(owner) + args
  end

  def ecosystem_index # rubocop:todo GitHub/UseRestfulActions
    if owner.organization?
      redirect_to org_packages_path(owner, ecosystem: params[:ecosystem])
    else
      redirect_to user_path(owner) + "?tab=packages&ecosystem=#{params[:ecosystem]}"
    end
  end

  def show
    get_package_version.tap do |package_version|
      return render_404 unless package_version

      # If GHES with V2 enabled, OR non-GHES with download counts flag enabled
      download_counts = if !GitHub.enterprise? || PackageRegistryHelper.ghes_registry_v2_enabled?
        client.get_package_version_download_counts(
          package_id: package_version.package_id,
          version_id: params[:version].to_i
        )
      else
        PackageRegistry::DownloadCounts::NULL
      end

      assets = nil
      if !GitHub.enterprise? && RegistryTwo::MembersHelper::NON_CONTAINER_V2_ECOSYSTEMS.include?(params[:ecosystem])
        assets = client.get_package_version_files(version_id: params[:version].to_i)
      end

      if params[:ecosystem] == "container"
        tag = params[:tag]
        # If a tag is provided, but doesn't correspond to the package version, unset it and flash
        # a message letting the user know it does not exist on this version
        if tag && !package_version.metadata.tags.any? { |t| t.name == tag }
          flash[:error] = "Tag '#{tag}' does not exist for this package version"
          tag = nil
        end
      end

      view = create_view_model(
        RegistryTwo::Packages::ShowView,
        owner: owner,
        package: @metadata.package,
        package_versions: @metadata.package_versions,
        package_version: package_version,
        repository: repository,
        package_tag: tag,
        package_download_counts: download_counts,
        assets: assets,
        viewer_is_admin: package_admin?,
        viewer_can_read_repo: current_user_can_read_repo?,
        user_type: params[:user_type] || get_owner_type,
        current_user: current_user
      )

      if params[:ecosystem] == "container"
        render "registry_two/packages/show", locals: { view: view }
      else
        render "registry_two/packages/non_container_version_show", locals: { view: view }
      end
    end
  end

  def edit
    get_package_version.tap do |package_version|
      return render_404 unless package_version

      view = create_view_model(
        RegistryTwo::Packages::ShowView,
        owner: owner,
        package: @metadata.package.package,
        package_version: package_version,
        repository: @metadata.package.repository,
        viewer_can_read_repo: current_user_can_read_repo?,
        user_type: params[:user_type] || get_owner_type
      )
      render "registry_two/packages/edit", locals: { view: view }
    end
  end

  def preview # rubocop:todo GitHub/UseRestfulActions
    markdown = params[:text]
    context = { base_url: base_url, current_user: current_user }

    html = GitHub.dogstats.time("markdown", tags: ["action:preview"]) do
      GitHub::Goomba::MarkdownPipeline.to_html(markdown, context)
    end

    render html: html
  end

  def commit # rubocop:todo GitHub/UseRestfulActions
    get_package_version.tap do |package_version|
      return render_404 unless package_version

      package_version.metadata.readme = params[:package_version_description]

      begin
          client.update_package_version_ecodata(
            version_id: package_version.id,
            key: "readme",
            value:  package_version.metadata.readme,
            actor: current_user)

          flash[:notice] = "Package readme updated successfully."

          rescue PackageRegistry::Twirp::BaseError => error
            GitHub.logger.error(error)
            flash[:error] = "Could not edit description of package. Please try again."
            return redirect_to package_two_path
        end

      return redirect_to package_two_path
    end
  end

  def restore # rubocop:todo GitHub/UseRestfulActions

    begin
      name, original_name, ecosystem = params.require([:name, :original_name, :ecosystem])
      client.restore_package(namespace: owner.display_login, name: name, ecosystem: ecosystem, actor: current_user)

      if owner.organization?
        redirect_to settings_org_packages_path(
          organization_id: owner.name,
          page: current_page,
          restored_package: original_name,
          anchor: "deleted-packages"
        )
      else
        redirect_to settings_packages_path(
          page: current_page,
          restored_package: original_name,
          anchor: "packages"
        )
      end
    rescue PackageRegistry::Twirp::AlreadyExistsError => e
      GitHub.logger.error(e)
      flash[:packages_error] = "Couldn't restore this package due to conflicting package: #{ActionController::Base.helpers.link_to(original_name, packages_two_view_path(name: original_name))}"
      redirect_to :back
    rescue PackageRegistry::Twirp::InvalidArgumentError => e
      GitHub.logger.error(e)
      flash[:packages_error] = "Package restore was not successful. The package name #{owner.name}/#{original_name} has been retired and cannot restored."
      redirect_to :back
    rescue PackageRegistry::Twirp::BaseError, ActionController::ParameterMissing => e
      GitHub.logger.error(e)
      flash[:error] = "Couldn't restore this package."
      redirect_to :back
    end
  end

  def package_view_redirect # rubocop:todo GitHub/UseRestfulActions
    redirect_to packages_two_view_path(user_type: get_owner_type)
  end

  # TODO: This should become #show once it supports other ecosystems
  # https://gist.github.com/noahmatisoff/914d694d7f071831c6af77af444b74f8
  def package_view # rubocop:todo GitHub/UseRestfulActions
    package_download_counts = if @tagged_metadata.package && !GitHub.flipper[:package_download_counts_disabled].enabled?(current_user)
      client.get_package_total_download_counts(package_id: @tagged_metadata.package.id)
    else
      PackageRegistry::DownloadCounts::NULL
    end
    @rendering_metadata = @tagged_metadata
    @tagged_package_versions = @tagged_metadata.package_versions
    if @tagged_metadata.latest_version.nil?
      @rendering_metadata = @metadata
      @tagged_package_versions = nil
    end

    view = create_view_model(
      RegistryTwo::Packages::PackageView,
      owner: owner,
      metadata: @rendering_metadata,
      tagged_package_versions: @tagged_package_versions,
      repository: repository,
      package_download_counts: package_download_counts,
      viewer_is_admin: package_admin?,
      viewer_can_read_repo: current_user_can_read_repo?,
      user_type: params[:user_type] || get_owner_type,
      current_user: current_user
    )
    render "registry_two/packages/package", locals: { view: view }
  end

  def repo_dialog # rubocop:todo GitHub/UseRestfulActions
    render partial: "registry_two/packages/repo_dialog", locals: {
      package: @metadata.package,
      owner: owner,
      repositories: []
    }
  end

  def remove_repo # rubocop:todo GitHub/UseRestfulActions
    unless package_admin?
      error = "Must be an admin of the package to unlink a repo. Please try again."
      GitHub.logger.error(error)
      flash[:error] = error
      return redirect_to packages_two_view_path
    end

    begin
      client.remove_package_repo(
        ecosystem: package.package_type,
        namespace: package.namespace,
        name: package.name,
        actor: current_user,
        repo_id: UNLINK_REPO_ID
      )
    rescue PackageRegistry::Twirp::BaseError => error
      GitHub.logger.error(error)
      flash[:error] = "Could not unlink the repository from the package. Please try again."
      return redirect_to packages_two_view_path
    end

    redirect_to packages_two_view_path
  end

  def update_repo # rubocop:todo GitHub/UseRestfulActions
    unless package_admin?
      error = "Must be an admin of the package to associate a repo. Please try again."
      GitHub.logger.error(error)
      flash[:error] = error
      return redirect_to packages_two_view_path
    end

    unless update_repo_params[:repo_id].present? || update_repo_params[:repo_name].present?
      error = "Must select a repository to connect to."
      GitHub.logger.error(error)
      flash[:error] = error
      return redirect_to packages_two_view_path
    end

    # This should never happen unless the user is manually poking at our API or there is a severe programmer error.
    if update_repo_params[:repo_id].present? && update_repo_params[:repo_name].present?
      return head :bad_request
    end

    # Note that the above guards ensure that we either `repo_id` or `repo_name`, but never both.
    repository = if update_repo_params[:repo_id].present?
      Repository.find_by(id: update_repo_params[:repo_id])
    else
      # Since repo names are not globaly unique we need to scope to a owner.
      # The UI only allows searching for repositories that are owned by the owner of the package.
      # Including the `owner` here as `package.owner` ensures that we never
      # assign a repo not owned by the package owner.
      #
      # Note that the old `repo_id` based code path didn't even perform this check.
      # There a request can be formed that assigns a package to a repo owned
      # by someone other than the package owner,
      # if the current user has admin rights to both.
      Repository.find_by(owner: package.owner, name: update_repo_params[:repo_name])
    end

    # We re-use the "must be admin" message even if the repo does not exist at all.
    # This ensures we don't expose the existance of a repo if the user doesn't have access to it.
    unless repository && repository.adminable_by?(current_user)
      error = "Must be an admin of the repository to associate it to a package. Please try again."
      GitHub.logger.error(error)
      flash[:error] = error
      return redirect_to packages_two_view_path
    end

    begin
      client.update_package_repo(
        package_id: package.id.to_i,
        repo_id: repository.id
      )
    rescue PackageRegistry::Twirp::BaseError => error
      GitHub.logger.error(error)
      flash[:error] = "Could not associate the repository to the package. Please try again"
      return redirect_to packages_two_view_path
    end

    redirect_to packages_two_view_path
  end

  private

  def ensure_can_see_package_view
    if !GitHub.enterprise?
      ensure_supported_ecosystem
    else
      render_404 unless PackageRegistryHelper.ghes_registry_v2_enabled? && params[:ecosystem] == "container"
    end
  end

  def get_package_version
    client.get_package_version(
      ecosystem: params[:ecosystem],
      actor: current_user,
      namespace: owner.display_login,
      name: params[:name],
      version_id: params[:version].to_i
    )
  end

  def redirect_latest
    GitHub.logger.info(
      "code.function" =>  __method__,
      "code.namespace" => self.class.name,
      "gh.registry.version" => params[:version].to_i
    )
    if params[:version].to_i == 0
      GitHub.logger.info(
        "code.function" => __method__,
        "code.namespace" => self.class.name,
        "gh.registry.no_versions" => @metadata.package_versions.blank?,
      )
      return render_404 if @metadata.package_versions.blank?
      GitHub.logger.info(
        "code.function" => __method__,
        "code.namespace" => self.class.name,
        "gh.registry.latest_version_id" => @metadata.package_versions.first.id
      )
      if package.repository.blank?
        redirect_to package_two_path(version: @metadata.package_versions.first.id, user_type: params[:user_type] || get_owner_type)
      else
        redirect_to repo_package_two_path(version: @metadata.package_versions.first.id)
      end
    end
  end

  def repository
    # If we go via packages_view then we won't be having the metadata object initialized since we aren't making the unfiltered call
    # Instead we'll have the metadata stored in the @tagged_metadata which is fetched via an API call made with filter of "tagged"
    repo = if !@metadata.nil?
      @metadata.package.repository
    else
      @tagged_metadata.package.repository
    end
    if repo && !repo.deleted? && (repo.public? || repo.readable_by?(current_user))
      repo
    end
  end

  def update_repo_params
    params.require(:update_repo).permit(:package_id, :repo_id, :repo_name)
  end
end
