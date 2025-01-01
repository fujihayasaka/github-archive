# typed: true
# frozen_string_literal: true

class RegistryTwo::Controller < ApplicationController
  include CurrentRepositoryInteractionsHelper
  include RegistryTwo::MembersHelper

  before_action :ensure_owner_exists

  rescue_from PackageRegistry::Twirp::ServiceUnavailableError do |_error|
    render "registry_two/packages/service_unavailable"
  end

  LEGACY_ECOSYSTEMS = %w(
    docker
  )

  protected

  DEFAULT_TAGGED_FILTER_VALUE = "tagged"

  # For legacy packages, redirect to the repository-scoped package path.
  def redirect_legacy_packages
    GitHub.logger.info(
      "code.function" => __method__,
      "code.namespace" => self.class.name,
      "gh.registry.ecosystem" => params[:ecosystem]
    )
    if LEGACY_ECOSYSTEMS.include?(params[:ecosystem])
      redirect_to package_path(owner, package.repository, package.id)
    end
  end

  def ensure_supported_ecosystem
    GitHub.logger.info(
      "code.function" => __method__,
      "code.namespace" => self.class.name,
      "gh.registry.ecosystem" => params[:ecosystem]
    )
    render_404 unless SUPPORTED_V2_ECOSYSTEMS.include?(params[:ecosystem])
  end

  def ensure_package
    render_404 unless package
  end

  def ensure_package_admin
    unless logged_in?
      return redirect_to :back
    end

    response = ::Permissions::Enforcer.authorize(
      action: :admin_package,
      actor: current_user,
      subject: package,
      context: {
        "subject.owner.id" => package.owner.id,
        "subject.author.id" => package.author_id,
       },
    )
    unless response.allow?
      flash[:error] = "You do not have permissions to administrate this package."
      redirect_to :back
    end
  end

  def write_access_response
    ::Permissions::Enforcer.authorize(
      action: :write_package,
      actor: current_user,
      subject: package,
      context: {
        "subject.owner.id" => package.owner.id,
        "subject.author.id" => package.author_id,
       },
    )
  end

  def write_access?
    write_access_response.allow?
  end

  # Allow V2 UI access for container (GHES and non-GHES) and npm, nuget, rubygems ecosystems (non-GHES)
  def ensure_v2_ui_enabled
    # Container, npm, rubygems and nuget ecosystem
    if %w[container npm nuget rubygems].include?(params[:ecosystem])
      return true if !GitHub.enterprise? || PackageRegistryHelper.ghes_registry_v2_enabled?
    end

    v2_enabled = PackageRegistryHelper.registry_v2_ui_enabled?(params[:ecosystem], owner)
    GitHub.logger.info(
      "code.function" => __method__,
      "code.namespace" => self.class.name,
      "gh.registry.ecosystem" => params[:ecosystem],
      "gh.registry.v2_enabled" => v2_enabled,
    )
    return true if !GitHub.enterprise? && v2_enabled

    render_404
  end

  def client # rubocop:todo GitHub/ControllersShouldUseMemoizeForMemoization
    @client ||= PackageRegistry::Twirp.metadata_client
  end

  def show_reclaimed_storage?
    GitHub.flipper[:container_registry_billing].enabled?(owner) && package.visibility != "public"
  end

  def billable_namespaces
    if owner.try(:delegate_billing_to_business?)
      owner.business.organizations.map { |o| o.name }
    else
      [owner.name]
    end
  end

  memoize def owner
    User.find_by_login(params[:user_id])
  end

  def ensure_owner_exists
    render_404 unless owner.present?
  end

  def target_for_conditional_access
    return :no_target_for_conditional_access unless owner # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
    owner
  end

  def get_metadata
    begin
      GitHub.logger.info(
        "code.function" => __method__,
        "code.namespace" => self.class.name,
        "gh.registry.ecosystem" => params[:ecosystem],
        "gh.registry.display_login" => owner.display_login,
        "gh.registry.owner_id" => current_user&.id
      )
      @metadata = client.get_package_metadata(
        ecosystem: params[:ecosystem],
        namespace: owner.display_login,
        name: params[:name],
        actor: current_user,
        version_limit: DEFAULT_PACKAGE_VERSIONS_LIMIT,
        include_download_count: true
      )
      GitHub.logger.info(
        "code.function" => __method__,
        "code.namespace" => self.class.name,
        "gh.registry.metadata" => @metadata
      )
      render_404 unless @metadata
    rescue PackageRegistry::Twirp::ServiceUnavailableError => e
      GitHub.logger.error(e)
      render "registry_two/packages/service_unavailable"
    rescue PackageRegistry::Twirp::BaseError => e
      GitHub.logger.error(e)
      render_404
    end
  end

  def get_tagged_metadata
    begin
      GitHub.logger.info(
        "code.function" => __method__,
        "code.namespace" => self.class.name,
        "gh.registry.owner_id" => current_user&.id,
        "gh.registry.ecosystem" => params[:ecosystem],
        "gh.registry.namespace" => owner.login, # rubocop:disable GitHub/DoNotAllowLogin login is expected in logs,
        "gh.registry.display_login" => owner.display_login,
        "gh.registry.user_name" => params[:name]

      )
      @tagged_metadata = client.get_package_metadata(
        ecosystem: params[:ecosystem],
        namespace: owner.display_login,
        name: params[:name],
        actor: current_user,
        version_filter: DEFAULT_TAGGED_FILTER_VALUE,
        version_limit: DEFAULT_TAGGED_PACKAGE_VERSIONS_LIMIT,
        include_download_count: true
      )
      GitHub.logger.info(
        "code.function" => __method__,
        "code.namespace" => self.class.name,
        "gh.registry.metadata" => @tagged_metadata
      )
      render_404 unless @tagged_metadata
    rescue PackageRegistry::Twirp::ServiceUnavailableError => e
      GitHub.logger.error(e)
      render "registry_two/packages/service_unavailable"
    rescue PackageRegistry::Twirp::BaseError => e
      GitHub.logger.error(e)
      render_404
    end
  end

  def package_admin?
    package_admin_response.allow?
  end

  def get_owner_type
    owner.organization? ? "orgs" : "users"
  end

  private

  helper_method :subscription_status, :current_user_can_read_repo?, :reclaimed_storage

  # cap_bypass:to_fix - Not sure if this is a bypass or not - where is current_repository used?
  # Do we need to check CAP policies on the current repo before returning?
  def current_repository # rubocop:todo GitHub/ControllersShouldUseMemoizeForMemoization
    # no point in looking up a repo without a package
    # this is helpful for redirects
    return nil unless params[:name]

    if !defined?(@current_repository) && package
      @current_repository = package.repository
    end

    # if the user can't read the repo, then we never want to return it
    return nil if @current_repository && !@current_repository&.readable_by?(current_user)

    @current_repository
  end

  def subscription_status
    return nil unless logged_in? && current_repository
    @subscription_status ||= GitHub.newsies.subscription_status(current_user, current_repository)
  end

  def reclaimed_storage(version = nil)
    return 0 unless show_reclaimed_storage?
    version ||= ""
    resp = client.get_reclaimed_storage(
      namespace: owner.display_login,
      name: params[:name],
      ecosystem: params[:ecosystem],
      billing_entity_namespaces: billable_namespaces,
      version: version
    )
    resp.reclaimed_storage_bytes
  end

  def package_admin_response
    ::Permissions::Enforcer.authorize(
      action: :admin_package,
      actor: current_user,
      subject: package,
      context: {
          "subject.owner.id" => package.owner.id,
          "subject.author.id" => package.author_id,
      },
    )
  end

  def repo_scoped_redirect(redirect_func)
    if package.repository.present? && !params[:repository] && !package.repository.deleted? && current_user_can_read_repo?
      # Package has repo linked, but is not on a repo scoped URL
      redirect_to method(redirect_func).call({ repository: package.repository.name,
                                               tag: params[:tag],
                                               filters: params[:filters]&.permit!,
                                               page: params[:page]
                                             }.compact_blank)
    elsif params[:repository] && (package.repository.blank? || !current_user_can_read_repo?)
      # In a repo scoped URL, but package not associated with repo.
      # Or, the user doesn't have read access to the repo even if it's linked to the package.
      render_404
    end
  end

  def set_default_nav_breadcrumb
    return unless header_redesign_enabled?

    if current_repository && current_user_can_read_repo?
      object = current_repository
    else
      object = owner
    end

    if object
      set_nav_breadcrumb ContextRegion::Factory.build(object, current_user: current_user)
    end
  end

  def spammy_behaviour_check
    render_404 if !PackageRegistryHelper.allow_access_to_actor?(owner, current_user)
  end
end
