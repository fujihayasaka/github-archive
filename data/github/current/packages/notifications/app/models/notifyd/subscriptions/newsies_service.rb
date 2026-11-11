# typed: true
# frozen_string_literal: true

module Notifyd
  module Subscriptions
    # Service used to mirror repository-level Newsies subscription state in Notifyd.
    class NewsiesService
      NS = Notifyd::Proto::Newsies
      REPOSITORY_REF_TYPE = "Repository"
      THREAD_TYPE_MAPPINGS = {
        "Discussion" => NS::ThreadTypes::DISCUSSION,
        "Issue" => NS::ThreadTypes::ISSUE,
        "PullRequest" => NS::ThreadTypes::PULL_REQUEST,
        "Release" => NS::ThreadTypes::RELEASE,
        "SecurityAlert" => NS::ThreadTypes::SECURITY_ALERT,
      }.freeze

      sig { params(user_id: Integer, repository_id: Integer, owner_id: Integer, thread_types: T::Array[String]).returns(T::Boolean) }
      def self.watch(user_id:, repository_id:, owner_id:, thread_types: [])
        return false if GitHub.enterprise?

        custom_fields = [
          NS::CustomField.new(name: "owner_id", value: owner_id.to_s),
        ]

        rpc_request = NS::WatchRequest.new(
          user_id: user_id,
          ref_id: repository_id,
          ref_type: REPOSITORY_REF_TYPE,
          thread_types: thread_types.map { |type| THREAD_TYPE_MAPPINGS[type] }.compact,
          custom_fields: custom_fields,
        )

        response = request(T.must(rpc_request.class.name)) do
          Notifyd.client.newsies.rpc(:Watch, rpc_request)
        end

        response.present?
      end

      sig { params(user_id: Integer, repository_id: Integer).returns(T::Boolean) }
      def self.unwatch(user_id:, repository_id:)
        return false if GitHub.enterprise?

        rpc_request = NS::UnwatchRequest.new(
          user_id: user_id,
          ref_ids: [repository_id],
          ref_type: REPOSITORY_REF_TYPE,
        )

        response = request(T.must(rpc_request.class.name)) do
          Notifyd.client.newsies.rpc(:Unwatch, rpc_request)
        end

        response.present?
      end

      sig { params(user_id: Integer, repository_id: Integer, owner_id: Integer).returns(T::Boolean) }
      def self.ignore(user_id:, repository_id:, owner_id:)
        return false if GitHub.enterprise?

        custom_fields = [
          NS::CustomField.new(name: "owner_id", value: owner_id.to_s),
        ]

        rpc_request = NS::IgnoreRequest.new(
          user_id: user_id,
          ref_id: repository_id,
          ref_type: REPOSITORY_REF_TYPE,
          custom_fields: custom_fields,
        )

        response = request(T.must(rpc_request.class.name)) do
          Notifyd.client.newsies.rpc(:Ignore, rpc_request)
        end

        response.present?
      end

      sig { params(request_class_name: String, block: T.proc.returns(T.untyped)).returns(T.untyped) }
      private_class_method def self.request(request_class_name, &block)
        GitHub.tracer.in_span(
          "notifyd.network_helper",
          kind: :internal,
          attributes: { "code.namespace" => request_class_name.to_s }
        ) do
          Notifyd::NetworkHelper::ResponseHandler.new(request_class_name: request_class_name, raise_error: false, tags: []).execute do
            block.call
          end
        end
      end
    end
  end
end
