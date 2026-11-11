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
        user.present?
      end

      def for_user?(u)
        return false unless valid?
        u.login == user.login
      end
    end

    # Load a Thread's object
    #
    # This follows transfers for Issue and Discussion models
    class Loader
      include GitHub::Memoizer

      attr_reader :newsies_thread

      def initialize(newsies_thread:)
        @newsies_thread = newsies_thread
      end

      def load
        Newsies::Response.new { thread }
      end

      memoize def thread
        case newsies_thread.type
        when "Grit::Commit", "Commit"
          list.commits.find(newsies_thread.id) if list
        when "AgentSessionThread"
          notification = AgentSessionFinishedNotification.find_by(id: newsies_thread.id)
          AgentSessionThread.new(notification) if notification
        when "Issue", "Discussion"
          model = newsies_thread.type.constantize
          thread = model.find_by(id: newsies_thread.id) # domain-isolation-query-violation:ignore:packages/issues (SELECT)
          return thread unless thread.nil?

          # The thread might had been transfered
          transfer_klass = "#{newsies_thread.type}Transfer".constantize
          new_id = transfer_klass.find_new_id_by_original_id(original_id: newsies_thread.id) # domain-isolation-query-violation:ignore:packages/issues (SELECT)
          model.find_by(id: new_id) # domain-isolation-query-violation:ignore:packages/issues (SELECT)
        else
          model = newsies_thread.type.constantize
          model.find_by(id: newsies_thread.id)
        end
      end

      memoize def list
        newsies_thread.list.type.constantize.find_by(id: newsies_thread.list.id)
      end
    end

    class Result
      attr_reader :result

      def initialize(result:)
        @result = result
      end

      def valid?
        result.success? && result.value.present?
      end
      alias_method :success?, :valid?

      def thread
        result.value
      end

      def permalink
        thread&.permalink
      end

      def unsubscribe(user)
        Notifications::Subscriptions.unsubscribe_from_thread(user, thread)
      end

      def readable_by?(user)
        thread&.readable_by?(user)
      end
    end

    def prepare
      user, id, extra_data = GitHub.newsies.user_and_id_from_token(action, token)
      # Token v2 doesn't use summary ID, it uses Newsies::Thread#composite_key
      if extra_data&.dig("v") == 2
        newsies_thread = Newsies::Thread.from_composite_key(id)
        result = Result.new(result: Loader.new(newsies_thread:).load)
        [Auth.new(user:, result:), result]
      else
        result = GitHub.newsies.web.find_rollup_summary_by_id(id.to_i)
        [
          Auth.new(user: user, result: result),
          UnsubscribeResourceTypeFactory.build(rollup_summary_result: result, thread_key: extra_data&.dig("thread_key")),
        ]
      end
    end

    private

    attr_reader :action, :token
  end
end
