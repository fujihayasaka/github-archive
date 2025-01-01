# typed: true
# frozen_string_literal: true

module ProgrammaticActor
  module AuthorizationDetailsGrantable
    extend T::Sig
    extend T::Helpers

    include GitHub::Memoizer
    include ProgrammaticActor::PermissionGrantable

    abstract!

    AuthorizationDetailableTypes = T.type_alias do
      T.any(
        GlobalIntegrationInstallation,
        ScopedIntegrationInstallation,
        SiteScopedIntegrationInstallation
      )
    end

    module ClassMethods
      ActorClasses = T.type_alias do
        T.any(
          T.class_of(GlobalIntegrationInstallation),
          T.class_of(ScopedIntegrationInstallation),
          T.class_of(SiteScopedIntegrationInstallation),
        )
      end

      def actor_type
        T.bind(self, ActorClasses)

        name
      end
    end

    mixes_in_class_methods ClassMethods

    sig { returns(T::Boolean) }
    def authorization_details_applicable?
      return false if GitHub.flipper[:use_authorization_details_v2_on_codespaces].enabled?

      T.bind(self, AuthorizationDetailableTypes)
      self.authorization_details.present?
    end

    sig { overridable.returns(ScopedInstallations::AuthorizationDetails::Structs::V1) }
    memoize def authorization_details_struct
      T.bind(self, AuthorizationDetailableTypes)

      ScopedInstallations::AuthorizationDetails::Structs::V1.from_hash(
        self.authorization_details
      )
    end

    ######################################################################
    # Overrides ProgrammaticActor::PermissionGrantable#can_self_install? #
    ######################################################################
    sig { params(target: T.untyped).returns(T::Boolean) }
    def can_self_install?(target)
      case self
      when ScopedIntegrationInstallation
        # This keeps the existing behavior of the ScopedIntegrationInstallation.
        return false if self.parent.nil?
        T.must(self.parent).can_self_install?(target)
      when GlobalIntegrationInstallation
        return false if self.target != target

        resource_type = ScopedInstallations::AuthorizationDetails::ResourceType::Repository
        helper = ScopedInstallations::AuthorizationDetails::Helper.new(authorization_details_struct)

        helper.has_minimum_action?(type: resource_type, resource: "administration", min_action: :write)
      else
        super
      end
    end

    ###################################################################################
    # Overrides ProgrammaticActor::PermissionGrantable#installed_on_all_repositories? #
    ###################################################################################
    def installed_on_all_repositories?(min_action: :read, resource: nil)
      case self
      when ScopedIntegrationInstallation, SiteScopedIntegrationInstallation
        context = {
          ability_id: self.ability_id,
          ability_type: self.ability_type,
          created_at: self.created_at,
          updated_at: self.updated_at
        }

        case self
        when ScopedIntegrationInstallation
          context[:parent_id] = self.integration_installation_id
        end

        science "ad_installed_on_all_repositories" do |e|
          e.context(context)

          e.run_if { authorization_details_applicable? }

          e.use { super }

          e.try { candidate_installed_on_all_repositories?(min_action:, resource:) }
        end
      when GlobalIntegrationInstallation
        candidate_installed_on_all_repositories?(min_action: min_action, resource: resource)
      else
        false
      end
    end

    ###########################################################################################
    # Overrides ProgrammaticActor::PermissionGrantable#installed_on_individual_repository_ids #
    ###########################################################################################
    def installed_on_individual_repository_ids(min_action: :read, resource: nil, repository_ids: nil, organization: nil)
      case self
      when ScopedIntegrationInstallation
        science "ad_installed_on_individual_repository_ids" do |e|
          e.context({
            ability_id: self.ability_id,
            ability_type: self.ability_type,
            created_at: self.created_at,
            updated_at: self.updated_at,
            parent_id: self.integration_installation_id
          })

          e.run_if { authorization_details_applicable? }

          e.use { super }

          e.try { candidate_installed_on_individual_repository_ids(min_action:, resource:, repository_ids:, organization:) }

          e.compare do |control, candidate|
            control.sort == candidate.sort
          end
        end
      when GlobalIntegrationInstallation
        []
      else
        super
      end
    end

    #######################################################################
    # Overrides ProgrammaticActor::PermissionGrantable#permission_results #
    #######################################################################
    def permission_results
      case self
      when ScopedIntegrationInstallation, SiteScopedIntegrationInstallation
        context = {
          ability_id: self.ability_id,
          ability_type: self.ability_type,
          created_at: self.created_at,
          updated_at: self.updated_at,
        }

        case self
        when ScopedIntegrationInstallation
          context[:parent_id] = self.integration_installation_id
        end

        science "ad_permission_results" do |e|
          e.context(context)

          e.run_if { authorization_details_applicable? }

          e.use do
            permissions = Permission.where(
              actor_id: self.ability_id,
              actor_type: self.ability_type
            ).select(:subject_type, :action).distinct

            permissions.each_with_object({}) do |permission, memo|
              resource = permission.subject_type.split("/").last

              if memo.key?(resource)
                new_action = Permission.actions[permission.action]
                old_action = Permission.actions[memo[resource]]

                action = [T.must(old_action), T.must(new_action)].max
                action = T.must(Permission.actions.key(action)).to_sym

                memo[resource] = action
              else
                memo[resource] = permission.action.to_sym
              end
            end
          end

          e.try { candidate_permission_results }
        end
      when GlobalIntegrationInstallation
        candidate_permission_results
      else
        {}
      end
    end

    #######################################################################
    # Overrides ProgrammaticActor::PermissionGrantable#repositories_count #
    #######################################################################
    def repositories_count
      case self
      when ScopedIntegrationInstallation
        science "ad_repositories_count" do |e|
          e.context({
            ability_id: self.ability_id,
            ability_type: self.ability_type,
            created_at: self.created_at,
            updated_at: self.updated_at,
            parent_id: self.integration_installation_id
          })

          e.run_if { authorization_details_applicable? }

          e.use { super }

          e.try { candidate_repositories_count }
        end
      when GlobalIntegrationInstallation
        installed_on_all_repositories? ? super : 0
      else
        super
      end
    end

    private

    def candidate_installed_on_all_repositories?(min_action: :read, resource: nil)
      T.bind(self, T.any(GlobalIntegrationInstallation, ScopedIntegrationInstallation, SiteScopedIntegrationInstallation))

      GitHub.tracer.in_span("ProgrammaticActor::AuthorizationDetailsGrantable#installed_on_all_repositories?", kind: :internal) do |_span|
        return false if self.new_record?

        resource_type = ScopedInstallations::AuthorizationDetails::ResourceType::Repository

        return false unless authorization_details_struct.granted_access_on_all_subjects?(resource_type, resource, min_action: min_action)

        # We only need to check the 'parent' for scoped installations.
        return true unless self.is_a?(ScopedIntegrationInstallation)

        # Rely on the parent for determining repository access.
        T.must(parent).installed_on_all_repositories?(min_action:, resource:)
      end
    end

    def candidate_installed_on_individual_repository_ids(min_action: :read, resource: nil, repository_ids: nil, organization: nil)
      T.bind(self, ScopedIntegrationInstallation)

      GitHub.tracer.in_span("ProgrammaticActor::AuthorizationDetailsGrantable#installed_on_individual_repository_ids", kind: :internal) do |_span|
        resource_type = ScopedInstallations::AuthorizationDetails::ResourceType::Repository

        helper = ScopedInstallations::AuthorizationDetails::Helper.with(authorization_details_struct)
        return [] unless helper.has_minimum_action?(type: resource_type, resource:, min_action:)

        case authorization_details_struct.selection_for(resource_type)
        when ScopedInstallations::AuthorizationDetails::Selection::Parent
          # Only return repository ids here if the parent is installed on select repos.
          T.must(parent).installed_on_individual_repository_ids(min_action:, resource:, repository_ids:, organization:)
        when ScopedInstallations::AuthorizationDetails::Selection::Subset
          repo_subject_ids = authorization_details_struct.subject_ids_for(resource_type)
          next [] if repo_subject_ids.empty?

          # Filter out any repository_ids that weren't granted originally.
          if repository_ids.present?
            repo_subject_ids &= repository_ids

            # If we pass an empty array to the parent, if will return all
            # of the available repositories.
            next [] if repo_subject_ids.empty?
          end

          # Because we are limiting the repos manually, we always want to return
          # the repository ids the parent have access to here regardless of its
          # selection.
          T.must(parent).repository_ids(min_action:, resource:, repository_ids: repo_subject_ids, organization:)
        else
          []
        end
      end
    end

    def candidate_permission_results
      GitHub.tracer.in_span("ProgrammaticActor::AuthorizationDetailsGrantable#permission_results", kind: :internal) do |_span|

        case self
        when ScopedIntegrationInstallation
          all_permissions = authorization_details_struct.all_permissions.dup

          differ = ::PermissionsDiffer.new(
            previous_permissions: all_permissions,
            new_permissions: T.must(parent).get_cached_permissions
          )

          # If the parent has downgraded permissions, then the child should also
          # reflect that.
          differ.downgraded_permissions.each_pair do |resource, action|
            all_permissions[resource] = action
          end

          # If the parent has removed permissions, then the child should also have
          # those permissions removed.
          if differ.removed_permissions.any?
            all_permissions.delete(*differ.removed_permissions.keys)
          end

          all_permissions
        else
          authorization_details_struct.all_permissions
        end
      end
    end

    def candidate_repositories_count
      T.bind(self, ScopedIntegrationInstallation)

      GitHub.tracer.in_span("ProgrammaticActor::AuthorizationDetailsGrantable#repositories_count", kind: :internal) do |_span|
        resource_type = ScopedInstallations::AuthorizationDetails::ResourceType::Repository

        # Don't count if we don't have repository access.
        helper = ScopedInstallations::AuthorizationDetails::Helper.with(authorization_details_struct)
        return 0 unless helper.has_minimum_action?(type: resource_type, resource: nil, min_action: :read)

        case authorization_details_struct.selection_for(resource_type)
        when ScopedInstallations::AuthorizationDetails::Selection::Parent
          T.must(parent).repositories_count
        when ScopedInstallations::AuthorizationDetails::Selection::Subset
          repo_subject_ids = authorization_details_struct.subject_ids_for(resource_type)
          return 0 if repo_subject_ids.empty?

          fake_subject = Repository.new.resources.metadata

          if T.must(parent).installed_on_all_repositories?(min_action: :read, resource: fake_subject.ability_type)
            # We do not have to filter out workspace repositories because we
            # aren't able to grant them as a part of granting subset access.
            repositories_domain.repo_ids_by_owner_count(
              owner_id: target_id,
              public_only: false,
              repo_ids_in: repo_subject_ids
            )
          else
            Permission.where(
              actor_id: T.must(parent).ability_id,
              actor_type: T.must(parent).ability_type,
              subject_type: fake_subject.ability_type,
              subject_id: repo_subject_ids
            ).count
          end
        else
          0
        end
      end
    end
  end
end
