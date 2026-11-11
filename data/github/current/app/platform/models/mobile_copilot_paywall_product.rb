# typed: strict
# frozen_string_literal: true

module Platform
  module Models
    class MobileCopilotPaywallProduct
      sig { params(hash: T::Hash[Symbol, T.untyped]).returns(MobileCopilotPaywallProduct) }
      def self.from_hash(hash)
        new(
          title: hash[:title].to_s,
          subtitle: hash[:subtitle],
          features_header: hash[:features_header].to_s,
          copilot_license_type: hash[:copilot_license_type].to_s,
          features: (hash[:features] || []).map { |f| MobileCopilotPaywallProductFeature.from_hash(f) }
        )
      end

      sig { returns(String) }
      attr_reader :title

      sig { returns(T.nilable(String)) }
      attr_reader :subtitle

      sig { returns(String) }
      attr_reader :features_header

      sig { returns(String) }
      attr_reader :copilot_license_type

      sig { returns(T::Array[Platform::Models::MobileCopilotPaywallProductFeature]) }
      attr_reader :features

      sig do
        params(
          title: String,
          subtitle: T.nilable(String),
          features_header: String,
          copilot_license_type: String,
          features: T::Array[Platform::Models::MobileCopilotPaywallProductFeature]
        ).void
      end
      def initialize(title:, subtitle:, features_header:, copilot_license_type:, features:)
        @title = title
        @subtitle = subtitle
        @features_header = features_header
        @copilot_license_type = copilot_license_type
        @features = features
      end

      sig { returns(T::Hash[Symbol, T.untyped]) }
      def to_hash
        {
          title:,
          subtitle:,
          features_header:,
          copilot_license_type:,
          features: features.map(&:to_hash)
        }
      end

      sig { params(other: MobileCopilotPaywallProduct).returns(T::Boolean) }
      def eql?(other)
        self.class == other.class &&
          title == other.title &&
          subtitle == other.subtitle &&
          features_header == other.features_header &&
          copilot_license_type == other.copilot_license_type &&
          features == other.features
      end
      alias :== eql?
    end
  end
end
