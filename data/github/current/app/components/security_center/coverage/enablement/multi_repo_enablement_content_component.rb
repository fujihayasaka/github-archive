# typed: strict
# frozen_string_literal: true

module SecurityCenter
  module Coverage
    module Enablement
      class MultiRepoEnablementContentComponent < ApplicationComponent
        extend T::Sig

        TEST_SELECTOR = T.let(SecureRandom.uuid, String)
        DEPENDENCIES_SECTION_TEST_SELECTOR = T.let(SecureRandom.uuid, String)
        DEPENDENCY_GRAPH_TEST_SELECTOR = T.let(SecureRandom.uuid, String)
        DEPENDABOT_SECTION_TEST_SELECTOR = T.let(SecureRandom.uuid, String)
        DEPENDABOT_ALERTS_TEST_SELECTOR = T.let(SecureRandom.uuid, String)
        DEPENDABOT_SECURITY_UPDATES_TEST_SELECTOR = T.let(SecureRandom.uuid, String)
        ADVANCED_SECURITY_SECTION_TEST_SELECTOR = T.let(SecureRandom.uuid, String)
        ADVANCED_SECURITY_TEST_SELECTOR = T.let(SecureRandom.uuid, String)
        CODE_SCANNING_SECTION_TEST_SELECTOR = T.let(SecureRandom.uuid, String)
        CODEQL_DEFAULT_SETUP_TEST_SELECTOR = T.let(SecureRandom.uuid, String)
        SECRET_SCANNING_SECTION_TEST_SELECTOR = T.let(SecureRandom.uuid, String)
        SECRET_SCANNING_ALERTS_TEST_SELECTOR = T.let(SecureRandom.uuid, String)
        PUSH_PROTECTION_TEST_SELECTOR = T.let(SecureRandom.uuid, String)
        TURBO_FRAME_ID = T.let("multi-repo-enablement-content", String)

        class FeatureData < T::Struct
          extend T::Sig

          const :can_disable, T::Boolean, default: true
          const :can_enable, T::Boolean, default: true
          const :description, String, default: ""
          const :is_available, T::Boolean, default: true
          const :blocked_reason, T.nilable(String)

          sig { params(other: FeatureData).returns(T::Boolean) }
          def ==(other)
            self.can_disable == other.can_disable &&
              self.can_enable == other.can_enable &&
              self.description == other.description &&
              self.is_available == other.is_available &&
              self.blocked_reason == other.blocked_reason
          end
        end

        class Data < T::Struct
          extend T::Sig

          const :organization, Organization
          const :dependency_graph, FeatureData
          const :dependabot_alerts, FeatureData
          const :dependabot_security_updates, FeatureData
          const :advanced_security, FeatureData
          const :codeql_default_setup, FeatureData
          const :secret_scanning_alerts, FeatureData
          const :secret_scanning_push_protection, FeatureData

          sig { params(hash: T::Hash[Symbol, FeatureData]).returns(Data) }
          def self.from_hash(hash)
            new(**T.unsafe(hash))
          end
        end

        sig { returns(Data) }; attr_reader :data

        sig { params(data: Data).void }
        def initialize(data)
          @data = data
        end

        sig { returns(T::Boolean) }
        def render_section_dependencies
          any_available?(data.dependency_graph)
        end

        sig { returns(T::Boolean) }
        def render_section_dependabot
          any_available?(
            data.dependabot_alerts,
            data.dependabot_security_updates
          )
        end

        sig { returns(T::Boolean) }
        def render_section_advanced_security
          any_available?(data.advanced_security)
        end

        sig { returns(T::Boolean) }
        def render_section_code_scanning
          any_available?(data.codeql_default_setup)
        end

        sig { returns(T::Boolean) }
        def render_section_secret_scanning
          any_available?(
            data.secret_scanning_alerts,
            data.secret_scanning_push_protection
          )
        end

        private

        sig { params(feature_data: FeatureData).returns(T::Boolean) }
        def any_available?(*feature_data)
          feature_data.any? { |feature| feature.is_available }
        end

        sig { returns(T.nilable(SecurityCenter::Coverage::Enablement::SettingComponent::AuxData)) }
        def codeql_default_setup_aux_data
          recommended_value = CodeScanning::AutoCodeql.recommended_query_suite(data.organization)

          SecurityCenter::Coverage::Enablement::SettingComponent::AuxData.new(
            name: "auto_codeql_query_suite",
            options: CodeScanning::AutoCodeql.query_suite_options(data.organization),
            initial_value: recommended_value,
            recommended_value: recommended_value,
          )
        end
      end
    end
  end
end
