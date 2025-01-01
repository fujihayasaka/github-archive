# typed: strict
# frozen_string_literal: true

module SecurityOverviewAnalytics
  class Initialization
    module ScopeStrategy
      class Business < Base

        sig { override.returns(T::Array[Type]) }
        def self.available_initialization_types
          # Not actually used for business, but we need to return something
          T.let([Type::Organizations, Type::Users], T::Array[Type])
        end

        sig { returns(::Business) }
        attr_reader :business

        sig { returns(T.nilable(Type)) }
        attr_reader :prerequisite

        sig { override.params(id: Integer, prerequisite: T.nilable(Type)).returns(String) }
        def self.initialization_key_prefix(id:, prerequisite: nil)
          return "security_overview_analytics.initialization.business.#{id}" if prerequisite.nil?
          "security_overview_analytics.initialization.business.#{prerequisite.serialize}.#{id}"
        end

        sig do
          params(
            business: ::Business,
            prerequisite: T.nilable(Type)
          ).void
        end
        def initialize(business:, prerequisite: nil)
          @business = business
          @prerequisite = prerequisite
        end

        sig { override.returns(String) }
        memoize def initialization_key_prefix
          self.class.initialization_key_prefix(id: T.cast(business.id, Integer), prerequisite:)
        end

        sig { override.params(type: T.nilable(Initialization::Type)).void }
        def enqueue(type: nil)
          Initialization::BusinessJob.perform_later(business_id: business.id, type: Initialization::Type::Organizations.serialize)

          if business.enterprise_managed? || GitHub.enterprise?
            Initialization::BusinessJob.perform_later(business_id: business.id, type: Initialization::Type::Users.serialize)
          end
        end

        sig { override.returns(T.any(::Business, ::Organization, ::User)) }
        def scope
          self.business
        end
      end
    end
  end
end
