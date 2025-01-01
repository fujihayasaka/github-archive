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

    hash.except!(:number) if exemption_request.request_type == SecretScanning::ExemptionConstants::CLOSURE_EXEMPTION_REQUEST_TYPE

    if exemption_request.request_type == CodeScanning::AlertDismissalService::EXEMPTION_REQUEST_TYPE
      # We internally store this information as "resolution" but externally always talk about reason
      resolution_symbol = T.let(T.must(Turboscan::Proto::ResultResolution.lookup(hash[:metadata]["resolution"].to_i)), Symbol)
      reason = GitHub::Turboscan.api_resolution_reason(resolution_symbol)
      hash[:metadata]["reason"] = reason
    end

    # Ensure we are only passing expected metadata
    hash[:metadata] = hash[:metadata]&.slice("label", "reason", "alert_title")
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
      :reviewer_comment,
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
