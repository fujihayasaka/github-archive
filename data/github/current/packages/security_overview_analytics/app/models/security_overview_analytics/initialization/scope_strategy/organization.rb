# typed: strict
# frozen_string_literal: true

module SecurityOverviewAnalytics
  class Initialization
    module ScopeStrategy
      class Organization < Base
        extend T::Sig

        sig { override.returns(T::Array[Type]) }
        def self.available_initialization_types
          result = T.let([Type::FeatureEnablement, Type::RepositoryMetadata], T::Array[Type])
          result << Type::CodeScanningAlert if SecurityCenter::SecurityFeatures.code_scanning_enabled_for_instance?
          result << Type::SecretScanningAlert if SecurityCenter::SecurityFeatures.secret_scanning_enabled_for_instance?
          result << Type::DependabotAlerts if SecurityCenter::SecurityFeatures.dependabot_alerts_enabled_for_instance?
          result
        end

        sig { returns(::Organization) }
        attr_reader :organization

        sig { override.params(id: Integer, prerequisite: T.nilable(Type)).returns(String) }
        def self.initialization_key_prefix(id:, prerequisite: nil)
          # The "prerequisite" pattern allow registering each feature type per tenant per prerequisite
          # and it is mostly used for enabling initialization on newly introduced feature at business level.
          #
          # Initialization types for repository owners level do not have any prerequisite when this function was added.
          "security_overview_analytics.initialization.organization.#{id}"
        end

        sig { params(organization: ::Organization).void }
        def initialize(organization:)
          @organization = organization
        end

        sig { override.returns(String) }
        memoize def initialization_key_prefix
          self.class.initialization_key_prefix(id: T.must(organization.id))
        end

        sig { override.params(type: T.nilable(Initialization::Type)).void }
        def enqueue(type: nil)
          Initialization::OrganizationJob.perform_later(organization_id: organization.id, type: type&.serialize)
        end

        sig { override.returns(T.any(::Business, ::Organization, ::User)) }
        def scope
          self.organization
        end
      end
    end
  end
end
