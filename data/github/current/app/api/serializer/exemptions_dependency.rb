# typed: true
# frozen_string_literal: true

module Api::Serializer::ExemptionsDependency

  sig { params(exemption_request: Exemptions::ExemptionRequest, options: T::Hash[Symbol, T.untyped]).returns(T::Hash[Symbol, T.untyped]) }
  def exemption_request_hash(exemption_request, options = {})
    hash = Exemptions::Serializer.request_to_hash(exemption_request, include_responses: true).slice(
      :id,
      :number,
      :repository_id,
      :requester_id,
      :requester_login,
      :request_type,
      :status,
      :requester_comment,
      :metadata,
      :expires_at,
      :created_at,
      :responses,
    )

    # Ensure we are only passing expected metadata
    hash[:metadata] = hash[:metadata]&.slice("label", "reason")
    hash[:exemption_request_data] = exemption_request_data_hash(exemption_request, options)
    hash[:html_url] = exemption_request.permalink
    hash
  end

  sig { params(exemption_response: Exemptions::ExemptionResponse, options: T::Hash[Symbol, T.untyped]).returns(T::Hash[Symbol, T.untyped]) }
  def exemption_response_hash(exemption_response, options = {})
    Exemptions::Serializer.response_to_hash(exemption_response).slice(
      :id,
      :reviewer_id,
      :reviewer_login,
      :status,
      :created_at
    )
  end

  sig { params(exemption_request: Exemptions::ExemptionRequest, options: T::Hash[Symbol, T.untyped]).returns(Exemptions::Types::ExemptionRequestDataHash) }
  def exemption_request_data_hash(exemption_request, options = {})
    hash = exemption_request.exemption_data_hash || {}
    {
      type: hash[:type],
      data: hash[:data]
    }
  end
end
