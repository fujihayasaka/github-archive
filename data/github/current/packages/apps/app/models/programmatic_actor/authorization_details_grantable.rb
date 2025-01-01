# typed: true
# frozen_string_literal: true

module ProgrammaticActor
  module AuthorizationDetailsGrantable
    extend T::Helpers

    include GitHub::Memoizer
    include ProgrammaticActor::PermissionGrantable
    include Repositories::Domain::Provider

    abstract!

    AuthorizationDetailableTypes = T.type_alias do
      T.any(
        GlobalIntegrationInstallation,
        ScopedIntegrationInstallation,
        SiteScopedIntegrationInstallation
      )
    end

    FALLBACK_PERMISSIONS_STATS_KEY = "programmatic_actor.authorization_details_grantable.fallback_to_permissions"

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
      T.bind(self, AuthorizationDetailableTypes)
      self.authorization_details.present?
    end

    sig { returns(T::Boolean) }
    def fallback_to_permissions?
      case self
      when GlobalIntegrationInstallation
        false
      else
        result = !authorization_details_applicable?
        GitHub.dogstats.increment(FALLBACK_PERMISSIONS_STATS_KEY, tags: ["result:#{result}", "type:#{self.class.name.underscore}"])

        result
      end
    end

    sig { overridable.returns(ScopedInstallations::AuthorizationDetails::PublicMethods) }
    def authorization_details_struct
      T.bind(self, AuthorizationDetailableTypes)
      ScopedInstallations::AuthorizationDetails::Builder.from_hash(self.authorization_details)
    end

    sig { overridable.returns(T::Array[Authzd::Proto::Attribute]) }
    def authzd_proto_attributes
      return [] unless authorization_details_applicable?
      authorization_details_struct.authzd_proto_attributes
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
      else
        return super if fallback_to_permissions?
        candidate_can_self_install?(target)
      end
    end

    ###################################################################################
    # Overrides ProgrammaticActor::PermissionGrantable#installed_on_all_repositories? #
    ###################################################################################
    def installed_on_all_repositories?(min_action: :read, resource: nil)
      return super if fallback_to_permissions?
      candidate_installed_on_all_repositories?(min_action:, resource:)
    end

    ###########################################################################################
    # Overrides ProgrammaticActor::PermissionGrantable#installed_on_individual_repository_ids #
    ###########################################################################################
    def installed_on_individual_repository_ids(min_action: :read, resource: nil, repository_ids: nil, organization: nil)
      return super if fallback_to_permissions?
      candidate_installed_on_individual_repository_ids(min_action:, resource:, repository_ids:, organization:)
    end

    def organization_ids(resource:)
      return super if fallback_to_permissions?
      ids = authorization_details_struct.granted_subject_ids_for(ScopedInstallations::AuthorizationDetails::ResourceType::Organization, resource)
      return ids if ids.empty? || !self.is_a?(ScopedIntegrationInstallation)

      ids & T.must(parent).organization_ids(resource:)
    end

    #######################################################################
    # Overrides ProgrammaticActor::PermissionGrantable#permission_results #
    #######################################################################
    def permission_results
      return super if fallback_to_permissions?
      candidate_permission_results
    end

    #######################################################################
    # Overrides ProgrammaticActor::PermissionGrantable#repositories_count #
    #######################################################################
    def repositories_count
      return super if fallback_to_permissions?
      return super if installed_on_all_repositories?

      candidate_repositories_count
    end

    private

    def candidate_can_self_install?(target)
      T.bind(self, T.any(GlobalIntegrationInstallation, SiteScopedIntegrationInstallation))

      return false if self.target != target

      resource_type = ScopedInstallations::AuthorizationDetails::ResourceType::Repository
      return true if authorization_details_struct.granted_access_on_all_subjects?(resource_type, "administration", min_action: :write)

      subject_ids = authorization_details_struct.granted_subject_ids_for(resource_type, "administration", min_action: :write)

      # In the case of Codespaces, we can grant repositories that are outside
      # of the target ownership. Therefore, we should check to make sure the
      # repos we have 'administration' access to are owned by the target.
      count =
        ActiveRecord::Base.connected_to(role: :reading) do
          repositories_domain.repo_ids_by_owner_count(
            owner_id: self.target_id,
            public_only: false,
            repo_ids_in: subject_ids
          )
        end

      count > 0
    end

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
      GitHub.tracer.in_span("ProgrammaticActor::AuthorizationDetailsGrantable#installed_on_individual_repository_ids", kind: :internal) do |_span|
        resource_type = ScopedInstallations::AuthorizationDetails::ResourceType::Repository

        case authorization_details_struct.selection_for(resource_type)
        when ScopedInstallations::AuthorizationDetails::Selection::Parent
          return [] unless self.is_a?(ScopedIntegrationInstallation)

          helper = ScopedInstallations::AuthorizationDetails::Helper.with(authorization_details_struct)
          return [] unless helper.has_minimum_action?(resource_type:, resource:, min_action:)

          # Only return repository ids here if the parent is installed on select repos.
          T.must(parent).installed_on_individual_repository_ids(min_action:, resource:, repository_ids:, organization:)
        else
          repo_subject_ids = authorization_details_struct.granted_subject_ids_for(resource_type, resource, min_action:)

          return [] if repo_subject_ids.empty?

          # Filter out any repository_ids that weren't granted originally.
          if repository_ids.present?
            repo_subject_ids &= repository_ids

            # If we pass an empty array to the parent, if will return all
            # of the available repositories.
            return [] if repo_subject_ids.empty?
          end

          return repo_subject_ids unless self.is_a?(ScopedIntegrationInstallation)

          # Because we are limiting the repos manually, we always want to return
          # the repository ids the parent have access to here regardless of its
          # selection.
          T.must(parent).repository_ids(min_action:, resource:, repository_ids: repo_subject_ids, organization:)
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
            new_permissions: T.must(parent).permission_results
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
      GitHub.tracer.in_span("ProgrammaticActor::AuthorizationDetailsGrantable#repositories_count", kind: :internal) do |_span|
        resource_type = ScopedInstallations::AuthorizationDetails::ResourceType::Repository

        # Don't count if we don't have repository access.
        helper = ScopedInstallations::AuthorizationDetails::Helper.with(authorization_details_struct)
        return 0 unless helper.has_minimum_action?(resource_type:, resource: nil, min_action: :read)

        case authorization_details_struct.selection_for(resource_type)
        when ScopedInstallations::AuthorizationDetails::Selection::Parent
          return 0 unless self.is_a?(ScopedIntegrationInstallation)

          T.must(parent).repositories_count
        when ScopedInstallations::AuthorizationDetails::Selection::Subset
          fake_subject = Repository.new.resources.metadata
          repo_subject_ids = authorization_details_struct.granted_subject_ids_for(
            resource_type, fake_subject.name,
            min_action: :read
          )
          return 0 if repo_subject_ids.empty?
          return repo_subject_ids.size unless self.is_a?(ScopedIntegrationInstallation)

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
