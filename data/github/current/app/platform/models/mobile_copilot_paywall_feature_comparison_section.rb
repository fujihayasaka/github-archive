# typed: strict
# frozen_string_literal: true

module Platform
  module Models
    class MobileCopilotPaywallFeatureComparisonSection
      sig { params(hash: T::Hash[Symbol, T.untyped]).returns(MobileCopilotPaywallFeatureComparisonSection) }
      def self.from_hash(hash)
        # features can be of different types, so we need to handle that here.
        features = (hash[:features] || []).map do |item_hash|
          case item_hash[:type]
          when MobileCopilotPaywallChatModels::TYPE
            MobileCopilotPaywallChatModels.from_hash(item_hash)
          when MobileCopilotFeatureComparisonSubsection::TYPE
            MobileCopilotFeatureComparisonSubsection.from_hash(item_hash)
          else
            raise Platform::Errors::Internal, "Unknown feature type: #{item_hash[:type]}"
          end
        end

        new(
          title: hash[:title].to_s,
          features:
        )
      end

      sig { returns(String) }
      attr_reader :title

      sig { returns(T::Array[T.any(MobileCopilotFeatureComparisonSubsection, MobileCopilotPaywallChatModels)]) }
      attr_reader :features

      sig do
        params(
          title: String,
          features: T::Array[T.any(MobileCopilotFeatureComparisonSubsection, MobileCopilotPaywallChatModels)]
        ).void
      end
      def initialize(title:, features:)
        @title = title
        @features = features
      end

      sig { returns(T::Hash[Symbol, T.untyped]) }
      def to_hash
        {
          title:,
          features: features.map(&:to_hash)
        }
      end

      sig { params(other: MobileCopilotPaywallFeatureComparisonSection).returns(T::Boolean) }
      def eql?(other)
        self.class == other.class &&
          title == other.title &&
          features == other.features
      end
      alias :== eql?
    end
  end
end
