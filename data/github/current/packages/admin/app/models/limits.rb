# typed: true
# frozen_string_literal: true

# Supports defining and handling limits in a standard way. Can be used to limit things like the number of
# enterprise teams per enterprise, the number of orgs per enterprise, the number of members per team, and so on.
#
# Simple example:
#
# class Group
#   include Limits
#
#   MAX_MEMBERS = 10
#
#   limits :members,
#     to: MAX_MEMBERS,
#     reached_when: -> { @members.size >= MAX_MEMBERS }
#
#   def initialize(members)
#     @members = members
#   end
# end
#
# See detailed usage documentation below.
module Limits
  extend ActiveSupport::Concern
  extend T::Helpers

  def self.included(base)
    base.extend(ClassMethods)
  end

  module ClassMethods
    extend T::Helpers
    include Kernel

    attr_writer :defined_limits

    def defined_limits
      @defined_limits ||= []
    end

    # Define a limit.
    #
    # name - Required Symbol representing the resources being limited.
    # options - Hash of options:
    #  :to - Required. Defines the limit value. May be an Integer, a Symbol representing a method
    #    name on the object, or a lambda.
    #  :reached_when - Required. Defines when the limit is reached. May be a Symbol representing a
    #    method name on the object, or a lambda.
    #  :at_limit - Optional. Defines when the count is exactly at the limit. May be a Symbol representing a
    #    method name on the object, or a lambda.
    #  :soft_limit - Optional. Defines a soft limit value. May be an Integer, a Symbol representing a method
    #    name on the object, or a lambda.
    #  :soft_limit_reached_when - Optional. Defines when the soft limit is reached. May be a Symbol representing a
    #    method name on the object, or a lambda.
    #  :at_soft_limit - Optional. Defines when the count is exactly at the soft limit. May be a Symbol representing a
    #    method name on the object, or a lambda.
    #  :allowed_to_be_added - Optional. Returns an Integer defining how many items are currently allowed
    #    to be added before the limit is reached. May be a Symbol representing a method name on the
    #    object, or a lambda.
    #  :will_be_exceeded_with - Optional. Defines if the addition of a given collection will result in
    #    the limit being exceeded. May be a Symbol representing a method name on the object, or a lambda.
    #    Must accept a single enumerable 'items' argument.
    #  :allowed_new_items - Optional. Defines which of the specified new items are allowed to be added
    #    given the limit. May be a Symbol representing a method name on the object, or a lambda.
    #    Must accept a single enumerable 'items' argument and return an enumerable result representing the
    #    items that are allowed to be added.
    #  :reached_message - Optional. A message to be used when the limit has been reached. May be a
    #    String or a lambda returning a String.
    #
    # Example usage:
    #
    # class Group
    #   include Limits
    #
    #   MAX_MEMBERS = 10
    #
    #   attr_reader :members
    #
    #   limits :members,
    #     to: MAX_MEMBERS,
    #     reached_when: -> { members.size >= MAX_MEMBERS }
    #
    #   def initialize(members)
    #     @members = members
    #   end
    # end
    #
    # group = Group.new([first, second])
    # group.members.size #=> 2
    # group.members_limit #=> 10
    # group.members_limit_reached? #=> false
    #
    # Returns nothing.
    def limits(name, options = {})
      raise ArgumentError, "'to' option is required" unless options[:to].present?
      raise ArgumentError, "'reached_when' option is required" unless options[:reached_when].present?

      defined_limits << name
      define_limit_method(name, options[:to])
      define_limit_reached_method(name, options[:reached_when])
      define_at_limit_method(name, options[:at_limit])
      define_soft_limit_method(name, options[:soft_limit])
      define_soft_limit_reached_method(name, options[:soft_limit_reached_when])
      define_at_soft_limit_method(name, options[:at_soft_limit])
      define_allowed_to_be_added_method(name, options[:allowed_to_be_added])
      define_limit_will_be_exceeded_with_method(name, options[:will_be_exceeded_with])
      define_limit_allowed_new_items_method(name, options[:allowed_new_items])
      define_limit_reached_message_method(name, options[:reached_message])
    end

    private

    def define_limit_method(name, limit)
      method_name = "#{name}_limit"
      if limit.is_a?(Integer)
        T.cast(self, Module).define_method(method_name, -> { limit })
      elsif limit.is_a?(Symbol)
        T.cast(self, Module).define_method(method_name, -> {
          public_send(limit) # rubocop:disable GitHub/AvoidObjectSendWithDynamicMethod
        })
      else
        T.cast(self, Module).define_method(method_name, &limit)
      end
    end

    def define_limit_reached_method(name, reached_when)
      method_name = "#{name}_limit_reached?"
      if reached_when.is_a?(Symbol)
        T.cast(self, Module).define_method(method_name, -> {
          public_send(reached_when) # rubocop:disable GitHub/AvoidObjectSendWithDynamicMethod
        })
      else
        T.cast(self, Module).define_method(method_name, &reached_when)
      end
    end

    def define_at_limit_method(name, at_limit)
      method_name = "at_#{name}_limit?"
      if at_limit.present?
        if at_limit.is_a?(Symbol)
          T.cast(self, Module).define_method(method_name, -> {
            public_send(at_limit) # rubocop:disable GitHub/AvoidObjectSendWithDynamicMethod
          })
        else
          T.cast(self, Module).define_method(method_name, &at_limit)
        end
      else
        T.cast(self, Module).define_method(method_name, -> {
          raise NotImplementedError, "specify the 'at_limit' option for the '#{name}' limit"
        })
      end
    end

    def define_soft_limit_method(name, soft_limit)
      method_name = "#{name}_soft_limit"
      if soft_limit.present?
        if soft_limit.is_a?(Integer)
          T.cast(self, Module).define_method(method_name, -> { soft_limit })
        elsif soft_limit.is_a?(Symbol)
          T.cast(self, Module).define_method(method_name, -> {
            public_send(soft_limit) # rubocop:disable GitHub/AvoidObjectSendWithDynamicMethod
          })
        else
          T.cast(self, Module).define_method(method_name, &soft_limit)
        end
      else
        T.cast(self, Module).define_method(method_name, -> {
          raise NotImplementedError, "specify the 'soft_limit' option for the '#{name}' limit"
        })
      end
    end

    def define_soft_limit_reached_method(name, soft_limit_reached_when)
      method_name = "#{name}_soft_limit_reached?"
      if soft_limit_reached_when.present?
        if soft_limit_reached_when.is_a?(Symbol)
          T.cast(self, Module).define_method(method_name, -> {
            public_send(soft_limit_reached_when) # rubocop:disable GitHub/AvoidObjectSendWithDynamicMethod
          })
        else
          T.cast(self, Module).define_method(method_name, &soft_limit_reached_when)
        end
      else
        T.cast(self, Module).define_method(method_name, -> {
          raise NotImplementedError, "specify the 'soft_limit_reached_when' option for the '#{name}' limit"
        })
      end
    end

    def define_at_soft_limit_method(name, at_soft_limit)
      method_name = "at_#{name}_soft_limit?"
      if at_soft_limit.present?
        if at_soft_limit.is_a?(Symbol)
          T.cast(self, Module).define_method(method_name, -> {
            public_send(at_soft_limit) # rubocop:disable GitHub/AvoidObjectSendWithDynamicMethod
          })
        else
          T.cast(self, Module).define_method(method_name, &at_soft_limit)
        end
      else
        T.cast(self, Module).define_method(method_name, -> {
          raise NotImplementedError, "specify the 'at_soft_limit' option for the '#{name}' limit"
        })
      end
    end

    def define_allowed_to_be_added_method(name, allowed_to_be_added)
      method_name = "#{name}_allowed_to_be_added"
      if allowed_to_be_added.present?
        if allowed_to_be_added.is_a?(Symbol)
          T.cast(self, Module).define_method(method_name, -> {
            public_send(allowed_to_be_added) # rubocop:disable GitHub/AvoidObjectSendWithDynamicMethod
          })
        else
          T.cast(self, Module).define_method(method_name, &allowed_to_be_added)
        end
      else
        T.cast(self, Module).define_method(method_name, -> {
          raise NotImplementedError, "specify the 'allowed_to_be_added' option for the '#{name}' limit"
        })
      end
    end

    def define_limit_will_be_exceeded_with_method(name, will_be_exceeded_with)
      method_name = "#{name}_limit_will_be_exceeded_with?"
      if will_be_exceeded_with.present?
        if will_be_exceeded_with.is_a?(Symbol)
          T.cast(self, Module).define_method(method_name, ->(items) {
            public_send(will_be_exceeded_with, items) # rubocop:disable GitHub/AvoidObjectSendWithDynamicMethod
          })
        else
          T.cast(self, Module).define_method(method_name, &will_be_exceeded_with)
        end
      else
        T.cast(self, Module).define_method(method_name, ->(_) {
          raise NotImplementedError, "specify the 'will_be_exceeded_with' option for the '#{name}' limit"
        })
      end
    end

    def define_limit_allowed_new_items_method(name, allowed_new_items)
      method_name = "#{name}_limit_allowed_new_items"
      if allowed_new_items.present?
        if allowed_new_items.is_a?(Symbol)
          T.cast(self, Module).define_method(method_name, ->(items) {
            public_send(allowed_new_items, items) # rubocop:disable GitHub/AvoidObjectSendWithDynamicMethod
          })
        else
          T.cast(self, Module).define_method(method_name, &allowed_new_items)
        end
      else
        T.cast(self, Module).define_method(method_name, ->(_) {
          raise NotImplementedError, "specify the 'allowed_new_items' option for the '#{name}' limit"
        })
      end
    end

    def define_limit_reached_message_method(name, message)
      method_name = "#{name}_limit_reached_message"
      if message.present?
        if message.is_a?(String)
          T.cast(self, Module).define_method(method_name, -> { message })
        else
          T.cast(self, Module).define_method(method_name, &message)
        end
      else
        T.cast(self, Module).define_method(method_name, -> { "limit reached" })
      end
    end
  end
end
