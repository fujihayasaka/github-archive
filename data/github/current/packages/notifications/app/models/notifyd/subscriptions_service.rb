# typed: true
# frozen_string_literal: true

module Notifyd
  class SubscriptionsService
    include Notifyd::NetworkHelper

    attr_reader :user, :raise_error, :stat_tags

    def initialize(user, notifyd_primary = false, stat_tags = [])
      @user = user
      # When notifyd is the primary settings store, we raise errors
      # While we are in darkship we hide them
      @raise_error = notifyd_primary
      @stat_tags = stat_tags
    end

    def get_thread_subscription(thread_type, thread_id)
      response_data = get([{ name: "thread_type", value: thread_type }, { name: "thread_id", value: thread_id.to_s }])
      response_data.subscriptions.any? ? response_data.subscriptions.first : nil
    end

    def get_thread_label_subscriptions(repository, thread)
      return [] if repository.nil? || !thread.is_a?(Issue)
      return [] if thread.labels.empty?

      label_subscriptions = get_label_subscriptions(repository)
      thread_labels = Set.new(thread.labels.map(&:id))

      raw_label_subscriptions = Array.new
      label_subscriptions.map do |subscription|
        label_id = subscription.custom_fields.find { |field| field.name == "label_id" }.value.to_i
        if thread_labels.include?(label_id)
          raw_label_subscriptions.push(subscription)
        end
      end

      grouped_label_subscriptions = raw_label_subscriptions.group_by do |subscription|
        subscription.custom_fields.find { |field| field.name == "label_id" }.value.to_i
      end

      grouped_label_subscriptions.map do |_, subscriptions|
        Notifyd::LabelSubscription.new(user, subscriptions)
      end
    end

    def get_label_subscriptions(repository)
      get([
        { name: "repository_id", value: repository.id.to_s },
        { name: "subject_type", value: "Issue" },
        { name: "label_id" },
      ]).subscriptions
    end

    def get(custom_fields)
      GitHub.tracer.in_span("notifyd.subscriptions_service.get", kind: :internal, attributes: { "gh.user.id" => user.id }) do
        request = Notifyd::Proto::Subscriptions::GetRequest.new({
          user_id: @user.id,
          filter_by_custom_fields: custom_fields,
        })

        response = make_network_request_to_notifyd(request.class.name, raise_error, stat_tags) do
          client&.subscriptions.get(request)
        end

        empty_result = Notifyd::Proto::Subscriptions::GetResponse.new(
          subscriptions: []
        )
        return empty_result unless response.present?
        response.data
      end
    end

    def save(subscriptions)
      return false if subscriptions.empty?
      return false unless enabled?

      GitHub.tracer.in_span("notifyd.subscriptions_service.save", kind: :internal, attributes: { "gh.user.id" => user.id }) do
        request = Notifyd::Proto::Subscriptions::BatchReplaceRequest.new({
          user_id: user.id,
          new_subscriptions: subscriptions,
          replace_by_custom_fields: subscriptions.flat_map { |s| s[:custom_fields] }.uniq
        })

        response = make_network_request_to_notifyd(request.class.name, raise_error, stat_tags) do
          client&.subscriptions.batch_replace(request)
        end

        response.present?
      end
    end

    def delete(custom_fields)
      GitHub.tracer.in_span("notifyd.subscriptions_service.delete", kind: :internal, attributes: { "gh.user.id" => user.id }) do
        request = Notifyd::Proto::Subscriptions::BatchReplaceRequest.new(
          user_id: user.id,
          new_subscriptions: [],
          replace_by_custom_fields: custom_fields
        )

        response = make_network_request_to_notifyd(request.class.name, raise_error, stat_tags) do
          client.subscriptions.batch_replace(request)
        end

        response.present?
      end
    end

    private

    def enabled?
      return false if GitHub.enterprise?

      client.present?
    end

    def client
      @client ||= Notifyd.client
    end
  end
end
