# typed: true
# frozen_string_literal: true

class Api::OrganizationProgrammaticAccessGrantRequests < Api::App
  include Api::App::PersonalAccessTokensHelper

  get "/organizations/:organization_id/personal-access-token-requests", operation_id: "orgs/list-pat-grant-requests" do
    org = find_org!
    ensure_api_enabled_for_org!(org)

    control_access :read_org_pat_requests,
      resource: org,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    # We need this to validate the query params
    receive_with_openapi

    filters = fetch_filters(org)
    return deliver :org_pat_grant_request_hash, [] if filters.values.any?(&:blank?)

    paginated_requests = ProgrammaticAccessGrantRequest
      .with_target_and_filters(org, filters)
      .then { |relation| sort_pats(relation) }
      .then { |sorted| paginate_rel(sorted) }

    GitHub::PrefillAssociations.prefill_associations(
      paginated_requests, [{ user_programmatic_access: :owner }]
    )

    deliver :org_pat_grant_request_hash, paginated_requests
  end

  post "/organizations/:organization_id/personal-access-token-requests", operation_id: "orgs/review-pat-grant-requests-in-bulk" do
    org = find_org!
    ensure_api_enabled_for_org!(org)

    control_access :write_org_pat_requests,
      resource: org,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    action, pat_request_ids = receive_with_openapi.values_at("action", "pat_request_ids")
    ensure_all_requests_belong_to_org!(org, pat_request_ids)

    case action
    when "approve"
      ProgrammaticAccessGrantRequest.bulk_approve(pat_request_ids, current_user, org, entry_point: :rest_api_orgs_review_pat_grant_requests_in_bulk)
    when "deny"
      ProgrammaticAccessGrantRequest.bulk_deny(pat_request_ids, current_user, org)
    end

    deliver_empty status: 202
  end

  get "/organizations/:organization_id/personal-access-token-requests/:pat_request_id/repositories", operation_id: "orgs/list-pat-grant-request-repositories" do
    org = find_org!
    ensure_api_enabled_for_org!(org)

    control_access :read_org_pat_requests,
      resource: org,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    pat_request = ProgrammaticAccessGrantRequest
      .with_target(org)
      .find_by_id(params[:pat_request_id])

    record_or_404(pat_request)

    paginated_repositories = paginate_rel(pat_request.repositories)
    Repository.prefill_associations(paginated_repositories)

    deliver :simple_repository_hash, paginated_repositories
  end

  post "/organizations/:organization_id/personal-access-token-requests/:pat_request_id", operation_id: "orgs/review-pat-grant-request" do
    org = find_org!
    ensure_api_enabled_for_org!(org)

    control_access :write_org_pat_requests,
      resource: org,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    pat_request = ProgrammaticAccessGrantRequest
      .with_target(org)
      .find_by_id(params[:pat_request_id])

    record_or_404(pat_request)

    action, reason = receive_with_openapi.values_at("action", "reason")

    grantable =
      case action
      when "approve"
        ProgrammaticAccessGrantRequest.approve(pat_request, current_user, entry_point: :rest_api_orgs_review_pat_grant_request)
      when "deny"
        ProgrammaticAccessGrantRequest.deny(pat_request, current_user, reason)
      end

    if grantable.errors.any?
      deliver_error! 500, message: "Something went wrong"
    else
      deliver_empty status: 204
    end
  end

  private

  def ensure_all_requests_belong_to_org!(org, pat_request_ids)
    unique_request_ids = pat_request_ids.uniq
    request_targeting_org = ProgrammaticAccessGrantRequest.from_target_and_ids(org, pat_request_ids)

    if unique_request_ids.count != request_targeting_org.count
      deliver_error! 422, message: "All requests must belong to the organization"
    end
  end
end
