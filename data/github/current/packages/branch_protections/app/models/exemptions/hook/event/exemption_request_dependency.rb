# typed: strict
# frozen_string_literal: true

module Exemptions::Hook::Event::ExemptionRequestDependency
  extend T::Helpers
  include GitHub::Memoizer

  requires_ancestor { ::Hook::Event }

  RESPONSE_EVENTS = T.let(%w(response_submitted response_dismissed).freeze, T::Array[String])

  sig { returns(T.nilable(Exemptions::ExemptionRequest)) }
  memoize def exemption_request
    T.bind(self, Exemptions::Types::ExemptionRequestEvent)
    Exemptions::ExemptionRequest.find_by(id: exemption_request_id)
  end

  sig { returns(T.nilable(Exemptions::ExemptionResponse)) }
  memoize def exemption_response
    T.bind(self, Exemptions::Types::ExemptionRequestEvent)
    # Exemption response is only present when coming from a response event
    return nil unless RESPONSE_EVENTS.include?(action.to_s)
    Exemptions::ExemptionResponse.find_by(id: exemption_response_id)
  end

  sig { returns(T.nilable(Repository)) }
  def target_repository
    exemption_request&.repository
  end

  sig { returns(T.nilable(Organization)) }
  def target_organization
    exemption_request&.repository&.organization
  end

  # If there is a response, then the webhook is for a response related event
  # If there is no response, then we are looking at a request related event
  sig { returns(T.nilable(User)) }
  def actor
    T.bind(self, Exemptions::Types::ExemptionRequestEvent)

    exemption_response&.reviewer || exemption_request&.requester
  end

  sig { returns(T::Boolean) }
  def deliverable?
    target_repository.present? || target_organization.present?
  end
end
