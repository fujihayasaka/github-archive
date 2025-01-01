# typed: strict
# frozen_string_literal: true

module Copilot
  module Policies
    module MenuItems
      module GeneralPolicies
        class Base
          extend T::Helpers
          abstract!

          sig { params(copilot_configurable: T.any(Copilot::User, Copilot::Organization, Copilot::Business), checked: T::Boolean, policy_value: String).void }
          def initialize(copilot_configurable:, checked:, policy_value: "nothing")
            @copilot_configurable = copilot_configurable
            @checked = checked
            @policy_value = policy_value
          end

          sig { returns(T.any(Copilot::User, Copilot::Organization, Copilot::Business)) }
          attr_reader :copilot_configurable

          sig { returns(T::Boolean) }
          attr_reader :checked

          sig { returns(String) }
          attr_reader :policy_value

          sig { returns(String) }
          def description
            ""
          end

          sig { returns(String) }
          def label
            ""
          end

          sig { returns(String) }
          def self.value
            title.parameterize.underscore
          end

          sig { returns(String) }
          def value
            self.class.value
          end

          sig { returns(T::Boolean) }
          def business?
            copilot_configurable.__getobj__.is_a?(::Business)
          end

          sig { returns(T::Boolean) }
          def standalone_business?
            return false unless business?
            T.cast(copilot_configurable, Copilot::Business).copilot_standalone?
          end

          sig { returns(T::Boolean) }
          def policies_refresh_business?
            copilot_configurable.__getobj__.is_a?(::Business) && copilot_configurable.__getobj__.feature_flag_enabled_or_raise?(:enterprise_copilot_policies_refresh) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
          end

          sig { returns(T::Boolean) }
          def user?
            copilot_configurable.__getobj__.is_a?(::User)
          end

          sig { returns(T::Boolean) }
          def organization?
            copilot_configurable.__getobj__.is_a?(::Organization)
          end

          sig { returns(T::Boolean) }
          def render?
            true
          end

          sig { returns(T::Boolean) }
          def checked?
            return @checked unless @checked.nil?

            false
          end

          sig { returns(String) }
          def self.title
            T.must(self.name).demodulize.titleize.humanize
          end

          sig { returns(String) }
          def title
            self.class.title
          end

          sig { returns(T.nilable(Copilot::Types::MenuItemHashType)) }
          def to_h
            return unless render?

            {
              id: self.class.name.to_s,
              selected: checked?,
              title: title,
              description: description,
              value: value
            }
          end
        end
      end
    end
  end
end
