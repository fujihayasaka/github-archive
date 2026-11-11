# typed: true
# frozen_string_literal: true

module Notifyd
  class MaintenanceService
    include Notifyd::NetworkHelper

    SubscriptionType = Notifications::Subscriptions::RepositorySubscriptionType

    # Public: Delete all the subscriptions and settings for a single repository in notifyd.
    #
    # repo_id - Repository identifier.
    sig { params(repo_id: Integer).void }
    def delete_repository(repo_id)
      GitHub.tracer.in_span("notifyd.maintenance_service.delete_repository", kind: :internal, attributes: { "gh.repo.id" => repo_id }) do
        request = Notifyd::Proto::Maintenance::DeleteRepositoryRequest.new({ repository_id: repo_id })
        make_network_request_to_notifyd(request.class.name) do
          client.maintenance.delete_repository(request)
        end
      end
    end

    # Public: Delete repository subscriptions and settings for a sequence of users in notifyd.
    #
    # repo_id - Repository identifier.
    # user_ids - The sequence of user identifiers.
    sig { params(repo_id: Integer, user_ids: T::Array[Integer]).void }
    def delete_repository_for_users(repo_id:, user_ids:)
      GitHub.tracer.in_span("notifyd.maintenance_service.delete_repository_for_users", kind: :internal, attributes: { "gh.repo.id" => repo_id }) do
        request = Notifyd::Proto::Maintenance::DeleteRepositoryForUsersRequest.new({ repository_id: repo_id, user_ids: user_ids })
        make_network_request_to_notifyd(request.class.name) do
          client.maintenance.delete_repository_for_users(request)
        end
      end
    end

    # Public: Delete all the subscriptions and settings for a user in notifyd.
    #
    # user_id - User identifier.
    sig { params(user_id: Integer).void }
    def delete_user(user_id)
      GitHub.tracer.in_span("notifyd.maintenance_service.delete_user", kind: :internal, attributes: { "gh.user.id" => user_id }) do
        request = Notifyd::Proto::Maintenance::DeleteUserRequest.new({ user_id: user_id })
        make_network_request_to_notifyd(request.class.name) do
          client.maintenance.delete_user(request)
        end
      end
    end

    # Public: Delete all the subscriptions and settings for a user to a sequence of repositories in notifyd.
    #
    # user_id - User identifier.
    # repository_ids - Sequence of repository identifiers.
    sig { params(user_id: Integer, repo_ids: T::Array[Integer]).void }
    def delete_user_repositories(user_id:, repo_ids:)
      GitHub.tracer.in_span("notifyd.maintenance_service.delete_user_repositories", kind: :internal, attributes: { "gh.user.id" => user_id }) do
        request = Notifyd::Proto::Maintenance::DeleteUserRepositoriesRequest.new({ user_id: user_id, repository_ids: repo_ids })
        make_network_request_to_notifyd(request.class.name) do
          client.maintenance.delete_user_repositories(request)
        end
      end
    end

    # Public: Delete subscriptions and settings for a user by repository subscription type.
    #
    # user_id - User identifier.
    # owner_id - Optional owner identifier. If nil, applies to all repositories.
    # subscription_type - Enum value: SubscriptionType::Watching, SubscriptionType::Custom, or SubscriptionType::Ignoring.
    sig { params(user_id: Integer, owner_id: T.nilable(Integer), subscription_type: SubscriptionType).void }
    def delete_user_repository_subscription_type(user_id:, owner_id:, subscription_type:)
      GitHub.tracer.in_span("notifyd.maintenance_service.delete_user_repository_subscription_type", kind: :internal, attributes: { "gh.user.id" => user_id, "gh.repo.owner.id" => owner_id, "gh.subscription.type" => subscription_type.serialize }) do
        request = Notifyd::Proto::Maintenance::DeleteUserRepositorySubscriptionTypeRequest.new({
          user_id: user_id,
          owner_id: owner_id,
          subscription_type: map_subscription_type(subscription_type),
        })
        make_network_request_to_notifyd(request.class.name) do
          client.maintenance.delete_user_repository_subscription_type(request)
        end
      end
    end

    private

    def client
      @client ||= Notifyd.client
    end

    sig { params(subscription_type: SubscriptionType).returns(Symbol) }
    def map_subscription_type(subscription_type)
      case subscription_type
      when SubscriptionType::Watching
        :SUBSCRIPTION_TYPE_REPOSITORY
      when SubscriptionType::Custom
        :SUBSCRIPTION_TYPE_THREAD_TYPE
      when SubscriptionType::Ignoring
        :SUBSCRIPTION_TYPE_MUTE
      else
        T.absurd(subscription_type)
      end
    end
  end
end
