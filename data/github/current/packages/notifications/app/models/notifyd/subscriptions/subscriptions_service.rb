# typed: true
# frozen_string_literal: true

module Notifyd
  module Subscriptions
    class SubscriptionsService
      extend Notifyd::NetworkHelper

      # Subscriptions (S) namespace
      S = Notifyd::Proto::Subscriptions

      sig { params(user_id: Integer, thread_type: String, thread_id: Integer).returns(T.nilable(Notifyd::Subscriptions::ThreadSubscription)) }
      def self.thread_subscription(user_id, thread_type, thread_id)
        response = get(user_id, [{ name: "thread_type", value: thread_type }, { name: "thread_id", value: thread_id.to_s }])
        return nil if response.nil?

        if response.subscriptions.any?
          subscription = T.must(response.subscriptions.first)

          Notifyd::Subscriptions::ThreadSubscription.new(
            subscribed: true,
            created_at: subscription.created_at.positive? ? subscription.created_at : nil,
          )
        else
          Notifyd::Subscriptions::ThreadSubscription.new(subscribed: false, created_at: nil)
        end
      end

      sig { params(user_id: Integer, repository_id: Integer, label_ids: T::Array[Integer]).returns(T.nilable(T::Array[Notifyd::LabelSubscription])) }
      def self.thread_label_subscriptions(user_id, repository_id, label_ids)
        return [] if label_ids.empty?

        response = get(user_id, [
          { name: "repository_id", value: repository_id.to_s },
          { name: "subject_type", value: "Issue" },
          { name: "label_id" },
        ])

        return nil if response.nil?

        thread_labels = Set.new(label_ids)

        raw_label_subscriptions = Array.new
        response.subscriptions.map do |subscription|
          label_id = subscription.custom_fields.find { |field| field.name == "label_id" }.value.to_i
          if thread_labels.include?(label_id)
            raw_label_subscriptions.push(subscription)
          end
        end

        grouped_label_subscriptions = raw_label_subscriptions.group_by do |subscription|
          subscription.custom_fields.find { |field| field.name == "label_id" }.value.to_i
        end

        grouped_label_subscriptions.map do |_, subscriptions|
          Notifyd::LabelSubscription.new(subscriptions)
        end
      end

      sig { params(user_id: Integer, repository_id: Integer).returns(T.nilable(T::Boolean)) }
      def self.repository_subscribed?(user_id, repository_id)
        response = get(user_id, [
          { name: "category", value: "all" },
          { name: "repository_id", value: repository_id.to_s },
        ])
        return nil if response.nil?

        response.subscriptions.any?
      end

      sig { params(user_id: Integer, subscriptions: T::Array[T.untyped]).returns(T::Boolean) }
      def self.batch_replace(user_id, subscriptions)
        return false if subscriptions.empty?

        GitHub.tracer.in_span("notifyd.subscriptions_service.batch_replace", kind: :internal, attributes: { "gh.user.id" => user_id }) do
          request = S::BatchReplaceRequest.new({
            user_id: user_id,
            new_subscriptions: subscriptions,
            replace_by_custom_fields: subscriptions.flat_map { |s| s[:custom_fields] }.uniq
          })

          response = request(T.must(request.class.name)) do
            Notifyd.client.subscriptions.batch_replace(request)
          end

          response.present?
        end
      end

      sig { params(user_id: Integer, custom_fields: T::Array[T.untyped]).returns(T::Boolean) }
      def self.delete(user_id, custom_fields)
        GitHub.tracer.in_span("notifyd.subscriptions_service.delete", kind: :internal, attributes: { "gh.user.id" => user_id }) do
          request = S::BatchReplaceRequest.new(
            user_id: user_id,
            new_subscriptions: [],
            replace_by_custom_fields: custom_fields
          )

          response = request(T.must(request.class.name)) do
            Notifyd.client.subscriptions.batch_replace(request)
          end

          response.present?
        end
      end

      sig { params(user_id: Integer, custom_fields: T::Array[T.untyped]).returns(T.nilable(S::GetResponse)) }
      private_class_method def self.get(user_id, custom_fields)
        GitHub.tracer.in_span("notifyd.subscriptions_service.get", kind: :internal, attributes: { "gh.user.id" => user_id }) do
          request = S::GetRequest.new({
            user_id: user_id,
            filter_by_custom_fields: custom_fields,
          })

          response = request(T.must(request.class.name)) do
            Notifyd.client.subscriptions.get(request)
          end

          return nil unless response.present?
          response.data
        end
      end

      sig do
        params(
          request_class_name: String,
          block: T.proc.returns(T.nilable(Twirp::ClientResp[T.any(
            S::GetResponse,
            Google::Protobuf::Empty
          )]))
        ).returns(T.nilable(Twirp::ClientResp[T.any(
          S::GetResponse,
          Google::Protobuf::Empty
        )]))
      end
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
