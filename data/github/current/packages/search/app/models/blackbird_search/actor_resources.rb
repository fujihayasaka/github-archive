# typed: true
# frozen_string_literal: true

module BlackbirdSearch
  class ActorResources
    extend T::Sig

    attr_reader :current_user, :cap_filter

    sig { params(current_user: T.any(User, Bot), cap_filter: T.untyped).void }
    def initialize(current_user:, cap_filter:)
      @current_user = current_user
      @cap_filter = cap_filter
    end

    # Public: List of organizations this user is authorized to access based on
    # their membership and all conditional access policies.
    #
    # Returns Array of Integer.
    def authorized_organization_ids
      @authorized_organization_ids ||= begin
        ActiveRecord::Base.connected_to(role: :reading) do
          org_ids = current_user.organizations.ids - protected_organization_ids
          org_ids.concat(Business::OrganizationMembership.where(business_id: accessible_business_ids).pluck(:organization_id))
          org_ids.uniq.sort
        end
      end
    end

    # Public: List of organizations to exclude from results based on whether
    # current the user does not meet any of the conditional access policies
    # (e.g. SAML policy or IP Allowlist policy)
    #
    # Returns Array of Organization.
    def protected_organizations
      # NB: :two_factor CAP excluded because it isn't shipped to production
      @protected_organizations ||= cap_filter.unauthorized_resources(current_user.organizations)
    end

    # Public: List of organization IDs to exclude from results based on whether
    # current the user does not meet any of the conditional access policies
    # (e.g. SAML policy or IP Allowlist policy)
    #
    # Returns Array of Integer.
    def protected_organization_ids
      protected_organizations.map(&:id)
    end

    # Public: List of owner IDs where this user is an outside collaborator on at least one repo. Should not overlap
    # with authorized_organization_ids or protected_organization_ids. May include both user and organization IDs.
    #
    # Returns Array of Integer.
    def outside_collaborator_owner_ids
      @outside_collaborator_owner_ids ||= begin
        ActiveRecord::Base.connected_to(role: :reading) do
          repository_ids = Authorization.service.subject_ids(actor: current_user, subject_type: "Repository")
          Repository
            .where(id: repository_ids)
            .where.not(owner_id: current_user.organizations.ids)
            .active
            .distinct
            .pluck(:owner_id)
        end
      end
    end

    def accessible_business_ids
      return [] unless current_user
      @accessible_business_ids ||= cap_filter.authorized_resource_ids(current_user.businesses)
    end

    # Private: List of repo ids to exclude from results based on
    # current user's external identities.
    def protected_repo_ids
      @protected_repo_ids ||= begin
        ActiveRecord::Base.connected_to(role: :reading) do
          ids = Repository.private_scope.where(owner_id: protected_organization_ids).ids

          if accessible_business_ids.any?
            ids.concat Repository.active.where(owner_id: protected_organization_ids)
              .joins(:internal_repository)
              .where("internal_repositories.business_id IN (?)", accessible_business_ids)
              .ids
          end

          ids.uniq
        end
      end
    end
  end
end
