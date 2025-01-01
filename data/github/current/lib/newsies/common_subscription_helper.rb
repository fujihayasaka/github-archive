# typed: true
# frozen_string_literal: true

module Newsies
  module CommonSubscriptionHelper
    extend ActiveSupport::Concern
    extend T::Helpers

    abstract!

    requires_ancestor { ::Object }

    DefaultTime = T.let(Time.utc(2008, 4, 10), Time) # Launch Day!

    sig { abstract.returns(T::Boolean) }
    def is_ignored; end

    sig { abstract.returns(T::Boolean) }
    def is_valid; end

    sig { abstract.returns(T.nilable(String)) }
    def reason; end

    included do
      # Public: Returns a Boolean specifying whether this Subscriber is ignoring
      # the List or Thread.
      alias_method :ignored?, :is_ignored

      # Public: Returns a Boolean specifying whether the User has a Subscription.
      alias_method :valid?, :is_valid
    end

    # Public: Returns a Boolean specifying whether this Subscriber was
    # mentioned.
    sig { returns T.nilable(Integer) }
    def mentioned?
      reason =~ /mention/i
    end

    # Checks if the subscription was created for a specific reason.  A blank
    # reason, or one that matches the default doesn't count.  List
    # subscriptions have a default of "list", and thread subscriptions use
    # "thread".
    sig { params(default_reason: T.nilable(String)).returns(T::Boolean) }
    def reason?(default_reason = nil)
      reason = self.reason
      return false unless reason && !reason.empty?
      default_reason ? reason != default_reason : true
    end

    # Public: Returns a Boolean specifying whether Subscriber is subscribed
    # and not ignored.
    sig { returns T::Boolean }
    def subscribed?
      valid? && !ignored?
    end

    # Public: Returns a Boolean specifying whether Subscriber should be notified
    # only if they have participated or were @mentioned in the thread.
    sig { returns T::Boolean }
    def participation_only?
      !valid? && !ignored?
    end

    sig { returns Time }
    def created_at
      if time = @created_at
        time = @created_at = time.utc unless time.utc?
      end
      time || DefaultTime
    end

    sig { params(value: String).returns(String) }
    def build_inspect(value)
      %(#<%s %s valid=%s, ignored=%s, reason=%s, created=%s>) % [
        self.class, value, is_valid.inspect,
        is_ignored.inspect, reason.inspect, created_at.inspect]
    end
  end
end
