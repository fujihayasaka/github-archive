# typed: true
# frozen_string_literal: true

module Notifyd
  class UnsubscribeFromLink
    def initialize(action, token)
      @action = action
      @token = token
    end

    attr_reader :action, :token

    class Auth
      attr_reader :user

      def initialize(user:)
        @user = user
      end

      def result
        Notifyd::Response.new(true)
      end

      def login
        user.login
      end

      def valid?
        user.present?
      end

      def for_user?(u)
        return false unless valid?
        u.login == user.login
      end
    end

    class Resource

      def initialize(payload:)
        @payload = TokenPayload.new(payload)
      end

      def permalink
        thread&.permalink()
      end

      def thread
        @thread if defined?(@thread)

        @thread = fetch
      end

      def to_json
        payload.to_json
      end

      def unsubscribe(user)
        Notifications::Subscriptions.unsubscribe_from_thread(user, thread)
      end

      def valid?
        thread.present?
      end

      private

      attr_reader :payload

      def fetch
        return if payload.topic_type.nil? || payload.topic_value.nil?
        if GitHub.flipper[:notifyd_unsubscribe_follow_transfers].enabled?
          return UnsubscribeResourceTypeFactory.build(klass: payload.topic_type).fetch(id: payload.topic_value)
        end
        klass = payload.topic_type
        klass.find_by(id: payload.topic_value)
      end
    end

    class MemberFeatureRequestResource < Resource
      def valid?
        subject_type == "MemberFeatureRequest::Notification" && organization_id
      end

      def unsubscribe(user)
        subscription = MemberFeatureRequest::Notification::Setting.new(user_enabled: true)
        subscription.ignore!

        Responses::Boolean.new do
          Notifyd::MemberFeatureRequestSettings.new(
            user: user,
            organization_id: organization_id,
            subscription: subscription
          ).save
        end
      end

      def permalink
        return @permalink if defined?(@permalink)
        @permalink = MemberFeatureRequest::Notification.where(entity_id: organization_id).first&.permalink
      end

      def organization_id
        payload.topic_value
      end

      def subject_type
        payload.subject_type
      end
    end

    class TokenPayload
      THREAD_TYPES = %w(gist issue organization).freeze
      attr_reader :topic_type, :topic_value, :subject_type

      def initialize(payload)
        @payload = payload
        topic = @payload&.dig("topics")&.find { |topic| THREAD_TYPES.include?(topic&.dig("type")) }
        @topic_type = topic&.dig("type")&.camelcase&.constantize
        @topic_value = topic&.dig("value")&.to_i
        @subject_type = @payload&.dig("subject_type")
      end
    end

    class ResourceFactory
      def self.build(payload:)
        if payload&.dig("subject_type") == "MemberFeatureRequest::Notification"
          return MemberFeatureRequestResource.new(payload: payload)
        end

        Resource.new(payload: payload)
      end
    end

    # Verifies a token to check whether it is for `notifyd` or not and in case
    # it is marks it as valid and returns the associated resource and the
    # signing user.
    def prepare
      user, payload = UnsubscribeToken.new(action).verify(token)

      [Auth.new(user: user), ResourceFactory.build(payload: payload)]
    end
  end
end
