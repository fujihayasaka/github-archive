# typed: true # rubocop:todo Sorbet/StrictSigil
# frozen_string_literal: true

module Codespaces
  module DevContainerConfig
    class Codespaces

      MANDATORY_PERMISSIONS = %w(metadata).freeze

      # `all_repository_permissions` returns a hash of all permissions for all repositories. ex: { contents: :read, issues: :read }
      # `repository_permissions` returns a hash of permissions for specific repositories. ex: { repository_instance: { contents: :read, issues: :read } }
      # `unknown_repository_permissions` returns a hash of permissions for repos that the user doesn't have access to or doesn't exist. ex: { "codespaces/codespaces": { contents: :read, issues: :read } }
      # `errors` is an array of errors that occurred during parsing
      attr_reader :source_repository, :all_repository_permissions, :unvalidated_permissions, :errors, :user, :unknown_repository_permissions, :is_prebuild

      def initialize(source_repository:, all_repository_permissions:, unvalidated_permissions:, errors:, user:, unknown_repository_permissions: {}, is_prebuild: false)
        @source_repository = source_repository
        @all_repository_permissions = all_repository_permissions
        @unvalidated_permissions = unvalidated_permissions
        @repository_permissions = {}
        @unknown_repository_permissions = unknown_repository_permissions
        @errors = errors
        @user = user
        @is_prebuild = is_prebuild
      end

      # Designated constructor which creates the instance and verifies the permissions.
      def self.build(**kwargs)
        T.unsafe(self).new(**kwargs).tap(&:validate_repository_permissions)
      end

      def repository_permissions
        raise "You must call validate_repository_permissions_for_user before calling repository_permissions" unless @validated
        @repository_permissions
      end

      def has_custom_permissions?
        unvalidated_permissions.any? || @all_repository_permissions.any?
      end

      def self.from_hash(source_repository, user, h, is_prebuild: false)
        return build(
          source_repository: source_repository,
          all_repository_permissions: {},
          unvalidated_permissions: {},
          errors: [],
          user: user,
          is_prebuild: is_prebuild
        ) unless h
        all_repository_permissions = {}
        repository_permissions = {}
        unknown_repository_permissions = {}
        errors = []

        Array(h["repositories"]).map do |r|
          begin
            # The repo here is not the model instance, it is the Repository subclass defined in this file that is created from the parsed JSON
            # so nwo, owner, etc are not the database fields, they are the user inputed values.
            repo = Repository.from_hash(r, user)
            next unless repo&.permissions&.any?

            # check to make sure all owners are the same
            if source_repository.owner.display_login.downcase != repo.owner.downcase
              unknown_repository_permissions[repo.nwo] = repo.permissions #rubocop:disable GitHub/DoNotAllowNameWithOwner this is not an active record model Repository see comment above on L:57
              next
            end

            if repo.glob? #org/* all repos case
              if all_repository_permissions.empty?
                owner = User.find_by_login(repo.owner)

                if owner.present? && repo.permissions.all? { |_resource, action| Repository::ALLOWED_ALL_PERMS.values.include?(action) }
                  all_repository_permissions[owner] = repo.permissions #rubocop:disable GitHub/DoNotAllowNameWithOwner this is not an active record model Repository see comment above on L:57
                else
                  unknown_repository_permissions[repo.nwo] = repo.permissions #rubocop:disable GitHub/DoNotAllowNameWithOwner this is not an active record model Repository see comment above on L:57
                end
              else
                raise ::Codespaces::DevContainer::ParseError.new("All repositories can only be configured once")
              end
            else
              repository_permissions[repo.nwo] = repo.permissions #rubocop:disable GitHub/DoNotAllowNameWithOwner this is not an active record model Repository see comment above on L:57
            end
          rescue ::Codespaces::DevContainer::ParseError => e
            errors << e
            next
          end
        end

        build(
          source_repository: source_repository,
          all_repository_permissions: all_repository_permissions,
          unvalidated_permissions: repository_permissions,
          unknown_repository_permissions: unknown_repository_permissions,
          errors: errors,
          user: user,
          is_prebuild: is_prebuild
        )
      end

      def validate_repository_permissions
        if @is_prebuild
          validate_repository_permissions_for_prebuild
        else
          validate_repository_permissions_for_user
        end
      end

      def validate_repository_permissions_for_prebuild
        return true if @validated

        repositories = fetch_repositories

        @validated = false

        promises = []
        unvalidated_permissions.each do |nwo, permissions|
          repo = repositories[nwo]

          permissions.each do |resource, action|
            # when called from the CreatPrebuildTemplateDynamicWorkflowJob user will be nil
            if user.nil? || !FeatureFlag.vexi.enabled_or_raise?(:codespaces_prebuild_admin_repo_access, @source_repository) # rubocop:disable GitHub/FeatureManagement/NoVexiEnabledOrRaiseUsage
              add_permissions_to_lists(repo: repo, resource: resource, action: action, nwo: nwo)
            else
              promises.push(async_user_can?(action, resource, repo).then do |can|
                add_permissions_to_lists(repo: repo, resource: resource, action: action, nwo: nwo, can: can)
              end)
            end
          end
        end
        Promise.all(promises).sync

        @validated = true
      end

      def add_permissions_to_lists(repo:, resource:, action:, nwo:, can: true)
        if can && !Permissions::ResourceRegistry.writeonly_subject_type?(resource)
          @repository_permissions[repo] ||= {}
          # Downgrade all prebuild permissions to read
          @repository_permissions[repo][resource] = "read"
        else
          # prebuild configuration or user does not have authorization
          # @unknown_repository_permissions is the list of permissions that the current user does not have access to
          # during the prebuild creation these permissions will be displayed as "unavailable"
          @unknown_repository_permissions[nwo] ||= {}
          @unknown_repository_permissions[nwo][resource] = action unless MANDATORY_PERMISSIONS.include?(resource)
        end
      end

      def validate_repository_permissions_for_user
        raise ArgumentError, "Cannot validate permissions without a user" unless user

        return true if @validated

        repositories = fetch_repositories

        @validated = false

        promises = []
        unvalidated_permissions.each do |nwo, permissions|
          repo = repositories[nwo]

          permissions.each do |resource, action|
            promises.push(async_user_can?(action, resource, repo).then do |can|
              if can
                @repository_permissions[repo] ||= {}
                @repository_permissions[repo][resource] = action
              else # User does not have authorization
                @unknown_repository_permissions[nwo] ||= {}
                @unknown_repository_permissions[nwo][resource] = action unless MANDATORY_PERMISSIONS.include?(resource)
              end
            end)
          end
        end
        Promise.all(promises).sync

        @validated = true
      end

      def fetch_repositories
        return {} if unvalidated_permissions.empty?
        # lookup actual repo objects from db in batch and add to hash by nwo
        ::Repository.with_names_with_owners(unvalidated_permissions.keys).each_with_object(GitHub::Migrator::CaseInsensitiveHash.new) do |repo, hash|
          hash[repo.name_with_display_owner] = repo
        end
      end

      # diff_allowed_permissions returns a PermissionsDiff that keeps track of
      # the differences in requested permissions vs. records in the database
      def diff_allowed_permissions(permissions:, prebuild_configuration_id: nil)
        GitHub.tracer.in_span("codespaces#diff_allowed_permissions", kind: :internal) do
          GitHub.dogstats.distribution_time("codespaces.dev_container.latency", tags: ["action:diff_allowed_permissions"]) do
            unconsented = {}
            consented = {}
            revoked = {} # revoked in this case is permissions that have been previously consented (are in the DB) but are no longer being requested

            if @is_prebuild
              existing_consent_records = ::Codespaces::AllowedPermission.includes(:target).where(repository: source_repository, is_prebuild: @is_prebuild, codespace_prebuild_configuration_id: prebuild_configuration_id)
            else
              existing_consent_records = ::Codespaces::AllowedPermission.includes(:target).where(user: @user, repository: source_repository, is_prebuild: @is_prebuild)
            end

            existing_consent = existing_consent_records.group_by(&:target).without(nil)
            permissions.each do |target, target_permissions|
              existing_perms = existing_consent.delete(target)

              MANDATORY_PERMISSIONS.each do |mandatory_permission|
                target_permissions[mandatory_permission] ||= "read"
              end

              target_permissions.each do |resource, action|
                if existing_perms&.any? { |p| p.resource == resource && p.action == action }
                  consented[target] ||= {}
                  consented[target][resource] = action
                else
                  unconsented[target] ||= {}
                  unconsented[target][resource] = action
                end
              end

              existing_perms&.each do |p|
                unless target_permissions.any? { |resource, action| resource == p.resource && action == p.action }
                  revoked[target] ||= {}
                  revoked[target][p.resource] = p.action
                end
              end
            end

            # requested is all permissions that are being requested, previously consented or otherwise
            requested = consented.deep_merge(unconsented)
            # Add any permissions from targets that were completely removed
            removed_targets = existing_consent.transform_values do |permissions|
              permissions.map { |p| { p.resource => p.action } }.reduce({}, &:merge)
            end
            revoked = revoked.deep_merge(removed_targets)

            PermissionsDiff.new(consented: consented, unconsented: unconsented, requested: requested, revoked: revoked)
          end
        end
      end

      private

      def user_can?(action, resource, repo)
        repo &&
          Repository::PERMITTED_ACTIONS.include?(action) &&
          repo.resources.send(resource.to_s.underscore)&.permit?(user, action)
      end

      def async_user_can?(action, resource, repo)
        repo &&
          Repository::PERMITTED_ACTIONS.include?(action) &&
          repo.resources.send(resource.to_s.underscore)&.async_permit?(user, action)
      end

      class PermissionsDiff
        attr_reader :consented, :unconsented, :requested, :revoked

        def initialize(consented: {}, unconsented: {}, requested: {}, revoked: {})
          # consented permissions are requested in the devcontainer.json and are already in the bookkeeping table
          @consented = consented
          # unconsented permissions are requested in devcontainer.json but not written into the bookkeeping table
          @unconsented = unconsented
          # requested permisssions are the combination of previously consented and unconsented permissions; what should be written on authorization
          @requested = requested
          # revoked permissions are no longer being requested in devcontainer.json but are still in the bookkeeping table
          @revoked = revoked
        end

        def any_permissions?
          @consented.any? || @unconsented.any? || @requested.any? || @revoked.any?
        end

        def only_revoked_permissions?
          @revoked.any? && @consented.none? && @unconsented.none? && @requested.none?
        end
      end

      class Repository
        attr_reader :owner, :name, :permissions

        def initialize(owner, name, permissions)
          @owner = owner || ""
          @name = name || ""
          @permissions = permissions || {}
        end

        def name_with_owner
          "#{owner}/#{name}" #rubocop:disable GitHub/DoNotAllowLogin this is not an active record model Repository see comment above on L:57
        end
        alias_method :nwo, :name_with_owner

        def glob?
          name == "*"
        end

        PERMITTED_ACTIONS = %w[
          read
          write
        ].freeze

        ALLOWED_ALL_PERMS = {
          "read-all" => "read",
          "write-all" => "write",
        }.freeze

        ALLOWED_ALL_SUBJECTS = %w[
          actions
          checks
          contents
          deployments
          discussions
          issues
          packages
          pages
          pull_requests
          repository_projects
          statuses
          workflows
        ].freeze

        def self.from_hash(h, user)
          return nil unless h

          if h.is_a?(Hash)
            nwo = h["name"]
            repo_config = h
          else
            nwo, repo_config = h
          end
          return nil unless nwo

          owner, name = nwo.split("/", 2)

          raise ::Codespaces::DevContainer::ParseError.new("'#{nwo}' is not a valid repository name") unless owner && name
          raise ::Codespaces::DevContainer::ParseError.new("Repository '#{nwo}' cannot have empty permissions") unless repo_config&.fetch("permissions", nil)&.present?

          permissions = map_permissions(nwo, repo_config["permissions"], user)

          new(owner, name, permissions)
        end

        def self.map_permissions(nwo, permissions, user)
          return {} if permissions.empty?
          allowed_subjects = ALLOWED_ALL_SUBJECTS
          valid = case permissions
          when Hash # fine grained permissions ex: { "contents": "read", "issues": "read" }
            # replace - with _ in user provided resource names
            permissions = permissions.transform_keys { |resource| resource.gsub("-", "_") }

            # Remove permissions with unrecognized subjects
            permissions = ::Repository::Resources.filter(permissions)

            # Remove permissions with invalid actions or not allowed subject
            permissions.delete_if do |subject, action|
              (action == "write" && ::Repository::Resources::READONLY_SUBJECT_TYPES.include?(subject)) ||
                (action == "read" && ::Repository::Resources::WRITEONLY_SUBJECT_TYPES.include?(subject)) ||
                !allowed_subjects.include?(subject)
            end

            # If any requested permissions remain, add mandatory permissions
            if permissions.any?
              MANDATORY_PERMISSIONS.each do |mandatory_permission|
                permissions[mandatory_permission] ||= "read"
              end
            end

            permissions
          when String # write-all | read-all
            selected = ALLOWED_ALL_PERMS.fetch(permissions.downcase.strip, nil)

            allowed_subjects.each_with_object({}) do |subject_type, hash|
              hash[subject_type] = selected
            end if selected
          end

          raise ::Codespaces::DevContainer::ParseError.new("Repository '#{nwo}' has invalid permissions") unless valid
          valid
        end

        private_class_method :map_permissions
      end
    end
  end
end
