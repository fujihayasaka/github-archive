# typed: strict
# frozen_string_literal: true

module Mobile
  module Copilot
    module Paywall
      class ChatModelPlan
        sig { params(hash: T::Hash[Symbol, T.untyped]).returns(ChatModelPlan) }
        def self.from_hash(hash)
          new(
            copilot_license_type: hash[:copilot_license_type].to_s,
            title: hash[:title].to_s,
            models: (hash[:models] || []).map { |model_hash| ChatModel.from_hash(model_hash) }
          )
        end

        sig { returns(String) }
        attr_reader :copilot_license_type

        sig { returns(String) }
        attr_reader :title

        sig { returns(T::Array[ChatModel]) }
        attr_reader :models

        sig do
          params(
            copilot_license_type: String,
            title: String,
            models: T::Array[ChatModel]
          ).void
        end
        def initialize(copilot_license_type:, title:, models:)
          @copilot_license_type = copilot_license_type
          @title = title
          @models = models
        end

        sig { returns(T::Hash[Symbol, T.untyped]) }
        def to_hash
          {
            copilot_license_type:,
            title:,
            models: models.map(&:to_hash)
          }
        end

        sig { params(other: ChatModelPlan).returns(T::Boolean) }
        def eql?(other)
          self.class == other.class &&
            copilot_license_type == other.copilot_license_type &&
            title == other.title &&
            models == other.models
        end
        alias :== eql?
      end
    end
  end
end
