# typed: true
# frozen_string_literal: true

module Newsies
  class UnsubscribeFromLink
    def initialize(action, token)
      @action = action
      @token = token
    end

    class Auth
      attr_reader :result, :user

      def initialize(user:, result:)
        @user = user
        @result = result
      end

      def login
        user&.login
      end

      def valid?
        result.success? && user.present?
      end

      def for_user?(u)
        return false unless valid?
        u.login == user.login
      end
    end

    class Resource
      def initialize(result:)
        @result = result
      end

      def permalink
        result.value&.thread&.permalink
      end

      def thread
        result.value&.thread
      end

      def to_json
        result.value&.to_json
      end

      def unsubscribe(user)
        Notifications::Subscriptions.unsubscribe_from_thread(user, thread)
      end

      def valid?
        thread.present?
      end

      def readable_by?(user)
        thread&.readable_by?(user)
      end

      private

      attr_reader :result
    end

    def prepare
      user, summary_id, extra_data = GitHub.newsies.user_and_id_from_token(action, token)
      result = GitHub.newsies.web.find_rollup_summary_by_id(summary_id.to_i)
      if GitHub.flipper[:newsies_unsubscribe_follow_transfers].enabled?(user)
        [
          Auth.new(user: user, result: result),
          UnsubscribeResourceTypeFactory.build(rollup_summary_result: result, thread_key: extra_data&.dig("thread_key")),
        ]
      else
        [Auth.new(user: user, result: result),  Resource.new(result: result)]
      end
    end

    private

    attr_reader :action, :token
  end
end
