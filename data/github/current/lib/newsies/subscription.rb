# typed: true
# frozen_string_literal: true
require "forwardable"

module Newsies
  # Public: Simple Struct for tracking the status of a User Subscription to a
  # List. This object implements the Null Object pattern.  Any Subscriptions
  # that don't exist will return false for #valid?.
  class Subscription
    extend Forwardable

    def_delegator :@list, :id, :list_id
    def_delegator :@list, :type, :list_type

    def_delegator :@thread, :id, :thread_id
    def_delegator :@thread, :type, :thread_type
    def_delegator :@thread, :type, :thread_class # backwards compatibility

    attr_reader :list, :thread, :is_valid, :is_ignored, :reason
    attr_accessor :thread_types, :events, :list_object

    # this include _has_ to be after the attr_accessor declaration because it
    # needs access to those accessors as it is being mixed in
    include CommonSubscriptionHelper

    # Returns a Subscription object for the list and/or thread, that represents being _not_ subscribed
    def self.not_subscribed(list = nil, thread = nil)
      new(list, thread, false, false, nil, nil)
    end

    def self.custom_list_subscription(list:, reason:, created_at:, thread_types:)
      subscription = new(list, nil, false, false, reason, created_at)
      subscription.thread_types = thread_types
      subscription
    end

    # Determines the target for for conditional access for Subscription instances
    #
    # subscriptions - an enumerable of Subscriptions
    #
    # returns Hash[Subscriptions] => target for conditional access
    def self.multiple_target_for_conditional_access(subscriptions)
      ConditionalAccess::Filter.ensure_with_class(subscriptions, Newsies::Subscription)

      # This implementation only considers subscriptions to repositories.
      raise NotImplementedError, "Only Repository is currently supported" if subscriptions.any? { |s| s.list_type != "Repository" }

      repositories = Repository.where(id: subscriptions.map { |s| s.list_id })
      repository_to_target = Repository.multiple_target_for_conditional_access(repositories)
      repository_id_to_target = repository_to_target.transform_keys { |k| k.id }
      subscriptions.each_with_object({}) { |v, h| h[v] = repository_id_to_target[v.list_id] }
    end

    def initialize(list = nil, thread = nil, is_valid = nil, is_ignored = nil, reason = nil, created_at = nil, events = [])
      @list         = list
      @thread       = thread
      @is_valid     = is_valid
      @is_ignored   = is_ignored
      @reason       = reason
      @created_at   = created_at
      @thread_types = []
      @events       = events
    end

    def readable_by?(user)
      # list subscriptions depend on the list object being readable
      if list && !thread
        return list_object&.readable_by?(user)
      end

      false
    end

    def thread_type_only?(thread_type_class)
      # thread_type_class can be a string of the thread type to check
      # so we don't need to coerce it if it is
      thread_type = \
        if thread_type_class.is_a?(String)
          thread_type_class
        else
          Newsies::Object.type_from_class(thread_type_class)
        end

      !ignored? && @thread_types.include?(thread_type)
    end

    def participation_only?
      super && @thread_types.empty?
    end

    def events_only?
      subscribed? && @events.present?
    end

    def inspect
      build_inspect "list=##{list_id}, thread_types=#{thread_types.inspect}, events=#{events.inspect}, "
    end
  end
end
