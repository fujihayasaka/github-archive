# typed: true
# frozen_string_literal: true

class Api::UserHovercards < Api::App

  HovercardQuery = PlatformClient.parse <<-'GRAPHQL'
    query($userId: ID!, $primarySubjectId: ID) {
      node(id: $userId) {
        ... on User {
          hovercard(primarySubjectId: $primarySubjectId) {
            organization {
              databaseId
            }
            ...Api::Serializer::UserDependency::HovercardFragment
          }
        }
      }
    }
  GRAPHQL

  # Get the information contained in a user hovercard
  get "/user/:user_id/hovercard", operation_id: "users/get-context-for-user" do
    user = find_user!
    deliver_error!(404) if user.bot? || user.organization?

    subject = nil
    if params[:subject_id]
      subject = Hovercard::SUBJECT_PREFIX_MAP[params[:subject_type]]&.find_by_id(params[:subject_id]) # domain-isolation-query-violation:ignore:packages/issues (SELECT)
      record_or_404(subject)
    end

    results = platform_execute(HovercardQuery, variables: {
      userId: user.global_relay_id,
      primarySubjectId: subject&.global_relay_id,
    })

    # For OAuth application policy enforcement
    if results.errors.none? && org = results.data.node&.hovercard&.organization
      @current_org = Organization.find(org.database_id)
    end

    control_access :read_user_hovercard, {
      resource: user,
      challenge: true,
      allow_integrations: false,
      allow_user_via_granular_actor: false,
      enforce_oauth_app_policy: true,
    }

    if results.errors.all.any?
      deprecated_deliver_graphql_error(errors: results.errors.all, resource: "User", documentation_url: @documentation_url)
    else
      deliver :graphql_hovercard_hash, results.data.node.hovercard
    end
  end
end
