# typed: strict
# frozen_string_literal: true

module Platform
  module Models
    class MobileCopilotPaywallChatModels
      TYPE = "chat_models"

      sig { params(hash: T::Hash[Symbol, T.untyped]).returns(MobileCopilotPaywallChatModels) }
      def self.from_hash(hash)
        new(
          title: hash[:title].to_s,
          plans: (hash[:plans] || []).map { |plan_hash| MobileCopilotPaywallChatModelPlan.from_hash(plan_hash) }
        )
      end

      sig { returns(String) }
      attr_reader :title

      sig { returns(T::Array[MobileCopilotPaywallChatModelPlan]) }
      attr_reader :plans

      sig do
        params(
          title: String,
          plans: T::Array[MobileCopilotPaywallChatModelPlan]
        ).void
      end
      def initialize(title:, plans:)
        @title = title
        @plans = plans
      end

      sig { returns(T::Hash[Symbol, T.untyped]) }
      def to_hash
        {
          type: TYPE,
          title:,
          plans: plans.map(&:to_hash)
        }
      end

      sig { params(other: MobileCopilotPaywallChatModels).returns(T::Boolean) }
      def eql?(other)
        self.class == other.class &&
          title == other.title &&
          plans == other.plans
      end
      alias :== eql?
    end
  end
end
