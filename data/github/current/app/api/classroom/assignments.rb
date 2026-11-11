# typed: true
# frozen_string_literal: true

require "cache_key_logging_denylist"

class Api::Classroom::Assignments < Api::App
  include ReceiveSchemaWithOpenApi

  # List repositories for the authenticated user.
  get "/classroom/user/assignments", operation_id: "classroom/list-user-assignments" do
    control_access :list_repos,
      resource: current_user,
      challenge: true,
      allow_integrations: false,
      allow_user_via_granular_actor: true

    GitHub.dogstats.time "classroom", tags: ["action:user_assignments"] do
      unauthorized_org_ids = cap_filter.unauthorized_resource_ids(current_user&.organizations)
      unauthorized_sso_org_ids = cap_filter.unauthorized_resource_ids(current_user&.organizations, only: :saml)
      affiliations = [:owned, :direct, :indirect]

      include_org_owned_repos = access_allowed?(:list_associated_public_org_owned_repos,
                                               resource: current_user,
                                               allow_integrations: false,
                                               allow_user_via_granular_actor: true)

      # rubocop:todo GitHub/DontCallAssociatedRepositoryIdsUnbounded
      associated_repository_ids = current_user.associated_repository_ids(including: affiliations, include_indirect_forks: false)
      # rubocop:enable GitHub/DontCallAssociatedRepositoryIdsUnbounded
      repository_with_classroom_ids = ClassroomRepository.where(repository_id: associated_repository_ids).pluck(:repository_id)
      scope = Repository.where(ActiveRecord::Base.sanitize_sql(["repositories.id IN (?)", repository_with_classroom_ids]))

      if include_org_owned_repos
        if unauthorized_org_ids.any?
          set_sso_partial_results_header(unauthorized_sso_org_ids) if unauthorized_sso_org_ids.any?
          scope = scope.where("repositories.organization_id NOT IN (?) OR repositories.organization_id IS NULL", unauthorized_org_ids)
        end
      else
        scope = scope.user_owned
      end

      if ProgrammaticActor::RepositoryFilter.applicable?(current_user)
        private_repo_ids = scope.private_scope.pluck(:id)

        accessible_repo_ids = ProgrammaticActor::RepositoryFilter.perform(
          actor: current_user, repository_ids: private_repo_ids
        )

        scope = scope.public_scope.or(scope.where(id: accessible_repo_ids))
      elsif !access_allowed?(:list_private_repos, resource: current_user, allow_integrations: false, allow_user_via_granular_actor: false)
        scope = scope.public_scope
      end

      repos = scope.pluck(:id).paginate(pagination)

      repo_records = Repository.where(id: repos).index_by(&:id)
      repos.replace(repos.map { |id| repo_records[id] }.compact)

      Repository.prefill_associations(repos)

      deliver :classroom_repository_hash, repos
    end
  end
end
