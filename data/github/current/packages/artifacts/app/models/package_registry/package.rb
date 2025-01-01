# typed: false
# frozen_string_literal: true

module PackageRegistry
  class Package < SimpleDelegator
    include Permissions::Attributes::Wrapper
    include UrlHelper

    self.permissions_wrapper_class = Permissions::Attributes::PackageRegistryPackage

    REPOSITORY_URL_REGEX = "(?<=github.com\/)(?<name_with_owner>[^/]+\/[^/]+)"
    NON_GITHUB_REPOSITORY_NAME_REGEX = /(\.\w+)\/(?<name_with_owner>[^\/]+\/[^\/]+)/
    PUBLICLY_SUPPORTED_TYPES = %i(container)

    attr_reader :latest_version, :package

    def initialize(package, package_type: nil)
      @package = package
      @package_type = package_type
      super(package)
    end

    def action_package_resolution_settings
      # Only containers can be an actions package.
      # But packages can live outside of RMS, so we should only request package resolution settings from RMS for packages that live there.
      return nil unless ecosystem == :container
      @action_package_resolution_settings ||= PackageRegistry::Twirp.action_packages_client.get_action_package_resolution_settings(package_id: package.id)
    end

    def is_actions_package?(actor)
      return false unless GitHub.flipper[:view_immutable_actions].enabled?(actor)
      !!action_package_resolution_settings&.is_action_package
    end

    def can_activate_actions_package?(actor)
      enabled_for_owner = false
      enabled_for_repo = false

      enabled_for_owner = owner&.feature_enabled?(:serve_immutable_actions)
      if !enabled_for_owner
        # Note that we check the FF on the repository matching the package's namespace and name as long as the repository exists.
        # Technically we could check the FF on the repository the packages is associated with for a few reasons:
        # - While we disallow linking action packages to a repo with another NWO, the repo can be renamed.
        # - When resolving an action package, we don't have the repository ID, so we can't check the FF on the repository the package is associated with.
        #   As we want to stay consistent with the FF check for serving the package, we check the FF on the repository matching the package's namespace and name.
        #
        # Uses with_name_with_owner to exclude renamed repositories.
        enabled_for_repo = Repository.with_name_with_owner("#{@package.namespace}/#{@package.name}")&.feature_enabled?(:serve_immutable_actions)
      end

      return false unless enabled_for_owner || enabled_for_repo
      return false unless is_actions_package?(actor)
      action_package_resolution_settings&.settings&.activated == false
    end

    def actions_package_activated?(actor)
      return false unless is_actions_package?(actor)
      action_package_resolution_settings&.settings&.activated == true
    end

    def author
      GitHub.logger.info("code.function": "package_registry.package.author", "author_type": package.author_type, "author_id": package.author_id, "package_id": package.id)
      if package.author_type == :SCOPED_INSTALLATION
        ScopedIntegrationInstallation.find_by_id(package.author_id)
      else
        User.find_by_id(package.author_id)
      end
    end

    def dockerfile_url
      latest_version.metadata&.labels&.source
    end

    def ecosystem
      package.ecosystem.downcase.to_sym
    end
    alias_method :package_type, :ecosystem

    def package_type_for_actor(actor)
      return ecosystem unless ecosystem == :container
      @package_type_for_actor ||= :actions if is_actions_package?(actor)
      @package_type_for_actor ||= ecosystem
    end

    def api_package_type
      return :actions if @package_type == Proto::RegistryMetadata::V1::Package::PackageSubtype::ACTIONS
      ecosystem
    end

    def latest_version=(version)
      @latest_version = version
    end

    def latest_non_signature_version(actor)
      return latest_version unless ecosystem == :container
      return latest_version unless GitHub.flipper[:search_action_packages].enabled?(actor)
      @client ||= PackageRegistry::Twirp.metadata_client
      @latest_non_signature_version ||= @client.get_container_latest_version(
        ecosystem: package.ecosystem,
        namespace: package.namespace,
        name: package.name,
        actor: actor
      )
      @latest_non_signature_version ||= latest_version
    end

    def readable_by?(actor)
      owner.readable_by?(actor) || (GitHub.flipper[:packages_readble_if_repo_readable].enabled?(actor) && repository&.readable_by?(actor))
    end

    def owner
      return @owner if defined?(@owner)
      @owner = if @owner_id
        User.find_by(id: @owner_id)
      elsif package.respond_to?(:owner_id) && package.owner_id
        User.find_by(id: @package.owner_id)
      elsif GitHub.multi_tenant_enterprise?
        # In multi-tenant mode, strip the slug to get the user or org login.
        User.find_by(login: package.namespace.partition("_").first)
      else
        # In all other cases, the namespace is the user or org login.
        User.find_by(login: package.namespace)
      end
    end

    def owner_id=(owner_id)
      @owner_id = owner_id
    end

    def public?
      visibility == "public"
    end

    def private?
      visibility == "private"
    end

    def internal?
      visibility == "internal"
    end

    def visibility
      package.visibility.to_s.downcase
    end

    def deleted?
      deleted_at.present?
    end

    def can_be_deleted?
      true
    end

    def repository
      return unless package.repo_id.present?
      Repository.find_by(id: package.repo_id)
    end

    # Public: Get display name of the referenced repository. If a github repo,
    # this returns repo name with owner. If a non-github repo, attempt to parse
    # the url for a repo name.
    def repository_name_with_owner
      if repository
        repository.name_with_display_owner
      elsif linked_repo_url
        linked_repo_url.downcase.match(NON_GITHUB_REPOSITORY_NAME_REGEX) { |m| m[:name_with_owner] }
      end
    end

    def linked_repo_url
      if repository
        repository_url(repository)
      else
        case @package.ecosystem.downcase.to_sym
        when :container
          latest_version&.metadata&.labels&.source
        when :npm, :nuget, :maven
          latest_version&.metadata&.repository&.url
        when :rubygems
          latest_version&.metadata&.repo
        end
      end
    end

    def user_role_target_type
      "Package"
    end

    def target_for_conditional_access
      # In the CAP framework, TFCA refers to the entity governing
      # the conditional access rules that grant access to resources they own.
      # If any changes are done to this method, please loop in @github/authorization.
      # https://thehub.github.com/engineering/development-and-ops/dotcom/cap/how-does-cap-evaluation-work/#target-for-conditional-access-tfca

      # There is a known vulnerability where a package can have a nil owner (user/org)
      # if the owner changes their name. Given that a package should always have an owner,
      # we must not use semantics such as: :no_target_for_conditional_access unless owner
      # as that would allow bypassing policy enforcement for org owned packages which may need it.
      # https://github.com/github/c2c-package-registry/issues/2240
      owner
    end

    def members_can_publish_public_packages?
      is_enterprise_managed = owner.organization? ? owner.enterprise_managed_user_enabled? : owner.is_enterprise_managed?
      return false if is_enterprise_managed
      !owner.organization? || owner.members_can_publish_public_packages?
    end

    def members_can_publish_internal_packages?
      owner.organization? && owner.members_can_publish_internal_packages?
    end

    def created_at
      epoch_micros = package.created_at.nanos / 10**3
      Time.at(package.created_at.seconds, epoch_micros)
    end

    def updated_at
      epoch_micros = package.updated_at.nanos / 10**3
      Time.at(package.updated_at.seconds, epoch_micros)
    end

    def deleted_at
      return nil unless package.deleted_at

      epoch_micros = package.deleted_at.nanos / 10**3
      Time.at(package.deleted_at.seconds, epoch_micros)
    end

    def migrated_at
      return nil unless package.migrated_at

      epoch_micros = package.migrated_at.nanos / 10**3
      Time.at(package.migrated_at.seconds, epoch_micros)
    end

    def sync_access_from_repo(repository:)
      # Defining a maximum number of pages to fetch for sync_access_from_repo. This is temporary for performance reasons
      max_pages = 30
      limit = 30
      after = nil
      curr_page = 0
      package_roles = Role.system_package_roles.to_a

      # Revoke current roles on package (maybe explore a diff approach instead of wiping & recreating entire list?)
      current_roles = UserRole.where(role_id: package_roles.map(&:id)).where(target_type: "Package", target_id: package.id)
      current_roles.delete_all

      # Enumerate repository collaborators to give access to the package.
      # Since this result is paginated, keep looping through the list to get all collaborators till end_of_results is reached
      loop do
        direct_access_list = ::RepositoryAccessList.new(repository:, current_user: repository.owner, limit:, after:)
        curr_page += 1
        repository_roles = repository_roles(repository, direct_access_list)

        # Filter full access list to only users and teams
        users_and_teams = direct_access_list.results.to_a

        users_and_teams.each do |actor|
          case actor
          when User, Team
            current_roles_actor = UserRole.where(role_id: package_roles.map(&:id)).where(target_type: "Package", target_id: package.id, actor_id: actor.id)
            if current_roles_actor.nil?
              raise "current_roles cannot be nil"
            end
            if !current_roles_actor.empty?
              Role.system_package_roles.each do |package_role|
                Permissions::Granters::RoleGranter.new(
                  actor: actor,
                  target: self,
                  role: package_role
                ).revoke_if_exists!
              end
            end
            begin
              Permissions::Granters::RoleGranter.new(
                actor: actor,
                target: self,
                role: map_package_access_type(repository_roles.direct_role_for(actor))
              ).grant_unless_exists!
            rescue ActiveRecord::RecordInvalid => e
              unless e.message.include?("Actor has already been taken")
                puts "Couldn't sync role: #{e.message}"
                raise
              end
            end
          end
        end

        after = direct_access_list.after_cursor

        if after.nil? || direct_access_list.end_of_results? || curr_page > max_pages
          break
        end
      end
    end

    def can_edit_actions_package_sharing_policy?(actor)
      return false unless is_actions_package?(actor)
      return false if public?
      true
    end

    def sharing_policy_value(sharing_policy)
      case sharing_policy.upcase.to_sym
      when :SHARING_POLICY_ACCESSIBLE_SAME_BUSINESS
        ::Proto::RegistryMetadata::V1::ActionPackages::ActionPackageSharingPolicy::SHARING_POLICY_ACCESSIBLE_SAME_BUSINESS
      when :SHARING_POLICY_ACCESSIBLE_SAME_ORG
        ::Proto::RegistryMetadata::V1::ActionPackages::ActionPackageSharingPolicy::SHARING_POLICY_ACCESSIBLE_SAME_ORG
      when :SHARING_POLICY_ACCESSIBLE_SAME_USER
        ::Proto::RegistryMetadata::V1::ActionPackages::ActionPackageSharingPolicy::SHARING_POLICY_ACCESSIBLE_SAME_USER
      when :SHARING_POLICY_NONE
        ::Proto::RegistryMetadata::V1::ActionPackages::ActionPackageSharingPolicy::SHARING_POLICY_NONE
      else
        ::Proto::RegistryMetadata::V1::ActionPackages::ActionPackageSharingPolicy::SHARING_POLICY_UNKNOWN
      end
    end

    private

    def repository_roles(repository, access_list)
      ::RepositoryMemberRoles.fetch(
        repository:   repository,
        current_user: repository.owner,
        members:      access_list.user_results,
        teams:        access_list.repository_teams
      )
    end

    def map_package_access_type(repository_access_type)
      case repository_access_type
      when :read, :triage
        Role.package_reader_role
      when :write, :maintain
        Role.package_writer_role
      when :admin
        Role.package_admin_role
      else
        Role.package_reader_role
      end
    end
  end
end
