# typed: strict
# frozen_string_literal: true

module Platform
  module Models
    class MobileCopilotFeatureComparisonSubsectionItem
      sig { params(hash: T::Hash[Symbol, T.untyped]).returns(MobileCopilotFeatureComparisonSubsectionItem) }
      def self.from_hash(hash)
        new(
          copilot_license_type: hash[:copilot_license_type].to_s,
          plan_title: hash[:plan_title].to_s,
          icon: hash[:icon].to_s,
          subtitle: hash[:subtitle]
        )
      end

      sig { returns(String) }
      attr_reader :copilot_license_type

      sig { returns(String) }
      attr_reader :plan_title

      sig { returns(String) }
      attr_reader :icon

      sig { returns(T.nilable(String)) }
      attr_reader :subtitle

      sig do
        params(
          copilot_license_type: String,
          plan_title: String,
          icon: String,
          subtitle: T.nilable(String)
        ).void
      end
      def initialize(copilot_license_type:, plan_title:, icon:, subtitle: nil)
        @copilot_license_type = copilot_license_type
        @plan_title = plan_title
        @icon = icon
        @subtitle = subtitle
      end

      sig { returns(T::Hash[Symbol, T.untyped]) }
      def to_hash
        {
          copilot_license_type:,
          plan_title:,
          icon:,
          subtitle:
        }
      end

      sig { params(other: MobileCopilotFeatureComparisonSubsectionItem).returns(T::Boolean) }
      def eql?(other)
        self.class == other.class &&
          copilot_license_type == other.copilot_license_type &&
          plan_title == other.plan_title &&
          icon == other.icon &&
          subtitle == other.subtitle
      end
      alias :== eql?
    end
  end
end
