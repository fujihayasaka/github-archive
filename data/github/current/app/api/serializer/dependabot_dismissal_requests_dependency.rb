# typed: true
# frozen_string_literal: true

module Api::Serializer::DependabotDismissalRequestsDependency
  extend T::Helpers

  requires_ancestor { Api::Serializer }
  requires_ancestor { Api::Serializer::RepositoriesDependency }
  requires_ancestor { Api::Serializer::UserDependency }

  sig { params(dismissal_request: Exemptions::ExemptionRequest, options: T.untyped).returns(T::Hash[Symbol, T.untyped]) }
  def dependabot_dismissal_request_hash(dismissal_request, options = {})
    # strict loading of response.reviewer
    GitHub::PrefillAssociations.prefill_associations(dismissal_request, [:responses])
    responses = dismissal_request.responses.map do |response|
      {
        id: response.id,
        reviewer: {
          actor_id: response.reviewer&.id,
          actor_name: response.reviewer&.display_login,
        },
        message: response.message,
        status: response.status == "rejected" ? "denied" : response.status,
        created_at: response.created_at,
      }
    end

    data = dependabot_dismissal_request_data_hash(dismissal_request)
    repo = dismissal_request.repository
    org = repo&.organization

    hash = {
      id: dismissal_request.id,
      number: dismissal_request.number,
      repository: simple_repo_hash(repo),
      organization: simple_org_hash(org),
      requester: actor_hash(dismissal_request.requester),
      request_type: dismissal_request.request_type,
      data: data[:data],
      resource_identifier: dismissal_request.resource_identifier,
      status: determine_request_status(dismissal_request, false),
      requester_comment: dismissal_request.requester_comment,
      expires_at: dismissal_request.expires_at&.iso8601,
      created_at: dismissal_request.created_at&.iso8601,
      responses: responses,
      url: "#{GitHub.api_url}/repos/#{repo&.name_with_display_owner}/dismissal-requests/dependabot/#{dismissal_request.metadata["alert_number"]}",
      html_url: dismissal_request.permalink,
    }

    hash
  end

  private

  def dependabot_dismissal_request_data_hash(dismissal_request)
    data_hash = {
      reason: dismissal_request.metadata["reason"],
      alert_number: dismissal_request.metadata["alert_number"],
      alert_title: dismissal_request.metadata["alert_title"],
    }

    {
      type: Dependabot::SecurityProduct::DelegatedClosures::CLOSURE_EXEMPTION_REQUEST_TYPE,
      data: [data_hash],
    }
  end
end
