# typed: true
# frozen_string_literal: true

class Api::OrganizationRepositoryAdvisories < Api::App
  include Api::App::AdvisoryPaginationHelpers
  include Api::App::RepositoryAdvisoriesHelpers
  include GitHub::SecurityCenter::TenantFilteringHelper
  include FeatureFlagHelper


  get "/organizations/:organization_id/security-advisories", operation_id: "security-advisories/list-org-repository-advisories" do
    org = find_org!

    control_access :list_org_repository_advisories,
      resource: org,
      organization: org,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    ensure_non_conflicting_cursor_params!

    # If this is a request where the actor has programmatic granular
    # permissions (i.e: PAT v2, or GitHub Apps), filter the repositories before we send the request.
    programmatic_actor_grant = ProgrammaticActor::Grant.with(current_user).with_target(org)

    if GitHub.flipper[:private_advisories_disabled].enabled? || org.feature_enabled?(:private_advisories_disabled)
      innersource_repo_ids = []
      if AdvisoryDB::Innersource.org_authorized?(org:)
        innersource_repo_ids = org.private_repositories.
          not_archived_scope.
          select { |repo| repo.innersource_advisories_enabled? }.pluck(:id)
      end

      # If the request is made with a programmatic actor (e.g. PATv2 or GH Apps) and the actor cannot access all repos
      # in the org, only include the repos the actor can access.
      # If the request is made with an OAuth app or a legacy PAT and `repos` is part of the scope, we include all
      # innersource repos.
      # Otherwise, the user does not have any access to private repos.
      private_repo_ids = if programmatic_actor_grant
        programmatic_actor_grant.repository_ids(
          min_action: :read, resource: "repository_advisories", repository_ids: innersource_repo_ids
        )
      elsif scope?(current_user, "repo")
        innersource_repo_ids
      else
        []
      end

      # Ensure a programmatic actor has access to the public repos in the org.
      unfiltered_public_repo_ids = org.repositories.public_scope.pluck(:id)
      public_repo_ids = if programmatic_actor_grant
        programmatic_actor_grant.repository_ids(
          min_action: :read, resource: "repository_advisories", repository_ids: unfiltered_public_repo_ids
        )
      else
        unfiltered_public_repo_ids
      end

      repository_ids = public_repo_ids + private_repo_ids
      advisories = (RepositoryAdvisory.where(repository_id: public_repo_ids).open_source).or(
        RepositoryAdvisory.where(repository_id: private_repo_ids).innersource
      )
    else
      # If the request is made with a programmatic actor (i.e: PAT v2, or GitHub Apps) and the actor cannot access all
      # repos in the org, we find only the repos that the actor can access.
      # When the request is made with an OAuth app or a legacy PAT, and `repos` is not part of the scope, we find only public repos of the org.
      # Otherwise, we set `repository_ids` to all repos in the org.
      repository_ids = if programmatic_actor_grant && !programmatic_actor_grant.installed_on_all_repositories?(min_action: :read, resource: "repository_advisories")
        programmatic_actor_grant.repository_ids(min_action: :read, resource: "repository_advisories")
      elsif !scope?(current_user, "repo")
        org.repositories.public_scope.pluck(:id)
      else
        org.repositories.pluck(:id)
      end

      advisories = RepositoryAdvisory.where(repository_id: repository_ids)
    end

    # Bail out early if the programmatic actors don't have access to
    # any of the repositories in question. This check is mostly for
    # extra safety. It seems to be hard to run into this case normally.
    if programmatic_actor_grant && repository_ids.is_a?(Array) && repository_ids.empty?
      deliver_error! 404
    end

    state = params[:state]&.to_sym
    advisories = case state
    when :draft
      advisories.open_triaged
    when :triage
      advisories.open_untriaged
    when :published
      advisories.published
    when :closed
      advisories.closed
    when nil
      advisories
    else
      []
    end

    advisories = order_advisories(advisories)
    advisories_platform_relation = paginate_advisories(advisories, params)
    advisories = advisories_platform_relation.edge_nodes.sync
    set_cursor_based_pagination_headers(advisories_platform_relation) if advisories.any?

    scope = GitHub::SecurityCenter::TenantFilteringHelper::RequestScope.new(
      :organization,
      org,
      "repository_advisories"
    )
    filtered_advisories, _ = filter_tenant_rows(
      scope,
      advisories,
      -> (advisory) { advisory.repository_id }
    )

    deliver_advisories(filtered_advisories)
  rescue Platform::Errors::Cursor,
    Platform::Errors::ExcessivePagination,
    Platform::Errors::InvalidPagination => e

    deliver_error!(400, message: e.message)
  end
end
