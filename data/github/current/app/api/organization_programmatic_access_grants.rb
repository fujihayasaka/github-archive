# typed: true
# frozen_string_literal: true

class Api::OrganizationProgrammaticAccessGrants < Api::App
  include Api::App::PersonalAccessTokensHelper

  get "/organizations/:organization_id/personal-access-tokens", operation_id: "orgs/list-pat-grants" do
    org = find_org!
    ensure_api_enabled_for_org!(org)

    control_access :read_org_pats,
      resource: org,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    # We need this to validate the query params
    receive_with_openapi

    filters = fetch_filters(org)
    return deliver :org_pat_grant_hash, [] if filters.values.any?(&:blank?)

    paginated_grants = ProgrammaticAccessGrant
      .with_target_and_filters(org, filters)
      .then { |relation| sort_pats(relation) }
      .then { |sorted| paginate_rel(sorted) }

    GitHub::PrefillAssociations.prefill_associations(
      paginated_grants, [{ user_programmatic_access: :owner }]
    )

    deliver :org_pat_grant_hash, paginated_grants
  end

  post "/organizations/:organization_id/personal-access-tokens/:pat_id", operation_id: "orgs/update-pat-access" do
    org = find_org!
    ensure_api_enabled_for_org!(org)

    control_access :write_org_pats,
      resource: org,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    grant = ProgrammaticAccessGrant.from_target_and_id(org, params[:pat_id])
    record_or_404(grant)

    receive_with_openapi

    result = ProgrammaticAccessGrant.revoke(grant, current_user)

    if result.errors.any?
      deliver_error! 500, message: "Something went wrong"
    else
      deliver_empty status: 204
    end
  end

  post "/organizations/:organization_id/personal-access-tokens", operation_id: "orgs/update-pat-accesses" do
    org = find_org!
    ensure_api_enabled_for_org!(org)

    control_access :write_org_pats,
      resource: org,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    grant_ids = receive_with_openapi["pat_ids"]

    result = ProgrammaticAccessGrant.bulk_revoke(grant_ids, current_user, org)

    if result.errors.any?
      if result.errors.include?(:grants)
        deliver_error! 422, message: "One or more personal access tokens do not belong to the organization."
      else
        deliver_error! 500, message: "Something went wrong"
      end
    else
      deliver_empty status: 202
    end
  end

  get "/organizations/:organization_id/personal-access-tokens/:pat_id/repositories", operation_id: "orgs/list-pat-grant-repositories" do
    org = find_org!
    ensure_api_enabled_for_org!(org)

    control_access :read_org_pats,
      resource: org,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    grant = ProgrammaticAccessGrant.from_target_and_id(org, params[:pat_id])
    record_or_404(grant)

    paginated_repositories = paginate_rel(grant.repositories)
    Repository.prefill_associations(paginated_repositories)

    deliver :simple_repository_hash, paginated_repositories
  end
end
