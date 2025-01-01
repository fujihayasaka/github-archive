# typed: true
# frozen_string_literal: true

module CodeScanning
  class AlertQueryService
    class RepositoryScopeStrategy < ScopeStrategy
      TenantFilteringHelper = GitHub::SecurityCenter::TenantFilteringHelper

      sig { returns(User) }
      attr_reader :user

      sig { returns(UserSession) }
      attr_reader :user_session

      sig { returns(Repository) }
      attr_reader :repository

      sig do
        params(
          user: User,
          user_session: UserSession,
          repository: Repository,
        ).void
      end
      def initialize(user:, user_session:, repository:)
        @user = user
        @user_session = user_session
        @repository = repository
      end

      memoize def scope
        :repository
      end

      sig { returns(TenantFilteringHelper::RequestScope) }
      memoize def tenant_filter_scope
        TenantFilteringHelper::RequestScope.new(
          :repository,
          repository,
          ::SecurityCenter::SecurityFeatures::CODE_SCANNING
        )
      end

      memoize def tenant_id
        @repository.owner_id
      end

      memoize def tenant_name
        @repository.owner_display_login
      end

      def with_owner_ids!(hash)
        hash[:owner_ids] = [repository.owner_id]
      end

      def with_repository_ids!(hash, exclude_filter_type: nil)
        hash[:repository_ids] = [repository.id]
      end
    end
  end
end
