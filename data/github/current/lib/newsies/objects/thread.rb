# typed: true
# frozen_string_literal: true

require "newsies/object"

module Newsies
  class Thread < ::Newsies::Object
    class SubscriptionTypeUnsetError < RuntimeError; end

    POSSIBLE_THREAD_TYPES = [
      CheckSuite,
      Commit,
      Gist,
      Issue,
      PullRequest,
      Release,
      RepositoryInvitation,
      RepositoryVulnerabilityAlert,
      RepositoryAdvisory,
      DiscussionPost,
      AdvisoryCredit,
      Discussion,
      Vulnerability
    ]
    # Public: Ensures that provided instance is a Newsies::Thread.
    #
    # object - The Newsies::Thread or object to convert to a Newsies::Thread.
    # list - An optional Newsies::List to assign to this thread.
    #
    # Returns a Newsies::Thread instance.
    def self.to_object(object, list: nil)
      # If the object is already a Newsies::Thread, just return it, and update the list if provided.
      if object.is_a?(self)
        object.list = list if list.present?
        return object
      end

      # If the object implements notifications_subscription_type, use that otherwise
      # fallback to type.
      subscription_type = if subscription_type_class = object.try(:notifications_subscription_type)
        type_from_class(subscription_type_class)
      else
        to_type(object)
      end
      new(to_type(object), to_id(object), list: list, subscription_type: subscription_type)
    end

    # Public: Converts a key into a Newsies::Thread instance.
    #
    # key - The String representation of type and id.
    # list - An optional Newsies::List to assign to this thread.
    #
    # Returns Newsies::Thread instance.
    def self.from_key(key, list: nil, separator: KEY_SEPARATOR)
      raise InvalidKey.new(key, separator) unless valid_key?(key, separator: separator)

      type, id = key.split(separator, 2)

      if list
        new(type, id, list: list)
      else
        new(type, id)
      end
    end

    attr_accessor :list

    def initialize(type, id, list: nil, subscription_type: nil)
      super(type, id)

      @list = list
      @subscription_type = subscription_type
    end

    def subscription_type
      # report a SubscriptionTypeUnsetError to Failbot with a backtrace from the caller if instance var is nil
      if @subscription_type.nil?
        unless GitHub.enterprise?
          error = SubscriptionTypeUnsetError.new("subscription_type is nil")
          error.set_backtrace(caller)
          NotificationsFailbot.report(error,
            "gh.notifications.list.id": list.id,
            "gh.notifications.list.type": list.type,
            "gh.notifications.thread.id": id,
            "gh.notifications.thread.type": type,
          )
        end

        # Fallback to thread type
        @subscription_type = type
      end

      @subscription_type
    end

    def list_key(separator = KEY_SEPARATOR)
      require_list
      "#{@list.type}#{separator}#{@list.id}#{separator}#{key(separator)}"
    end

    # Public: Awkward but backward compatible thread_key with list id prefix.
    def list_id_key(separator = KEY_SEPARATOR)
      require_list
      "#{@list.id}#{separator}#{key(separator)}"
    end

    def list_id
      require_list
      @list.id
    end

    def list_type
      require_list
      @list.type
    end

    private

    def require_list
      raise ArgumentError, "@list is required" if @list.blank?
    end
  end
end
