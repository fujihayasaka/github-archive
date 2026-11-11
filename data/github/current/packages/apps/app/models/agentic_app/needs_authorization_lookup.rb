# typed: true
# frozen_string_literal: true

require "set"

class AgenticApp::NeedsAuthorizationLookup
  sig { params(user: T.nilable(User), integration_ids: T::Enumerable[Integer]).returns(T::Set[Integer]) }
  def self.for_integration_ids(user:, integration_ids:)
    return Set.new unless user

    candidate_integration_ids = integration_ids.uniq
    return Set.new if candidate_integration_ids.empty?

    callback_integration_ids = ApplicationCallbackUrl
      .where(application_type: OauthAuthorization::INTEGRATION, application_id: candidate_integration_ids)
      .distinct
      .pluck(:application_id)

    return Set.new if callback_integration_ids.empty?

    oauth_integration_ids = Integration
      .where(id: callback_integration_ids, request_oauth_on_install: true)
      .pluck(:id)

    return Set.new if oauth_integration_ids.empty?

    authorized_integration_ids = user.oauth_authorizations
      .where(application_id: oauth_integration_ids, application_type: OauthAuthorization::INTEGRATION)
      .pluck(:application_id)

    Set.new(oauth_integration_ids).subtract(authorized_integration_ids)
  end
end
