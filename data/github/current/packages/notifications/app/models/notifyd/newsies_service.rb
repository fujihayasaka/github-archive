# typed: true
# frozen_string_literal: true

module Notifyd
  # Service built specifically to migrate use cases and data from Newsies to Notifyd
  class NewsiesService
    include Notifyd::NetworkHelper

    include GitHub::Tracing
    trace_method :watch
    trace_method :watch_repository
    trace_method :unwatch
    trace_method :unwatch_all
    trace_method :ignore

    # alias
    NS = Notifyd::Proto::Newsies

    # Reference to a List type entity
    Ref = Struct.new(:id, :type) do
      def to_params
        { ref_id: id, ref_type: type }
      end
    end

    Refs = Struct.new(:ids, :type) do
      def to_params
        { ref_ids: ids, ref_type: type }
      end
    end

    class RefConverter
      def self.from(list)
        new.from(list)
      end

      def self.from_multiple(lists)
        new.from_multiple(lists)
      end

      def self.from_repository_id(repository_id)
        Ref.new(repository_id, "Repository")
      end

      def from(list)
        Ref.new(list.id, list.class.name)
      end

      def from_multiple(lists)
        return nil if lists.nil? || lists.length == 0
        Refs.new(lists.map { |list| list.id }, lists[0].class.name)
      end
    end

    class ThreadTypeConverter
      MAPPINGS = {
        "Discussion" => NS::ThreadTypes::DISCUSSION,
        "Issue" => NS::ThreadTypes::ISSUE,
        "PullRequest" => NS::ThreadTypes::PULL_REQUEST,
        "Release" => NS::ThreadTypes::RELEASE,
        "SecurityAlert" => NS::ThreadTypes::SECURITY_ALERT,
      }

      def self.from(type)
        new.from(type)
      end

      def from(type)
        MAPPINGS[type]
      end
    end

    def initialize(client = Notifyd.client)
      @client = client
    end

    # Start watching a list type entity like Repository and optionally only some thread types under it
    def watch(user:, list:, thread_types: [], is_auto_susbcription: false)
      return nil unless enabled?

      # handle cases when is_auto_susbcription isn't boolean
      auto_susbcription_value = (is_auto_susbcription == true).to_s

      # Passing auto_subscription isn't intended in migration use-case
      custom_fields = [
        { name: "owner_id", value: list.owner&.id&.to_s },
        { name: "owner_type", value: list.owner&.class&.name&.downcase },
        { name: "auto_subscription", value: auto_susbcription_value }
      ]

      request = NS::WatchRequest.new(
        RefConverter.from(list).to_params.merge(
          user_id: user.id,
          thread_types: thread_types.map { |type| ThreadTypeConverter.from(type) }.compact,
          custom_fields: custom_fields
        )
      )

      tags = tags_for_list(list)
      tags << "auto_subscription:#{auto_susbcription_value}"

      rpc(:Watch, request, false, tags)
    end

    def watch_repository(user_id:, repository_id:, owner_id: nil, owner_type: nil, thread_types: [])
      return nil unless enabled?

      request = NS::WatchRequest.new(
        RefConverter.from_repository_id(repository_id).to_params.merge(
          user_id: user_id,
          thread_types: thread_types.map { |type| ThreadTypeConverter.from(type) }.compact,
          custom_fields: [
            NS::CustomField.new(name: "owner_id", value: owner_id&.to_s),
            NS::CustomField.new(name: "owner_type", value: owner_type&.downcase),
          ]
        )
      )
      tags = base_tags(owner_type: owner_type, list_type: "Repository")
      rpc(:Watch, request, false, tags)
    end

    # Stop watching a list type entity like Repository
    def unwatch(user:, lists:)
      return nil unless enabled?
      return nil if lists.nil? || lists.empty?

      request = NS::UnwatchRequest.new(
        RefConverter.from_multiple(lists).to_params.merge(user_id: user.id)
      )

      rpc(:Unwatch, request, false, tags_for_list(lists[0]))
    end

    # Stop watching all lists of a type entity like Repository
    def unwatch_all(user_id:, ref_type:)
      return nil unless enabled?

      request = NS::UnwatchAllRequest.new(
        { user_id: user_id, ref_type: ref_type }
      )

      rpc(:UnwatchAll, request, false, [])
    end

    # Ignore a list type entity like Repository
    def ignore(user:, list:)
      return nil unless enabled?

      request = NS::IgnoreRequest.new(
        RefConverter.from(list).to_params.merge(
          user_id: user.id,
          custom_fields: [
            NS::CustomField.new(name: "owner_id", value: list.owner.id.to_s),
            NS::CustomField.new(name: "owner_type", value: list.owner&.class&.name&.downcase),
          ]
        )
      )

      rpc(:Ignore, request, false, tags_for_list(list))
    end

    private

    attr_reader :client

    def rpc(action, request, raise_error = false, tags = [])
      make_network_request_to_notifyd(request.class.name, raise_error, tags) do
        client.newsies.rpc(action, request)
      end
    end

    def tags_for_list(list)
      base_tags(owner_type: list.owner&.class&.name&.downcase, list_type: list&.class&.name)
    end

    def base_tags(owner_type:, list_type:)
      ["owner_type:#{owner_type}", "list_type:#{list_type}"]
    end

    def enabled?
      return false if GitHub.enterprise?

      client.present?
    end
  end
end
