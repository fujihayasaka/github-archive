# typed: strict
# frozen_string_literal: true

module Mobile
  module Copilot
    module Paywall
      class ChatModels
        TYPE = "chat_models"

        sig { params(hash: T::Hash[Symbol, T.untyped]).returns(ChatModels) }
        def self.from_hash(hash)
          new(
            title: hash[:title].to_s,
            plans: (hash[:plans] || []).map { |plan_hash| ChatModelPlan.from_hash(plan_hash) }
          )
        end

        sig { returns(String) }
        attr_reader :title

        sig { returns(T::Array[ChatModelPlan]) }
        attr_reader :plans

        sig do
          params(
            title: String,
            plans: T::Array[ChatModelPlan]
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

        sig { params(other: ChatModels).returns(T::Boolean) }
        def eql?(other)
          self.class == other.class &&
            title == other.title &&
            plans == other.plans
        end
        alias :== eql?
      end
    end
  end
end
