# typed: strict
# frozen_string_literal: true

module SecurityOverviewAnalytics
  class Initialization
    module ScopeStrategy
      class User < Base

        sig { override.returns(T::Array[Type]) }
        def self.available_initialization_types
          result = T.let([Type::FeatureEnablement, Type::RepositoryMetadata], T::Array[Type])
          result << Type::SecretScanningAlert if SecurityCenter::SecurityFeatures.secret_scanning_enabled_for_instance?
          result
        end

        sig { returns(::User) }
        attr_reader :user

        sig { override.params(id: Integer, prerequisite: T.nilable(Type)).returns(String) }
        def self.initialization_key_prefix(id:, prerequisite: nil)
          # The "prerequisite" pattern allow registering each feature type per tenant per prerequisite
          # and it is mostly used for enabling initialization on newly introduced feature at business level.
          #
          # Initialization types for repository owners level do not have any prerequisite when this function was added.
          "security_overview_analytics.initialization.user.#{id}"
        end

        sig { params(user: ::User).void }
        def initialize(user:)
          raise ArgumentError, "User must be vanilla. Use ScopeStrategy::Organization for organizations." unless user.user?
          @user = user
        end

        sig { override.returns(String) }
        memoize def initialization_key_prefix
          self.class.initialization_key_prefix(id: user.id)
        end

        sig { override.params(type: T.nilable(Initialization::Type)).void }
        def enqueue(type: nil)
          Initialization::UserJob.perform_later(user_id: user.id, type: type&.serialize)
        end

        sig { override.returns(T.any(::Business, ::Organization, ::User)) }
        def scope
          self.user
        end
      end
    end
  end
end
