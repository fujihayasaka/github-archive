# typed: strict
# frozen_string_literal: true

module Exemptions
  module Public

    sig do
      params(
        repository_id: Integer,
        actor_id: Integer,
        response_status: String
      ).returns(T::Array[Exemptions::Serializer::ExemptionResponseHash])
    end
    def self.responses_for_repository(repository_id, actor_id, response_status)
      responses = Exemptions::ExemptionResponse
        .where(status: response_status)
        .joins(:exemption_request)
      responses = responses.where.not(exemption_request: {
        status: "rejected"
      }) if response_status != "rejected"
      responses = responses.where(exemption_request: {
          repository_id:,
          requester_id: actor_id,
          expires_at: Time.now..,
        })

      responses.map { |response| Exemptions::Serializer.response_to_hash(response) }
    end

    sig do
      params(
        repository_id: Integer,
        actor_id: Integer,
        response_status: String,
        include_responses: T.nilable(T::Boolean),
        include_cancelled_requests: T.nilable(T::Boolean)
      ).returns(T::Array[Exemptions::Serializer::ExemptionRequestHash])
    end
    def self.requests_for_repository(repository_id, actor_id, response_status, include_responses: false, include_cancelled_requests: false)
      requests = ExemptionRequest
        .where(repository_id: repository_id, requester_id: actor_id)
      requests = requests.where.not(status: "rejected") if response_status != "rejected"
      if !include_cancelled_requests
        requests = requests.where.not(status: "cancelled")
      end
      requests = requests
        .not_expired
        .joins(:responses)
        .where(responses: {
          status: response_status.to_sym
        })

      requests.map { |request| Exemptions::Serializer.request_to_hash(request, include_responses:) }
    end

    sig do
      params(
        request_type: String,
        resource_identifier: String,
        include_expired: T.nilable(T::Boolean)
      ).returns(T::Array[Exemptions::Serializer::ExemptionRequestHash])
    end
    def self.requests_for_resource_id(request_type, resource_identifier, include_expired: false)
      requests = ExemptionRequest.where(request_type:, resource_identifier:)
      requests = requests.not_expired unless include_expired

      requests.map { |request| Exemptions::Serializer.request_to_hash(request) }
    end

    sig do
      params(
        request_type: String,
        resource_identifier: String,
        include_expired: T.nilable(T::Boolean)
      ).returns(T::Array[Exemptions::Serializer::ExemptionResponseHash])
    end
    def self.responses_for_resource_id(request_type, resource_identifier, include_expired: false)
      requests = ExemptionRequest.where(request_type:, resource_identifier:)
      requests = requests.not_expired unless include_expired

      GitHub::PrefillAssociations.prefill_associations(requests, :responses)

      requests.filter_map do |request|
        request.responses.map { |response| Exemptions::Serializer.response_to_hash(response) }
      end.flatten
    end

    sig do
      params(
        resource_owner: T.untyped,
        requester: T.any(User, PublicKey),
        resource_identifier: T.nilable(String),
        repository: T.nilable(Repository),
        request_type: String,
        requester_comment: T.nilable(String),
        expires_at: T.nilable(Time)
      ).returns(Exemptions::ExemptionRequest)
    end
    def self.create_request(
      resource_owner:,
      requester:,
      resource_identifier:,
      repository:,
      request_type:,
      requester_comment:,
      expires_at:
    )
      raise UnauthorizedOnRoot unless repository && repository.readable_by?(requester)

      Exemptions::ExemptionRequest.create!(
        resource_owner:,
        requester:,
        resource_identifier:,
        repository:,
        request_type:,
        requester_comment:,
        expires_at:,
      )
    end

    class UnauthorizedOnRoot < StandardError; end
  end
end
