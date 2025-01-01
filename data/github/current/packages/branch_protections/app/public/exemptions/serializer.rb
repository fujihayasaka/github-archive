# typed: strict
# frozen_string_literal: true

module Exemptions
  module Serializer
    extend T::Sig

    ExemptionRequestHash = T.type_alias do
      {
        id: Integer,
        number: Integer,
        repository_id: T.nilable(Integer),
        requester_id: Integer,
        requester_login: T.nilable(String),
        request_type: String,
        resource_owner_id: Integer,
        resource_owner_type: String,
        resource_identifier: T.nilable(String),
        status: T.any(Symbol, String),
        requester_comment: T.nilable(String),
        expires_at: Time,
        created_at: Time,
        metadata: T.nilable(T::Hash[String, T.untyped]),
        responses: T.nilable(T::Array[ExemptionResponseHash]),
      }
    end

    ExemptionResponseHash = T.type_alias do
      {
        id: Integer,
        reviewer_id: Integer,
        reviewer_login: String,
        status: T.any(Symbol, String),
        created_at: Time,
      }
    end

    sig { params(request: ExemptionRequest, include_responses: T.nilable(T::Boolean)).returns(ExemptionRequestHash) }
    def self.request_to_hash(request, include_responses: false)
      request_hash = T.let({
        id: T.must(request.id),
        number: T.must(request.number),
        repository_id: request.repository_id,
        requester_id: request.requester_id,
        requester_login: request.requester&.display_login,
        request_type: request.request_type,
        resource_owner_id: T.must(request.resource_owner_id),
        resource_owner_type: T.must(request.resource_owner_type),
        resource_identifier: T.must(request.resource_identifier),
        status: request.status,
        requester_comment: request.requester_comment,
        expires_at: T.must(request.expires_at).to_time,
        created_at: T.must(request.created_at).to_time,
        metadata: request.metadata,
        responses: nil,
      }, ExemptionRequestHash)
      request_hash[:responses] = request.responses.map do
        |response| response_to_hash(response)
      end if include_responses

      request_hash
    end

    sig { params(response: ExemptionResponse).returns(ExemptionResponseHash) }
    def self.response_to_hash(response)
      {
        id: T.must(response.id),
        reviewer_id: response.reviewer_id,
        reviewer_login: T.must(response.reviewer).display_login,
        status: response.status,
        created_at: T.must(response.created_at).to_time,
      }
    end
  end
end
