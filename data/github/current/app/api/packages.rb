# typed: false
# frozen_string_literal: true

class Api::Packages < Api::App
  include ReceiveSchemaWithOpenApi
  include Registry::QueryHelper
  include GitHub::Encoding
  MAX_ES_PACKAGES_RESULT = 10000

  # These endpoints have disable_conditional_access_policies set because CAP enforcement is done elsewhere
  # See https://github.com/github/github/pull/173456#issuecomment-799394674 for context

  get "/packages/container-registry-url", operation_id: "packages/get-container-registry-url" do
    control_access :public_site_information,
      resource: Platform::PublicResource.new, # rubocop:disable GitHub/PublicResource
      allow_integrations: true,
      allow_user_via_granular_actor: true

    deliver_raw url: GitHub.urls.registry_url(:containers)
  end

  # Get package for the current authenticated user.
  get "/user/packages/:package_type/:package", operation_id: "packages/get-package-for-authenticated-user" do
    set_forbidden_message "You need at least read:packages scope to get a package."
    control_access :authenticated_user,
      resource: current_user,
      challenge: true,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      # cap enforcement is done in the individual methods called (ie: get_package)
      disable_conditional_access_policies: true # rubocop:disable GitHub/DoNotSkipCapAccessAllowed

    get_package(package_owner(current_user))
  end

  # Get package for an organization.
  get "/organizations/:organization_id/packages/:package_type/:package", operation_id: "packages/get-package-for-organization" do
    org = find_org!

    set_forbidden_message "You need at least read:packages scope to get a package."
    control_access :authenticated_user,
      resource: org,
      challenge: true,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      # cap enforcement is done in the individual methods called (ie: get_package)
      disable_conditional_access_policies: true # rubocop:disable GitHub/DoNotSkipCapAccessAllowed

    get_package(org)
  end

  # Get user package
  get "/user/:user_id/packages/:package_type/:package", operation_id: "packages/get-package-for-user" do
    user = find_user!

    set_forbidden_message "You need at least read:packages scope to get a package."
    control_access :authenticated_user,
      resource: user,
      challenge: true,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      # cap enforcement is done in the individual methods called (ie: get_package)
      disable_conditional_access_policies: true # rubocop:disable GitHub/DoNotSkipCapAccessAllowed

    get_package(user)
  end

  # List packages for the current authenticated user.
  get "/user/packages", operation_id: "packages/list-packages-for-authenticated-user" do
    set_forbidden_message "You need at least read:packages scope to list packages."
    control_access :authenticated_user,
      resource: current_user,
      challenge: true,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      # cap enforcement is done in the individual methods called (ie: list_packages)
      disable_conditional_access_policies: true # rubocop:disable GitHub/DoNotSkipCapAccessAllowed

    list_packages(package_owner(current_user))
  end

  # List packages for a user.
  get "/user/:user_id/packages", operation_id: "packages/list-packages-for-user" do
    user = find_user!

    set_forbidden_message "You need at least read:packages scope to list packages."
    control_access :authenticated_user,
      resource: user,
      challenge: true,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      # cap enforcement is done in the individual methods called (ie: list_packages)
      disable_conditional_access_policies: true # rubocop:disable GitHub/DoNotSkipCapAccessAllowed

    list_packages(user)
  end

  # List packages for an organization.
  get "/organizations/:organization_id/packages", operation_id: "packages/list-packages-for-organization" do
    org = find_org!

    set_forbidden_message "You need at least read:packages scope to list packages."

    if org.business&.feature_enabled?(:saml_scope_private_resources_to_org)
      resource = Platform::InternalResource.new(resource: org)
    else
      resource = org
    end

    control_access :authenticated_user,
      resource: resource,
      challenge: true,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      # cap enforcement is done in the individual methods called (ie: list_packages)
      disable_conditional_access_policies: true # rubocop:disable GitHub/DoNotSkipCapAccessAllowed

    list_packages(resource)
  end

  # List packages that conflict during docker migration for the current authenticated user.
  get "/user/docker/conflicts", operation_id: "packages/list-docker-migration-conflicting-packages-for-authenticated-user" do
    control_access :authenticated_user,
      resource: current_user,
      challenge: true,
      allow_integrations: false,
      allow_user_via_granular_actor: true,
      # cap enforcement is done in the individual methods called (ie: list_docker_migration_conflicting_packages)
      disable_conditional_access_policies: true # rubocop:disable GitHub/DoNotSkipCapAccessAllowed

    list_docker_migration_conflicting_packages(current_user)
  end

  # List packages that conflict during docker migration for a user.
  get "/user/:user_id/docker/conflicts", operation_id: "packages/list-docker-migration-conflicting-packages-for-user" do
    control_access :authenticated_user,
      resource: current_user,
      challenge: true,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      # cap enforcement is done in the individual methods called (ie: list_docker_migration_conflicting_packages)
      disable_conditional_access_policies: true # rubocop:disable GitHub/DoNotSkipCapAccessAllowed

    user = find_user!
    list_docker_migration_conflicting_packages(user)
  end

  # List packages that conflict during docker migration for an organization.
  get "/organizations/:organization_id/docker/conflicts", operation_id: "packages/list-docker-migration-conflicting-packages-for-organization" do
    control_access :authenticated_user,
      resource: current_user,
      challenge: true,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      # cap enforcement is done in the individual methods called (ie: list_docker_migration_conflicting_packages)
      disable_conditional_access_policies: true # rubocop:disable GitHub/DoNotSkipCapAccessAllowed

    org = find_org!
    list_docker_migration_conflicting_packages(org)
  end

  # Delete package for the authenticated user
  delete "/user/packages/:package_type/:package", operation_id: "packages/delete-package-for-authenticated-user" do
    set_forbidden_message "You need at least delete:packages and read:packages scopes to delete a package."
    control_access :authenticated_user,
      resource: current_user,
      challenge: true,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      # cap enforcement is done in the individual methods called (ie: delete_package)
      disable_conditional_access_policies: true # rubocop:disable GitHub/DoNotSkipCapAccessAllowed

    receive_with_schema("package", "delete-current-user")
    delete_package(package_owner(current_user))
  end

  # Delete package for a user
  delete "/user/:user_id/packages/:package_type/:package", operation_id: "packages/delete-package-for-user" do
    user = find_user!

    set_forbidden_message "You need at least delete:packages and read:packages scopes to delete a package."
    control_access :authenticated_user,
      resource: user,
      challenge: true,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      # cap enforcement is done in the individual methods called (ie: delete_package)
      disable_conditional_access_policies: true # rubocop:disable GitHub/DoNotSkipCapAccessAllowed

    receive_with_schema("package", "delete-user")
    delete_package(user)
  end

  # Delete package for an organization
  delete "/organizations/:organization_id/packages/:package_type/:package", operation_id: "packages/delete-package-for-org" do
    org = find_org!

    set_forbidden_message "You need at least delete:packages and read:packages scopes to delete a package."
    control_access :authenticated_user,
      resource: org,
      challenge: true,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      # cap enforcement is done in the individual methods called (ie: delete_package)
      disable_conditional_access_policies: true # rubocop:disable GitHub/DoNotSkipCapAccessAllowed

    receive_with_schema("package", "delete-org")
    delete_package(org)
  end

  # List package versions for the authenticated user
  get "/user/packages/:package_type/:package/versions", operation_id: "packages/get-all-package-versions-for-package-owned-by-authenticated-user" do
    set_forbidden_message "You need at least read:packages scope to get a package's versions."
    control_access :authenticated_user,
      resource: current_user,
      challenge: true,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      # cap enforcement is done in the individual methods called (ie: list_package_versions)
      disable_conditional_access_policies: true # rubocop:disable GitHub/DoNotSkipCapAccessAllowed

    list_package_versions(package_owner(current_user))
  end

  # List package versions for an organization
  get "/organizations/:organization_id/packages/:package_type/:package/versions", operation_id: "packages/get-all-package-versions-for-package-owned-by-org" do
    org = find_org!

    if org.business&.feature_enabled?(:saml_scope_private_resources_to_org)
      resource = Platform::InternalResource.new(resource: org)
    else
      resource = org
    end

    set_forbidden_message "You need at least read:packages scope to get a package's versions."
    control_access :authenticated_user,
      resource: resource,
      challenge: true,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      # cap enforcement is done in the individual methods called (ie: list_package_versions)
      disable_conditional_access_policies: true # rubocop:disable GitHub/DoNotSkipCapAccessAllowed

    list_package_versions(org)
  end

  # List other user's public package versions
  get "/user/:user_id/packages/:package_type/:package/versions", operation_id: "packages/get-all-package-versions-for-package-owned-by-user" do
    user = find_user!

    set_forbidden_message "You need at least read:packages scope to get a package's versions."
    control_access :authenticated_user,
      resource: user,
      challenge: true,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      # cap enforcement is done in the individual methods called (ie: list_package_versions)
      disable_conditional_access_policies: true # rubocop:disable GitHub/DoNotSkipCapAccessAllowed

    list_package_versions(user)
  end

  # Get package version for the authenticated user
  get "/user/packages/:package_type/:package/versions/:version_id", operation_id: "packages/get-package-version-for-authenticated-user" do
    set_forbidden_message "You need at least read:packages scope to view a package's versions."
    control_access :authenticated_user,
      resource: current_user,
      challenge: true,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      # cap enforcement is done in the individual methods called (ie: get_package_version)
      disable_conditional_access_policies: true # rubocop:disable GitHub/DoNotSkipCapAccessAllowed

    get_package_version(package_owner(current_user))
  end

  # Get package version for a user
  get "/user/:user_id/packages/:package_type/:package/versions/:version_id", operation_id: "packages/get-package-version-for-user" do
    user = find_user!

    set_forbidden_message "You need at least read:packages scope to view a package's versions."
    control_access :authenticated_user,
      resource: user,
      challenge: true,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      # cap enforcement is done in the individual methods called (ie: get_package_version)
      disable_conditional_access_policies: true # rubocop:disable GitHub/DoNotSkipCapAccessAllowed

    get_package_version(user)
  end

  # Get package version for an organization
  get "/organizations/:organization_id/packages/:package_type/:package/versions/:version_id", operation_id: "packages/get-package-version-for-organization" do
    org = find_org!

    set_forbidden_message "You need at least read:packages scope to view a package's versions."
    control_access :authenticated_user,
      resource: org,
      challenge: true,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      # cap enforcement is done in the individual methods called (ie: get_package_version)
      disable_conditional_access_policies: true # rubocop:disable GitHub/DoNotSkipCapAccessAllowed

    get_package_version(org)
  end

  # Delete package version for the authenticated user
  delete "/user/packages/:package_type/:package/versions/:version_id", operation_id: "packages/delete-package-version-for-authenticated-user" do
    set_forbidden_message "You need at least delete:packages and read:packages scopes to delete a package version."
    control_access :authenticated_user,
      resource: current_user,
      challenge: true,
      allow_integrations: true,
      allow_user_via_granular_actor: false,
      # cap enforcement is done in the individual methods called (ie: delete_package_version)
      disable_conditional_access_policies: true # rubocop:disable GitHub/DoNotSkipCapAccessAllowed

    receive_with_schema("package-version", "delete-current-user")
    delete_package_version(package_owner(current_user))
  end

  # Delete package version for a user
  delete "/user/:user_id/packages/:package_type/:package/versions/:version_id", operation_id: "packages/delete-package-version-for-user" do
    user = find_user!

    set_forbidden_message "You need at least delete:packages and read:packages scopes to delete a package version."
    control_access :authenticated_user,
      resource: user,
      challenge: true,
      allow_integrations: true,
      allow_user_via_granular_actor: false,
      # cap enforcement is done in the individual methods called (ie: delete_package_version)
      disable_conditional_access_policies: true # rubocop:disable GitHub/DoNotSkipCapAccessAllowed

    receive_with_schema("package-version", "delete-user")
    delete_package_version(user)
  end

  # Delete package version for an organization.
  delete "/organizations/:organization_id/packages/:package_type/:package/versions/:version_id", operation_id: "packages/delete-package-version-for-org" do
    org = find_org!

    set_forbidden_message "You need at least delete:packages and read:packages scopes to delete a package version."
    control_access :authenticated_user,
      resource: org,
      challenge: true,
      allow_integrations: true,
      allow_user_via_granular_actor: false,
      # cap enforcement is done in the individual methods called (ie: delete_package_version)
      disable_conditional_access_policies: true # rubocop:disable GitHub/DoNotSkipCapAccessAllowed

    receive_with_schema("package-version", "delete-org")
    delete_package_version(org)
  end

  # Restore package for the authenticated user
  post "/user/packages/:package_type/:package/restore", operation_id: "packages/restore-package-for-authenticated-user" do
    set_forbidden_message "You need at least write:packages and read:packages scopes to restore a package."
    control_access :authenticated_user,
      resource: current_user,
      challenge: true,
      allow_integrations: true,
      allow_user_via_granular_actor: false,
      # cap enforcement is done in the individual methods called (ie: restore_package)
      disable_conditional_access_policies: true # rubocop:disable GitHub/DoNotSkipCapAccessAllowed

    receive_with_schema("package", "restore-current-user")
    restore_package(package_owner(current_user))
  end

  # Restore package for a user
  post "/user/:user_id/packages/:package_type/:package/restore", operation_id: "packages/restore-package-for-user" do
    user = find_user!

    set_forbidden_message "You need at least write:packages and read:packages scopes to restore a package."
    control_access :authenticated_user,
      resource: user,
      challenge: true,
      allow_integrations: true,
      allow_user_via_granular_actor: false,
      # cap enforcement is done in the individual methods called (ie: restore_package)
      disable_conditional_access_policies: true # rubocop:disable GitHub/DoNotSkipCapAccessAllowed

    receive_with_schema("package", "restore-user")
    restore_package(user)
  end

  # Restore package for an organization
  post "/organizations/:organization_id/packages/:package_type/:package/restore", operation_id: "packages/restore-package-for-org" do
    org = find_org!

    set_forbidden_message "You need at least write:packages and read:packages scopes to restore a package."
    control_access :authenticated_user,
      resource: org,
      challenge: true,
      allow_integrations: true,
      allow_user_via_granular_actor: false,
      # cap enforcement is done in the individual methods called (ie: restore_package)
      disable_conditional_access_policies: true # rubocop:disable GitHub/DoNotSkipCapAccessAllowed

    receive_with_schema("package", "restore-org")
    restore_package(org)
  end

  # Restore package version for the authenticated user
  post "/user/packages/:package_type/:package/versions/:version_id/restore", operation_id: "packages/restore-package-version-for-authenticated-user" do
    set_forbidden_message "You need at least write:packages and read:packages scopes to restore a package version."
    control_access :authenticated_user,
      resource: current_user,
      challenge: true,
      allow_integrations: true,
      allow_user_via_granular_actor: false,
      # cap enforcement is done in the individual methods called (ie: restore_package_version)
      disable_conditional_access_policies: true # rubocop:disable GitHub/DoNotSkipCapAccessAllowed

    receive_with_schema("package-version", "restore-current-user")
    restore_package_version(package_owner(current_user))
  end

  # Restore package version for a user
  post "/user/:user_id/packages/:package_type/:package/versions/:version_id/restore", operation_id: "packages/restore-package-version-for-user" do
    user = find_user!

    set_forbidden_message "You need at least write:packages and read:packages scopes to restore a package version."
    control_access :authenticated_user,
      resource: user,
      challenge: true,
      allow_integrations: true,
      allow_user_via_granular_actor: false,
      # cap enforcement is done in the individual methods called (ie: restore_package_version)
      disable_conditional_access_policies: true # rubocop:disable GitHub/DoNotSkipCapAccessAllowed

    receive_with_schema("package-version", "restore-user")
    restore_package_version(user)
  end

  # Restore package version for an organization
  post "/organizations/:organization_id/packages/:package_type/:package/versions/:version_id/restore", operation_id: "packages/restore-package-version-for-org" do
    org = find_org!

    set_forbidden_message "You need at least write:packages and read:packages scopes to restore a package version."
    control_access :authenticated_user,
      resource: org,
      challenge: true,
      allow_integrations: true,
      allow_user_via_granular_actor: false,
      # cap enforcement is done in the individual methods called (ie: restore_package_version)
      disable_conditional_access_policies: true # rubocop:disable GitHub/DoNotSkipCapAccessAllowed

    receive_with_schema("package-version", "restore-org")
    restore_package_version(org)
  end

  private

  def get_package(owner)
    deliver_error!(404,
      message: "GitHub Packages has not been enabled. Contact your Enterprise Administrator to enable GitHub Packages.",
    ) if GitHub.enterprise? && !GitHub.registry_enabled_for_enterprise?

    deliver_error!(404,
      message: "Not Found",
    ) if !PackageRegistryHelper.allow_access_to_actor?(owner, current_user)

    package_type = string_param!(key: :package_type)
    package_name = string_param!(key: :package)

    if Registry::Package::PUBLICLY_SUPPORTED_TYPES.include?(package_type.to_sym)
      # v1 package
      package = owner.packages.find_by(name: package_name, package_type: package_type)

      if package.nil?
        if Registry::Package.publicly_supported_migrated_types(owner).include?(package_type.to_sym)
          return get_v2_package(owner, package_type, package_name)
        else
          deliver_error!(404,
            message: "Package not found.",
          )
        end
      end

      if package.migrated?
        if package_type.to_sym == :docker
          package_name = "#{package.repository.name}/#{package_name}"
          package_type = "container"
        end
        return get_v2_package(owner, package_type, package_name)
      end

      # package access is tied to the repository
      control_access :get_package,
        repo: package.repository,
        resource: package,
        challenge: true,
        allow_integrations: true,
        allow_user_via_granular_actor: true

      deliver :package_hash, PackageV1Adapter.new(package)
    elsif PackageRegistry::Package::PUBLICLY_SUPPORTED_TYPES.include?(package_type.to_sym) || actions_package_type_included?(package_type.to_sym)
      # v2 package

      get_v2_package(owner, package_type, package_name)
    else
      deliver_error!(422,
        message: "The package_type parameter is invalid.",
      )
    end
  end

  def get_v2_package(owner, package_type, package_name)
    begin
      resp = v2_client.get_package_metadata(namespace: owner.display_login, name: package_name, ecosystem: package_type.to_sym, actor: current_user, version_limit: 1, search_action_packages_enabled: search_action_packages_enabled?)

      deliver_error!(404,
        message: "Package not found.",
      ) if resp&.package.nil?

      package = resp&.package

      control_access :get_package_v2,
        resource: package,
        challenge: true,
        allow_integrations: true,
        allow_user_via_granular_actor: false

    rescue PackageRegistry::Twirp::PermissionDeniedError
      deliver_error!(404,
        message: "Package not found.",
      )
    rescue PackageRegistry::Twirp::Error => e
      GitHub.logger.error(e)
      deliver_error!(500,
        message: "Internal server error.",
      )
    end

    deliver :package_hash, PackageV2Adapter.new(resp)
  end

  def list_packages(owner)
    deliver_error!(404,
      message: "GitHub Packages has not been enabled. Contact your Enterprise Administrator to enable GitHub Packages.",
    ) if GitHub.enterprise? && !GitHub.registry_enabled_for_enterprise?

    deliver_error!(404,
      message: "Not Found",
    ) if !PackageRegistryHelper.allow_access_to_actor?(owner, current_user)

    package_type = string_param!(key: :package_type)
    visibility = string_visibility_param!(key: :visibility, halt_on_invalid: true)

    # TODO: return org's public packages if the user is not authenticated, see https://github.com/github/c2c-package-registry/issues/3282

    if Registry::Package::PUBLICLY_SUPPORTED_TYPES.include?(package_type.to_sym)
      # This says v2 but it actually just checks that the user has the proper read:packages scope on their PAT.
      control_access :get_package_v2,
        resource: owner,
        challenge: true,
        allow_integrations: true,
        allow_user_via_granular_actor: false

      if Registry::Package.publicly_supported_migrated_types(owner).include?(package_type.to_sym)
        return list_v1_v2_packages(owner, package_type, visibility)
      end

      collection = if use_list_packages_candidate?(owner)
        list_packages_candidate(owner, package_type, visibility)
      else
        science "list_packages_no_join" do |e|
          e.try { list_packages_candidate(owner, package_type, visibility) }
          e.use { list_packages_control(owner, package_type, visibility) }
          e.compare_ordered_records
        end
      end

      deliver :package_hash, collection
    elsif PackageRegistry::Package::PUBLICLY_SUPPORTED_TYPES.include?(package_type.to_sym) || actions_package_type_included?(package_type.to_sym)

      list_v2_packages(owner, package_type, visibility)
    else
      deliver_error!(422,
        message: "The package_type parameter is invalid.",
      )
    end
  end

  def use_list_packages_candidate?(owner)
    (owner.is_a?(User) || owner.is_a?(Organization) && owner.feature_enabled?(:list_packages_no_join_candidate)) ||
      FeatureFlag.vexi.enabled?(:list_packages_no_join_candidate, default: false)
  end

  def list_packages_control(owner, package_type, visibility)
    # V1 package visibility is based on whether the user can access the package's parent repository
    # Retrieve a list of IDs of repositories this user can read, then get all the packages for those repos
    readable_repos = current_user.associated_repository_ids(repository_ids: owner.repositories.pluck(:id))
    readable_packages = Registry::Package.where(repository_id: readable_repos, package_type: package_type).not_deleted

    public_packages = Registry::Package.where(owner: owner, package_type: package_type).not_deleted.public_scope

    # Scope to requested visibility if any
    case visibility&.to_sym
    when :public
      v1_packages = public_packages
    when :private, :internal
      v1_packages = readable_packages.private_scope
    else
      v1_packages = public_packages.or(readable_packages)
    end

    v1_packages = v1_packages.joins(:package_versions).unmigrated if package_type.to_sym == :docker

    PackageV1Adapter.collection(v1_packages.order(created_at: :asc)).paginate(pagination)
  end

  def list_packages_candidate(owner, package_type, visibility)
    case visibility&.to_sym
    when :public
      v1_packages = public_packages(owner, package_type)
    when :private, :internal
      v1_packages = Registry::Package.where(repository_id: private_readable_repo_ids(owner), package_type: package_type).not_deleted
    else
      v1_packages = public_packages(owner, package_type).or(Registry::Package.where(repository_id: private_readable_repo_ids(owner), package_type: package_type).not_deleted)
    end

    v1_packages = v1_packages.joins(:package_versions).unmigrated if package_type.to_sym == :docker

    PackageV1Adapter.collection(v1_packages.order(created_at: :asc)).paginate(pagination)
  end

  def public_packages(owner, package_type)
    public_repo_ids_by_owner = Repositories.domain.repo_ids_by_owners(owner_ids: [owner.id], active_only: true, visibility: Repositories::RepositoryVisibility::Public)
    Registry::Package.where(owner: owner, package_type: package_type).where(repository_id: public_repo_ids_by_owner).not_deleted
  end

  def private_readable_repo_ids(owner)
    private_repo_ids_by_owner = Repositories.domain.repo_ids_by_owners(owner_ids: [owner.id], active_only: true, visibility: Repositories::RepositoryVisibility::Private)
    current_user.associated_repository_ids(repository_ids: private_repo_ids_by_owner)
  end

  def list_v2_packages(owner, package_type, visibility)
    begin
      per_page = pagination[:per_page].present? ? pagination[:per_page].to_i : 30  # default to 30, cap at 100
      per_page = 100 if per_page > 100
      page = pagination[:page].to_i || 0
      offset = page != 0 ? (page - 1) * per_page : 0
      will_paginate = !pagination[:per_page].to_i.zero?

      if (offset + per_page) > MAX_ES_PACKAGES_RESULT
        deliver_error!(400,
          message: "The per_page and page parameters are invalid. The value of per_page multipled by page cannot be greater than 10000.",
        )
      end

      # v2 does not yet support GITHUB_TOKEN or GitHub App Tokens
      # https://github.com/github/c2c-package-registry/issues/2594
      control_access :get_package_v2,
        resource: owner,
        challenge: true,
        allow_integrations: true,
        allow_user_via_granular_actor: false

      # If the queried namespace is an organization that the acting user is a member of, include all internal packages for that org.
      internal_namespaces = [owner.display_login] if owner.readable_by?(current_user)

      # Private repository IDs that this user can read within this namespace
      readable_repo_ids = current_user.associated_repository_ids(repository_ids: owner.repositories.private_scope.pluck(:id))

      # The final list of packages that comes back is originally sourced from Elasticsearch but each is passed through
      # an authzd check to be sure we are only giving back packages users should be able to access.
      result = v2_client.get_package_listing(ecosystem: package_type.to_sym,
        actor: current_user,
        namespace: owner.display_login,
        internal_namespaces: internal_namespaces,
        visibility: visibility,
        readable_repo_ids: readable_repo_ids,
        limit: per_page,
        offset: offset,
        search_action_packages_enabled: search_action_packages_enabled?
      )

      build_pagination_links(per_page, page, result[:total_packages]) if will_paginate
    rescue PackageRegistry::Twirp::PermissionDeniedError
      deliver_error!(404,
        message: "Package not found.",
      )
    rescue PackageRegistry::Twirp::InvalidArgumentError => e
      GitHub.logger.error(e)
      deliver_error!(400,
        message: "Invalid argument.",
      )
    rescue PackageRegistry::Twirp::Error => e
      GitHub.logger.error(e)
      deliver_error!(500,
        message: "Internal server error.",
      )
    end

    deliver :package_hash, PackageV2Adapter.collection(result[:packages])
  end

  def list_v1_v2_packages(owner, package_type, visibility)
    begin
      per_page = pagination[:per_page].present? ? pagination[:per_page].to_i : 30  # default to 30, cap at 100
      per_page = 100 if per_page > 100
      page = pagination[:page].to_i || 1
      will_paginate = !pagination[:per_page].to_i.zero?

      # TODO : for v2 packages how to get packages if we pass repo_ids in query & v2 package not associated with repo

      packages, _, total_unfiltered_count = packages_for_query(
        current_user: current_user,
        user_session: nil,
        owner: owner,
        repo_id: nil,
        query: nil,
        package_type: package_type,
        visibility: visibility,
        sort: nil,
        page: page,
        per_page: per_page,
        use_cached_versions: true,
        include_version_count: true,
      )
      ar_packages = []
      rms_packages = []
      packages.map do |package|
        package.class.to_s == "PackageRegistry::PackageMetadata" ? rms_packages.push(package) : ar_packages.push(package)
      end
      build_pagination_links(per_page, page, total_unfiltered_count) if will_paginate
      v1_packages = deliver :package_hash, PackageV1Adapter.collection(ar_packages)
      v2_packages = deliver :package_hash, PackageV2Adapter.collection(rms_packages)
      if rms_packages.empty?
        v1_packages
      elsif ar_packages.empty?
        v2_packages
      else
        v1_packages = v1_packages.to_s.strip
        v1_packages = v1_packages[0..-2]
        v1_packages += ","
        v1_packages + v2_packages[1..-1]
      end
    end
  end

  def list_docker_migration_conflicting_packages(owner)
    deliver_error!(400,
      message: "Package migration for docker is no longer supported. Please contact support for assistance.",
    ) if owner.feature_enabled?(:packages_disable_docker_v1) && !owner.feature_enabled?(:packages_enable_docker_v1)

    deliver_error!(404,
      message: "GitHub Packages has not been enabled. Contact your Enterprise Administrator to enable GitHub Packages.",
    ) if GitHub.enterprise? && !GitHub.registry_enabled_for_enterprise?

    deliver_error!(404,
      message: "Not Found",
    ) if !PackageRegistryHelper.allow_access_to_actor?(owner, current_user)

    # v1 packages which are not migrated to v2
    v1_packages = Registry::Package.migratable("docker")&.where(owner_id: owner.id)
    pkg_names = v1_packages.map { |pkg| pkg.repository&.name + "/" + pkg.name }

    # if there are no packages to migrate, return an empty array
    return deliver :package_hash, PackageV2Adapter.collection([]) if pkg_names.empty?

    begin
      packages = v2_client.get_packages_by_names(
        namespace: owner.display_login,
        package_names: pkg_names,
        ecosystem: "container",
        actor: current_user,
      )
      packages = packages.filter { |pkg| pkg.package.migrated_at.nil? }
      deliver :package_hash, PackageV2Adapter.collection(packages)
    rescue PackageRegistry::Twirp::PermissionDeniedError
      deliver_error!(404,
        message: "Packages not found.",
      )
    rescue PackageRegistry::Twirp::Error => e
      GitHub.logger.error(e)
      deliver_error!(500,
        message: "Internal server error.",
      )
    end
  end

  def delete_package(owner)
    deliver_error!(404,
      message: "GitHub Packages has not been enabled. Contact your Enterprise Administrator to enable GitHub Packages.",
    ) if GitHub.enterprise? && !GitHub.registry_enabled_for_enterprise?

    deliver_error!(404,
      message: "Not Found",
    ) if !PackageRegistryHelper.allow_access_to_actor?(owner, current_user)

    package_type = string_param!(key: :package_type)
    package_name = string_param!(key: :package)

    if Registry::Package::PUBLICLY_SUPPORTED_TYPES.include?(package_type.to_sym)
      # v1 package
      package = owner.packages.find_by(name: package_name, package_type: package_type)

      if package.nil? && Registry::Package.publicly_supported_migrated_types(owner).include?(package_type.to_sym)
        return delete_v2_package(owner, package_type, package_name)
      end

      if package.nil? || package.deleted?
        deliver_error!(404,
          message: "Package not found.",
        )
      end

      deliver_error!(403,
        message: "This package cannot be deleted due to an ongoing migration. Please try again later"
      ) if package.restrict_delete_restore_on_migration?

      if package.migrated?
        if package_type.to_sym == :docker
          package_name = "#{package.repository.name}/#{package_name}"
          package_type = "container"
        end
        return delete_v2_package(owner, package_type, package_name)
      end

      # package access is tied to the repository
      control_access :delete_package,
        repo: package.repository,
        resource: package,
        challenge: true,
        allow_integrations: true,
        allow_user_via_granular_actor: false

      begin
        package.delete!(
          actor: current_user,
          via_actions: false, # TODO: set this correctly once we support GitHub Apps/Actions
          user_agent: GitHub.context[:user_agent].to_s,
        )

        deliver_empty status: 204
      rescue Registry::Package::PackageDeletionError
        deliver_error!(400,
          message: Registry::Package::PUBLIC_PACKAGE_DELETE_ERR_MSG
        )
      end
    elsif PackageRegistry::Package::PUBLICLY_SUPPORTED_TYPES.include?(package_type.to_sym) || actions_package_type_included?(package_type.to_sym)
      # v2 package

      delete_v2_package(owner, package_type, package_name)
    else
      deliver_error!(422,
        message: "The package_type parameter is invalid.",
      )
    end
  end

  def delete_v2_package(owner, package_type, package_name)
    begin
      resp = v2_client.get_package_metadata(namespace: owner.display_login, name: package_name, ecosystem: package_type.to_sym, actor: current_user, version_limit: 1, search_action_packages_enabled: search_action_packages_enabled?)

      deliver_error!(404,
        message: "Package not found.",
      ) if resp&.package.nil? || resp.package.deleted?

      package = resp.package

      # v2 does not yet support GITHUB_TOKEN or GitHub App Tokens
      # https://github.com/github/c2c-package-registry/issues/2594
      control_access :delete_package_v2,
        resource: package,
        challenge: true,
        allow_integrations: true,
        allow_user_via_granular_actor: false

      v2_client.delete_package(namespace: owner.display_login, name: package_name, ecosystem: package_type.to_sym, actor: current_user, mode: :soft, search_action_packages_enabled: search_action_packages_enabled?)

      deliver_empty status: 204
    rescue PackageRegistry::Twirp::FailedPreconditionError
      deliver_error!(400,
        message: Registry::Package::PUBLIC_PACKAGE_DELETE_ERR_MSG
      )
    rescue PackageRegistry::Twirp::PermissionDeniedError
      deliver_error!(404,
        message: "Package not found.",
      )
    rescue PackageRegistry::Twirp::Error => e
      GitHub.logger.error(e)
      deliver_error!(500,
        message: "Internal server error.",
      )
    end
  end

  def restore_package(owner)
    deliver_error!(404,
      message: "GitHub Packages has not been enabled. Contact your Enterprise Administrator to enable GitHub Packages.",
    ) if GitHub.enterprise? && !GitHub.registry_enabled_for_enterprise?

    deliver_error!(404,
      message: "Not Found",
    ) if !PackageRegistryHelper.allow_access_to_actor?(owner, current_user)

    package_type = string_param!(key: :package_type)
    package_name = string_param!(key: :package)

    if Registry::Package::PUBLICLY_SUPPORTED_TYPES.include?(package_type.to_sym)
      # v1 package
      if params[:token]
        # token provided, use it to hone in on the proper package right away
        package = owner.packages.find_by(name: "deleted_#{params[:token]}", original_name: package_name, package_type: package_type)
      else
        # no token provided, use original_name and check if we got multiple returns
        packages = owner.packages.where(original_name: package_name, package_type: package_type)

        deliver_error!(409,
          message: "Multiple deleted packages match given name, specify a package by providing a restore token",
        ) if packages.size > 1

        package = packages.first
      end

      # check if the package was migrated before it was deleted
      # it will not have been deleted in v1 so we have to fetch it out by its regular name
      if package.nil?
        package = owner.packages.find_by(name: package_name, package_type: package_type)

        # return a 404 if we got the v1 package and it was not migrated somehow, that can only mean
        # it was never properly deleted
        deliver_error!(409,
          message: "An active package already exists with given name.",
        ) if package && !package&.migrated?
      end

      if package.nil?
        if Registry::Package.publicly_supported_migrated_types(owner).include?(package_type.to_sym)
          return restore_v2_package(owner, package_type, package_name)
        else
          deliver_error!(404,
            message: "Package not found.",
          )
        end
      end

      deliver_error!(403,
        message: "This package cannot be restored due to an ongoing migration. Please try again later"
      ) if package.restrict_delete_restore_on_migration?

      if package.migrated?
        if package_type.to_sym == :docker
          package_name = "#{package.repository.name}/#{package_name}"
          package_type = "container"
        end
        return restore_v2_package(owner, package_type, package_name)
      end

      # package access is tied to the repository
      control_access :restore_package,
        repo: package.repository,
        resource: package,
        challenge: true,
        allow_integrations: true,
        allow_user_via_granular_actor: false

      begin
        package.restore!(
          actor: current_user,
          via_actions: false, # TODO: set this correctly once we support GitHub Apps/Actions
          user_agent: GitHub.context[:user_agent].to_s,
        )
      rescue Registry::Package::PackageConflictError
        deliver_error!(409,
          message: "An active package already exists with given name.",
        )
      end

      deliver_empty status: 204
    elsif PackageRegistry::Package::PUBLICLY_SUPPORTED_TYPES.include?(package_type.to_sym) || actions_package_type_included?(package_type.to_sym)
      # v2 package
      restore_v2_package(owner, package_type, package_name)
    else
      deliver_error!(422,
        message: "The package_type parameter is invalid.",
      )
    end
  end

  def restore_v2_package(owner, package_type, package_name)
    begin
      if params[:token]
        packages = v2_client.get_packages_by_original_name(namespace: owner.display_login, name: package_name, ecosystem: package_type.to_sym, actor: current_user, search_action_packages_enabled: search_action_packages_enabled?)

        # use the token to get the proper package out of the one(s) returned
        package = packages.find { |pkg| pkg.name.include? "deleted_#{params[:token]}" }
      else
        # no token provided, use original_name and check if we got multiple returns
        packages = v2_client.get_packages_by_original_name(namespace: owner.display_login, name: package_name, ecosystem: package_type.to_sym, actor: current_user, search_action_packages_enabled: search_action_packages_enabled?)

        deliver_error!(409,
          message: "Multiple deleted packages match given name, specify a package by providing a restore token",
        ) if packages.size > 1

        package = packages.first
      end

      deliver_error!(404,
        message: "Package not found.",
      ) if package.nil?

      # v2 does not yet support GITHUB_TOKEN or GitHub App Tokens
      # https://github.com/github/c2c-package-registry/issues/2594
      control_access :restore_package_v2,
        resource: package,
        challenge: true,
        allow_integrations: true,
        allow_user_via_granular_actor: false

      v2_client.restore_package(namespace: owner.display_login, name: package.name, ecosystem: package_type.to_sym, actor: current_user, search_action_packages_enabled: search_action_packages_enabled?)

      deliver_empty status: 204
    rescue PackageRegistry::Twirp::PermissionDeniedError
      deliver_error!(404,
        message: "Package not found.",
      )
    rescue PackageRegistry::Twirp::AlreadyExistsError
      deliver_error!(409,
        message: "Active package version already exists with given name.",
      )
    rescue PackageRegistry::Twirp::InvalidArgumentError
      GitHub.logger.error(e)
      deliver_error!(422,
         message: "Package restore was not successful. The package name #{owner.name}/#{original_name} has been retired and cannot restored.",
      )
    rescue PackageRegistry::Twirp::Error => e
      GitHub.logger.error(e)
      deliver_error!(500,
        message: "Internal server error.",
      )
    end
  end

  def list_package_versions(owner)
    deliver_error!(404,
      message: "GitHub Packages has not been enabled. Contact your Enterprise Administrator to enable GitHub Packages.",
    ) if GitHub.enterprise? && !GitHub.registry_enabled_for_enterprise?

    deliver_error!(404,
      message: "Not Found",
    ) if !PackageRegistryHelper.allow_access_to_actor?(owner, current_user)
    # filter by state
    state = case params[:state]
    when "", nil, /active/ then :active
    when /deleted/ then :deleted
    else
      deliver_error!(422,
        message: "The state parameter is invalid.",
      )
    end

    package_type = string_param!(key: :package_type)
    package_name = string_param!(key: :package)

    if Registry::Package::PUBLICLY_SUPPORTED_TYPES.include?(package_type.to_sym)
      # v1 package
      package = owner.packages.find_by(name: package_name, package_type: package_type)

      if package.nil?
        if Registry::Package.publicly_supported_migrated_types(owner).include?(package_type.to_sym)
          return list_v2_package_versions(owner, state, package_type, package_name)
        else
          deliver_error!(404,
            message: "Package not found.",
          )
        end
      end

      if package.migrated?
        if package_type.to_sym == :docker
          package_name = "#{package.repository.name}/#{package_name}"
          package_type = "container"
        end
        return list_v2_package_versions(owner, state, package_type, package_name)
      end

      # viewing deleted package versions requires delete access
      access_level = state == :deleted ? :delete_package : :get_package
      if access_level == :delete_package
        set_forbidden_message "You need at least delete:packages and read:packages scopes to get a package's deleted versions."
      end

      # package access is tied to the repository
      control_access access_level,
        repo: package.repository,
        resource: package,
        challenge: true,
        allow_integrations: true,
        allow_user_via_granular_actor: false

      scope = package.package_versions.exclude_docker_base_layer

      # only return deleted package versions if asked, otherwise only return non-deleted
      package_versions = state == :deleted ? scope.deleted : scope.not_deleted

      # remove internal docker-base-layer from results
      deliver :package_version_hash, PackageVersionV1Adapter.collection(PackageV1Adapter.new(package), package_versions.order(updated_at: :desc, id: :desc)).paginate(pagination)
    elsif PackageRegistry::Package::PUBLICLY_SUPPORTED_TYPES.include?(package_type.to_sym) || actions_package_type_included?(package_type.to_sym)
      # v2 package
      list_v2_package_versions(owner, state, package_type, package_name)
    else
      deliver_error!(422,
        message: "The package_type parameter is invalid.",
      )
    end
  end

  def list_v2_package_versions(owner, state, package_type, package_name)
    # viewing deleted package versions requires delete access
    access_level = state == :deleted ? :delete_package_v2 : :get_package_v2
    if access_level == :delete_package_v2
      set_forbidden_message "You need at least delete:packages and read:packages scopes to get a package's deleted versions."
    end

    begin
      per_page = pagination[:per_page].present? ? pagination[:per_page].to_i : 30  # default to 30, cap at 100
      per_page = 100 if per_page > 100
      page = pagination[:page].to_i || 0
      offset = (page - 1) * per_page
      will_paginate = !per_page.zero?

      if state == :deleted
        # need to check if package exists first to return proper error message if it does not
        resp = v2_client.get_package_metadata(namespace: owner.display_login, name: package_name, ecosystem: package_type.to_sym, actor: current_user, version_limit: 1, search_action_packages_enabled: search_action_packages_enabled?)
      else
        resp = v2_client.get_package_metadata(namespace: owner.display_login, name: package_name, ecosystem: package_type.to_sym, actor: current_user, version_limit: per_page, version_offset: offset, search_action_packages_enabled: search_action_packages_enabled?)
      end

      deliver_error!(404,
        message: "Package not found.",
      ) if resp&.package.nil?

      package = resp.package

      # v2 does not yet support GITHUB_TOKEN or GitHub App Tokens
      # https://github.com/github/c2c-package-registry/issues/2594
      control_access access_level,
        resource: package,
        challenge: true,
        allow_integrations: true,
        allow_user_via_granular_actor: false

      if state == :deleted
        resp = v2_client.get_deleted_package_versions(namespace: owner.display_login, name: package_name, ecosystem: package_type.to_sym, actor: current_user, version_limit: per_page, version_offset: offset, search_action_packages_enabled: search_action_packages_enabled?)
        # return empty result set here if no deleted package_versions instead of 404ing
        return deliver(:package_version_hash, []) if resp.nil?
      end

      build_pagination_links(per_page, page, resp.total_version_count) if will_paginate
    rescue PackageRegistry::Twirp::PermissionDeniedError
      deliver_error!(404,
        message: "Package not found.",
      )
    rescue PackageRegistry::Twirp::Error => e
      GitHub.logger.error(e)
      deliver_error!(500,
        message: "Internal server error.",
      )
    end

    deliver :package_version_hash, PackageVersionV2Adapter.collection(PackageV2Adapter.new(resp), resp.package_versions)
  end

  def get_package_version(owner)
    deliver_error!(404,
      message: "GitHub Packages has not been enabled. Contact your Enterprise Administrator to enable GitHub Packages.",
    ) if GitHub.enterprise? && !GitHub.registry_enabled_for_enterprise?

    deliver_error!(404,
      message: "Not Found",
    ) if !PackageRegistryHelper.allow_access_to_actor?(owner, current_user)

    package_type = string_param!(key: :package_type)
    package_name = string_param!(key: :package)
    version_id = int_id_param!(key: :version_id, halt: true)

    if Registry::Package::PUBLICLY_SUPPORTED_TYPES.include?(package_type.to_sym)
      # v1 package
      package = owner.packages.find_by(name: package_name, package_type: package_type)

      if package.nil?
        if Registry::Package.publicly_supported_migrated_types(owner).include?(package_type.to_sym)
          return get_v2_package_version(owner, package_type, package_name, version_id)
        else
          deliver_error!(404,
            message: "Package not found.",
          )
        end
      end

      # added docker check because for docker migrated packages we do not call
      # v2 get package version right now so to avoid this call for docker
      if package.migrated? && package_type.to_sym != :docker
        return get_v2_package_version(owner, package_type, package_name, version_id)
      end

      version = package.package_versions.find_by(id: version_id)

      deliver_error!(404,
        message: "Package version not found.",
      ) if version.nil? || version.deleted?

      # package access is tied to the repository
      control_access :get_package,
        repo: package.repository,
        resource: package,
        challenge: true,
        allow_integrations: true,
        allow_user_via_granular_actor: false

      deliver :package_version_hash, PackageVersionV1Adapter.new(PackageV1Adapter.new(package), version)
    elsif PackageRegistry::Package::PUBLICLY_SUPPORTED_TYPES.include?(package_type.to_sym) || actions_package_type_included?(package_type.to_sym)
      # v2 package
      get_v2_package_version(owner, package_type, package_name, version_id)
    else
      deliver_error!(422,
        message: "The package_type parameter is invalid.",
      )
    end
  end

  def get_v2_package_version(owner, package_type, package_name, version_id)
    # v2 package
    begin
      # get the package as an existence check and so we can populate the version result with metadata the resides on the package
      resp = v2_client.get_package_metadata(namespace: owner.display_login, name: package_name, ecosystem: package_type.to_sym, actor: current_user, version_limit: 1)

      deliver_error!(404,
        message: "Package not found.",
      ) if resp&.package.nil?

      package = resp.package

      # v2 does not yet support GITHUB_TOKEN or GitHub App Tokens
      # https://github.com/github/c2c-package-registry/issues/2594
      control_access :get_package_v2,
        resource: package,
        challenge: true,
        allow_integrations: true,
        allow_user_via_granular_actor: false

      # v2 package version
      version = v2_client.get_package_version(namespace: owner.display_login, name: resp.package.name, ecosystem: package_type.to_sym, actor: current_user, version_id: version_id, search_action_packages_enabled: search_action_packages_enabled?)
      deliver_error!(404,
        message: "Package version not found.",
      ) if version.nil? || version.deleted?

    rescue PackageRegistry::Twirp::PermissionDeniedError
      deliver_error!(404,
        message: "Package not found.",
      )
    rescue PackageRegistry::Twirp::Error => e
      GitHub.logger.error(e)
      deliver_error!(500,
        message: "Internal server error.",
      )
    end

    deliver :package_version_hash, PackageVersionV2Adapter.new(PackageV2Adapter.new(resp), version)
  end

  def delete_package_version(owner)
    deliver_error!(404,
      message: "GitHub Packages has not been enabled. Contact your Enterprise Administrator to enable GitHub Packages.",
    ) if GitHub.enterprise? && !GitHub.registry_enabled_for_enterprise?

    deliver_error!(404,
      message: "Not Found",
    ) if !PackageRegistryHelper.allow_access_to_actor?(owner, current_user)
    package_type = string_param!(key: :package_type)
    package_name = string_param!(key: :package)
    version_id = int_id_param!(key: :version_id, halt: true)

    if Registry::Package::PUBLICLY_SUPPORTED_TYPES.include?(package_type.to_sym)
      # v1 package
      package = owner.packages.find_by(name: package_name, package_type: package_type)

      if package.nil?
        if Registry::Package.publicly_supported_migrated_types(owner).include?(package_type.to_sym)
          return delete_v2_package_version(owner, package_type, package_name, version_id)
        else
          deliver_error!(404,
            message: "Package not found.",
          )
        end
      end

      # added docker check because for docker migrated packages we do not call
      # v2 delete package version right now so to avoid this call for docker
      if package.migrated? && package_type.to_sym != :docker
        return delete_v2_package_version(owner, package_type, package_name, version_id)
      end

      deliver_error!(400,
        message: "You cannot delete the last version of a package. You must delete the package instead.",
      ) if package.package_versions.exclude_docker_base_layer.count == 1

      # package access is tied to the repository
      control_access :delete_package,
        repo: package.repository,
        resource: package,
        challenge: true,
        allow_integrations: true,
        allow_user_via_granular_actor: false

      package_version = package.package_versions.find_by(id: version_id)

      deliver_error!(404,
        message: "Package version not found.",
      ) if package_version.nil? || package_version.deleted?

      deliver_error!(403,
        message: "This version cannot be deleted due to an ongoing migration. Please try again later"
      ) if package_version.restrict_delete_restore_on_migration?

      begin
        package_version.delete!(
          actor: current_user,
          via_actions: false, # TODO: set this correctly once we support GitHub Apps/Actions
          user_agent: GitHub.context[:user_agent].to_s,
        )

        deliver_empty status: 204
      rescue Registry::PackageVersion::PackageVersionDeletionError
        deliver_error!(400,
          message: Registry::PackageVersion::PUBLIC_PACKAGE_VERSION_DELETE_ERR_MSG
        )
      end
    elsif PackageRegistry::Package::PUBLICLY_SUPPORTED_TYPES.include?(package_type.to_sym) || actions_package_type_included?(package_type.to_sym)
      # v2 package
      delete_v2_package_version(owner, package_type, package_name, version_id)
    else
      deliver_error!(422,
        message: "The package_type parameter is invalid.",
      )
    end
  end

  def delete_v2_package_version(owner, package_type, package_name, version_id)
    # v2 package
    begin
      # get the package so we can check if its versions can be deleted
      resp = if package_type.to_sym == :container
        v2_client.get_container_metadata_for_version_deletion(namespace: owner.display_login, name: package_name, ecosystem: package_type.to_sym, actor: current_user)
      else
        v2_client.get_package_metadata(namespace: owner.display_login, name: package_name, ecosystem: package_type.to_sym, actor: current_user, version_limit: 2, search_action_packages_enabled: search_action_packages_enabled?)
      end

      deliver_error!(404,
        message: "Package not found.",
      ) if resp&.package.nil?

      package = resp.package

      # v2 does not yet support GITHUB_TOKEN or GitHub App Tokens
      # https://github.com/github/c2c-package-registry/issues/2594
      control_access :delete_package_v2,
        resource: package,
        challenge: true,
        allow_integrations: true,
        allow_user_via_granular_actor: false

      package_version = v2_client.get_package_version(namespace: owner.display_login, name: package_name, ecosystem: package_type.to_sym, actor: current_user, version_id: version_id, search_action_packages_enabled: search_action_packages_enabled?)

      deliver_error!(404,
        message: "Package version not found.",
      ) if package_version.nil? || package_version.deleted?

      case package_type.to_sym
      when :container
        if resp.has_single_tagged_version
          deliver_error!(400,
            message: "You cannot delete the last tagged version of a package. You must delete the package instead.",
          ) if package_version.tags.any?
        end
      else
        if resp.total_tagged_versions_count < 2
          # deleting last version of non container package should delete the package
          return delete_v2_package(owner, package_type, package_name)
        end
      end

      v2_client.delete_package_version(namespace: owner.display_login, name: package_name, ecosystem: package_type.to_sym, actor: current_user, version: package_version.version, mode: :soft, search_action_packages_enabled: search_action_packages_enabled?)

      deliver_empty status: 204
    rescue PackageRegistry::Twirp::PermissionDeniedError
      deliver_error!(404,
        message: "Package not found.",
      )
    rescue PackageRegistry::Twirp::FailedPreconditionError
      deliver_error!(400,
        message: Registry::PackageVersion::PUBLIC_PACKAGE_VERSION_DELETE_ERR_MSG,
      )
    rescue PackageRegistry::Twirp::Error => e
      GitHub.logger.error(e)
      deliver_error!(500,
        message: "Internal server error.",
      )
    end
  end

  def restore_package_version(owner)
    deliver_error!(404,
      message: "GitHub Packages has not been enabled. Contact your Enterprise Administrator to enable GitHub Packages.",
    ) if GitHub.enterprise? && !GitHub.registry_enabled_for_enterprise?

    deliver_error!(404,
      message: "Not Found",
    ) if !PackageRegistryHelper.allow_access_to_actor?(owner, current_user)

    package_type = string_param!(key: :package_type)
    package_name = string_param!(key: :package)
    version_id = int_id_param!(key: :version_id, halt: true)

    if Registry::Package::PUBLICLY_SUPPORTED_TYPES.include?(package_type.to_sym)
      # v1 package
      package = owner.packages.find_by(name: package_name, package_type: package_type)

      if package.nil?
        if Registry::Package.publicly_supported_migrated_types(owner).include?(package_type.to_sym)
          return restore_v2_package_version(owner, package_type, package_name, version_id)
        else
          deliver_error!(404,
            message: "Package not found.",
          )
        end
      end

      # added docker check because for docker migrated packages we do not call
      # v2 restore package version right now so to avoid this call for docker
      if package.migrated? && package_type.to_sym != :docker
        return restore_v2_package_version(owner, package_type, package_name, version_id)
      end

      # package access is tied to the repository
      control_access :restore_package,
        repo: package.repository,
        resource: package,
        challenge: true,
        allow_integrations: true,
        allow_user_via_granular_actor: false

      package_version = package.package_versions.find_by(id: version_id)

      deliver_error!(404,
        message: "Package version not found.",
      ) if package_version.nil?

      deliver_error!(403,
        message: "This version cannot be restored due to an ongoing migration. Please try again later"
      ) if package_version.restrict_delete_restore_on_migration?

      begin
        package_version.restore!(
          actor: current_user,
          via_actions: false, # TODO: set this correctly once we support GitHub Apps/Actions
          user_agent: GitHub.context[:user_agent].to_s,
        )
      rescue Registry::PackageVersion::PackageVersionRestorationError
        deliver_error!(422,
          message: "Restore not allowed at the moment, please try after some time.",
        )
      end

      deliver_empty status: 204
    elsif PackageRegistry::Package::PUBLICLY_SUPPORTED_TYPES.include?(package_type.to_sym) || actions_package_type_included?(package_type.to_sym)
      # v2 package
      restore_v2_package_version(owner, package_type, package_name, version_id)
    else
      deliver_error!(422,
        message: "The package_type parameter is invalid.",
      )
    end
  end

  def restore_v2_package_version(owner, package_type, package_name, version_id)
    # v2 package
    begin
      # get the package as an existence check and so we can populate the version result with metadata the resides on the package
      resp = v2_client.get_package_metadata(namespace: owner.display_login, name: package_name, ecosystem: package_type.to_sym, actor: current_user, version_limit: 1, search_action_packages_enabled: search_action_packages_enabled?)

      deliver_error!(404,
        message: "Package not found.",
      ) if resp&.package.nil?

      package = resp.package

      # v2 does not yet support GITHUB_TOKEN or GitHub App Tokens
      # https://github.com/github/c2c-package-registry/issues/2594
      control_access :restore_package_v2,
        resource: package,
        challenge: true,
        allow_integrations: true,
        allow_user_via_granular_actor: false

      package_version = v2_client.get_package_version(namespace: owner.display_login, name: package_name, ecosystem: package_type.to_sym, actor: current_user, version_id: version_id, search_action_packages_enabled: search_action_packages_enabled?)

      deliver_error!(404,
        message: "Package version not found.",
      ) if package_version.nil?

      v2_client.restore_package_version(namespace: owner.display_login, name: package_name, ecosystem: package_type.to_sym, actor: current_user, version: package_version.version, search_action_packages_enabled: search_action_packages_enabled?)

      deliver_empty status: 204
    rescue PackageRegistry::Twirp::PermissionDeniedError
      deliver_error!(404,
        message: "Package not found.",
      )
    rescue PackageRegistry::Twirp::AlreadyExistsError
      deliver_error!(400,
        message: "Active package version already exists with given name.",
      )
    rescue PackageRegistry::Twirp::Error => e
      GitHub.logger.error(e)
      deliver_error!(500,
        message: "Internal server error.",
      )
    end
  end

  # Helper methods
  def actions_package_type_included?(package_type)
    search_action_packages_enabled? && package_type == :actions
  end

  def search_action_packages_enabled?
    current_user.feature_enabled?(:search_action_packages)
  end

  def string_param!(key:)
    str = params.delete(key)

    unless str =~ /\A\S+\z/
      message = "The #{key} parameter is required."
      deliver_error!(422, message: message)
    end

    str.to_s
  end

  def string_visibility_param!(key:, required: false, halt_on_invalid: false)
    case params.delete(key)&.downcase
    when /public/ then "public"
    when /private/ then "private"
    when /internal/ then "internal"
    when nil
      deliver_error!(422,
        message: "The visibility parameter is required.",
      ) if required

      nil
    else
      deliver_error!(422,
        message: "The visibility parameter is invalid.",
      ) if halt_on_invalid

      nil
    end
  end

  def package_owner(user)
    # Delegate to the bot's installation target if the user is a bot
    user&.bot? ? user.installation.target : user
  end

  def v2_client
    @client ||= PackageRegistry::Twirp.metadata_client
  end

  def build_pagination_links(per_page, page, total_count)
    total_count ||= 0 # in case total_count is nil
    page = 1 if page == 0 # no page being given is identical to page 1
    has_next_page = total_count > (per_page * page) # 2 > 1 * 0
    has_prev_page = (page > 1) && (per_page < total_count)
    last_page = (total_count.to_f / per_page).ceil
    has_last_page = page != last_page

    next_page = page + 1
    prev_page = page - 1
    prev_page = last_page if prev_page > last_page

    @links.add_current({ page: next_page, per_page: per_page }, rel: "next") if has_next_page
    @links.add_current({ page: prev_page, per_page: per_page }, rel: "prev") if has_prev_page
    @links.add_current({ page: 1, per_page: per_page }, rel: "first") if has_prev_page
    @links.add_current({ page: last_page, per_page: per_page }, rel: "last") if has_last_page
  end

  # Adapters to adapt v1/v2 objects to a common serializable object
  class PackageAdapter < ::SimpleDelegator
    def self.collection(packages)
      packages.map { |package| new package }
    end
  end

  # PackageV2Adapter is an adapter that adapts V2 package objects to the common
  # object that is expected from the packages_dependency serializer
  class PackageV2Adapter < PackageAdapter
    def initialize(resp)
      @version_count = resp.total_version_count if resp.respond_to? :total_version_count
      @package = resp.package
      # delegates all method calls to package object unless implemented
      super(resp.package)
    end

    def version_count
      return nil if @version_count.zero?
      @version_count
    end

    def uri
      "#{root_uri}/#{ERB::Util.url_encode(name)}"
    end

    def html_uri
      # package overview uri
      "#{root_uri}/package/#{ERB::Util.url_encode(name)}"
    end

    def repository
      package.repository
    end

    private

    def root_uri
      root = package.owner.organization? ? "orgs" : "users"
      "/#{root}/#{package.owner.login_for_api}/packages/#{package.ecosystem}"
    end

    attr_reader :package
  end

  # PackageEntityAdapter is an adapter that adapts V2 package objects to the common
  # object that is expected from the registry_packages_dependency serializer from webhooks
  class PackageEntityAdapter < PackageAdapter
    def initialize(package_entity)
      @package = package_entity
      super(package)
    end

    def package_type
      package.ecosystem.to_s
    end

    def owner
      if package.respond_to?(:owner_id) && package.owner_id
        User.find_by(id: package.owner_id)
      elsif GitHub.multi_tenant_enterprise?
        # In multi-tenant mode, strip the slug to get the user or org login.
        User.find_by(login: package.namespace.partition("_").first)
      else
        # In all other cases, the namespace is the user or org login.
        User.find_by(login: package.namespace)
      end
    end

    def repository
      Repository.find_by(id: repo_id)
    end

    def source_registry
      registry_package_type = package_type
      {
        about_url: "#{GitHub.help_url}/packages/learn-github-packages/introduction-to-github-packages",
        name: "GitHub #{registry_package_type} registry",
        type: registry_package_type,
        url: "#{GitHub.urls.registry_url(registry_package_type)}#{package.namespace}", # GitHub.urls.registry_url includes trailing slash
        vendor: "GitHub Inc"
      }
    end

    private

    attr_reader :package
  end

  class PackageFileEntityAdapter < PackageAdapter
    def initialize(package_file_entity)
      @package_file = package_file_entity
      super(package_file)
    end

    def url
      ""
    end

    def content_type
      "application/octet-stream".freeze
    end

    def filename
      package_file.file_name
    end

    attr_reader :package_file
  end

  # PackageVersionEntityAdapter is an adapter that adapts V2 package version objects to the common
  # object that is expected from the registry_packages_dependency serializer from webhooks
  class PackageVersionEntityAdapter < PackageAdapter
    def initialize(package_version_entity, package, package_file)
      @package_version = package_version_entity
      @package = package
      @package_file = package_file
      super(package_version)
    end

    def release
    end

    def version
      package_version.name
    end

    def summary
      package_version.description
    end

    def body
      if package_version.ecosystem.downcase.to_sym == :nuget || package_version.ecosystem.downcase.to_sym == :npm || package_version.ecosystem.downcase.to_sym == :rubygems
        ecosystem_metadata.description
      else
        package&.repository&.preferred_readme
      end
    end

    def body_html
      # TODO
    end

    def package_manifest
      if package_version.ecosystem.downcase.to_sym == :nuget
        ecosystem_metadata.manifest
      else
        ""
      end
    end

    def serializeable_metadata
      []
    end

    def package_files
      files = []
      package_file.map do |file|
        files.push(PackageFileEntityAdapter.new(file))
      end
      files
    end

    def author
      User.find_by(id: package.author_id) unless package.author_type == :ACTOR_TYPE_INSTALLATION
    end

    def installation_command
      if package_version.ecosystem.downcase.to_sym == :container
        "docker pull #{source_url}"
      elsif package_version.ecosystem.downcase.to_sym == :nuget
        ""  # Since Installation command is not a part of nuget metadata in V2, this field will be blank
      elsif package_version.ecosystem.downcase.to_sym == :rubygems
        ""  # Since Installation command is not a part of rubygems metadata in V2, this field will be blank

      else
        ecosystem_metadata.installation_command
      end
    end

    def source_url
      if package_version.ecosystem.downcase.to_sym == :container
        version_tag = ecosystem_metadata.tag ? ":#{ecosystem_metadata.tag.name}" : "@#{ecosystem_metadata.manifest.digest}"
        "#{GitHub.urls.registry_host_name(:containers)}/#{package.namespace.downcase}/#{package.name.downcase}#{version_tag}"
      else
        "#{GitHub.urls.registry_host_name(package_version.ecosystem.downcase.to_sym)}/#{package.namespace.downcase}/#{package.name.downcase}:#{package_version.name}"
      end
    end

    def html_uri
      root = package.owner.organization? ? "orgs" : "users"
      # don't return the html url for a deleted version as users can't view it in the UI
      package_version.deleted_at.present? ? nil : "/#{root}/#{package.owner.login_for_api}/packages/#{package.ecosystem.downcase}/#{package.name}/#{package_version.id}"
    end

    def format_metadata
      eco_metadata = package_version.send(ecosystem_metadata_label).to_h
      eco_metadata_formatted = []
      eco_metadata.each do |key, value|
        camelcasestring = (key.to_s).split("_").collect(&:capitalize).join
        if Registry::Metadatum::NON_SERIALIZED_KEYS.include?(camelcasestring)
          next
        end
        eco_metadata_formatted.push({ name: camelcasestring, value: value, id: "" })
      end
      eco_metadata_formatted
    end

    def version_ecosystem_metadata
      return unless package_version.ecosystem.present?
      if package_version.ecosystem.downcase.to_sym == :nuget
        format_metadata
      elsif package_version.ecosystem.downcase.to_sym == :container || package_version.ecosystem.downcase.to_sym == :npm
        (package_version.send(ecosystem_metadata_label))&.to_h
      else
        []
      end
    end

    def version_metadata
      if package_version.ecosystem.downcase.to_sym == :nuget
        format_metadata
      else
        []
      end
    end

    def ecosystem_metadata
      return unless package_version.ecosystem.present?
      package_version.send(ecosystem_metadata_label)
    end

    def ecosystem_metadata_label
      return unless package_version.ecosystem.present?
      "#{package_version.ecosystem.downcase}_metadata".to_sym
    end

    private

    attr_reader :package_version, :package, :package_file
  end

  # PackageV1Adapter is an adapter that adapts V1 package objects to the common
  # object that is expected from the packages_dependency serializer
  class PackageV1Adapter < PackageAdapter
    def initialize(package)
      @package = package
      # delegates all method calls to package object unless implemented
      super(package)
    end

    def version_count
      package.package_versions.not_deleted.count
    end

    def uri
      root = package.repository.owner.organization? ? "orgs" : "users"
      "/#{root}/#{package.repository.owner.login_for_api}/packages/#{package.package_type}/#{ERB::Util.url_encode(name)}"
    end

    def html_uri
      "/#{package.repository.name_with_owner_for_api}/packages/#{package.id}"
    end

    def namespace
      # nwo not used in response therefore safe to use here.
      package.repository.nwo # rubocop:disable GitHub/DoNotAllowNameWithOwner
    end

    def description
    end

    def ecosystem
      package.package_type
    end

    private

    attr_reader :package
  end

  class PackageVersionAdapter < ::SimpleDelegator
    def self.collection(package, versions)
      versions.map { |v| new package, v }
    end
  end

  # PackageVersionV2Adapter is an adapter that adapts V2 package/package_version objects to the common
  # object that is expected from the packages_dependency serializer
  class PackageVersionV2Adapter < PackageVersionAdapter
    def initialize(package, version)
      @package = package
      @version = version
      # delegates all method calls to version object unless implemented
      super(version)
    end

    def name
      version.deleted? ? version.original_name : version.name
    end

    def package_html_uri
      package.html_uri
    end

    def uri
      "#{package.uri}/versions/#{id}"
    end

    def html_uri
      root = package.owner.organization? ? "orgs" : "users"
      # don't return the html url for a deleted version as users can't view it in the UI
      version.deleted? ? nil : "/#{root}/#{package.owner.login_for_api}/packages/#{package.ecosystem}/#{ERB::Util.url_encode(package.name)}/#{id}"
    end

    def license
      version.license&.blank? ? nil : version.license
    end

    def package_type
      package.package_type
    end

    def container_metadata
      {
        tags: version.containerMetadata.tags.map(&:name),
      }
    end

    private

    attr_reader :package, :version
  end

  # PackageVersionV1Adapter is an adapter that adapts V1 package/package_version objects to the common
  # object that is expected from the packages_dependency serializer
  class PackageVersionV1Adapter < PackageVersionAdapter
    def initialize(package, version)
      @package = package
      @version = version
      # delegates all method calls to version object unless implemented
      super(version)
    end

    def name
      # compatibility with v2
      package_type == :docker ? "sha256:#{version.sha256}" : version_name
    end

    def package_html_uri
      package.html_uri
    end

    def uri
      "#{package.uri}/versions/#{id}"
    end

    def html_uri
      # don't return the html url for a deleted version as users can't view it in the UI
      version.deleted? ? nil : "#{package_html_uri}?version=#{version_name}"
    end

    def description
      version.summary
    end

    def license
      package.repository.license&.spdx_id
    end

    def package_type
      package.package_type.to_sym
    end

    def docker_metadata
      {
        tags: [version.version],
      }
    end

    def ecosystem
      package.package_type
    end

    def ecosystem_metadata_label
      return unless ecosystem.present?
      "#{ecosystem.downcase}_metadata".to_sym
    end

    def source_url
      return "" unless %w(docker rubygems).include?(ecosystem)
      "#{GitHub.urls.registry_host_name(ecosystem.to_sym)}/#{package.namespace.downcase}/#{package.name.downcase}:#{version_name}"
    end

    private

    attr_reader :package, :version

    def version_name
      version.deleted? ? version.original_name : version.version
    end
  end
end
