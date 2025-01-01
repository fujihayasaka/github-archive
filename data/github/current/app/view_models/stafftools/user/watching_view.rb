# typed: true
# frozen_string_literal: true

module Stafftools
  module User
    class WatchingView < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels
      attr_reader :user

      def page_title
        "#{user.login} - Watching"
      end

      def settings_available?
        settings_response.success?
      end

      def subscriptions_available?
        subscriptions_response.success?
      end

      # FIXME: This should be paginated and should use set: :subscribed.
      def subscriptions
        @subscriptions ||= begin
          subscriptions = subscriptions_response.select { |subscription| !subscription.ignored? }
          subscriptions_with_repositories(subscriptions)
        end
      end

      # FIXME: This should be paginated and should use set: :ignored.
      def ignoring
        @ignoring ||= begin
          subscriptions = subscriptions_response.select { |subscription| subscription.ignored? }
          subscriptions_with_repositories(subscriptions)
        end
      end

      def automatically_watch
        if settings_available?
          settings_response.auto_subscribe?
        else
          "unavailable"
        end
      end

      require "forwardable"
      class SubscriptionWithRepository
        extend Forwardable

        def_delegators :@subscription, :created_at
        def_delegators :@repository, :owner, :name_with_owner, :name

        attr_reader :subscription, :repository

        def initialize(subscription, repository)
          @subscription = subscription
          @repository = repository
        end

        def repository_id
          repository.id
        end
      end

      private

      def settings_response
        @settings_response ||= GitHub.newsies.settings(user)
      end

      def subscriptions_with_repositories(subscriptions)
        ids = subscriptions.map(&:list_id)
        repositories = ::Repository.includes(:owner).where(id: ids).index_by(&:id)
        subscriptions.map do |subscription|
          if repo = repositories[subscription.list_id]
            SubscriptionWithRepository.new(subscription, repo)
          end
        end.compact
      end

      def subscriptions_response
        @subscriptions_response ||= GitHub.newsies.subscriptions(user, list_type: ::Repository.name)
      end
    end
  end
end
