# typed: strict
# frozen_string_literal: true

module Copilot
  class ModelsRegistry < ApplicationRecord::Copilot
    # Eventually this will be pulled from the models registry API and cached. For now
    # we will use a static hash we define here.
    # Each record should have:

    # key: unversioned model name,
    # name: public facing model name,
    # description: description of the model,
    # plans: an array of plans that this model is available on
    # feature_flag: the feature flag that enables this model
    # internal: boolean indicating if this model is internal only
    MODELS = T.let(
      [
        {
          key: "internal-model",
          name: "Internal Model",
          description: "An internal only model for testing.",
          plans: %w(copilot_free copilot_pro copilot_pro_plus copilot_business copilot_enterprise),
          feature_flag: "",
          internal: true,
        }
      ].freeze, T::Array[T::Hash[Symbol, T.any(String, T::Boolean)]])

    sig { returns(T::Array[String]) }
    def self.model_keys
      MODELS.map { |model| model[:key].to_s }.reject(&:empty?)
    end

    sig { params(key: String).returns(T.nilable(T::Hash[Symbol, T.any(String, T::Boolean)])) }
    def self.model(key)
      MODELS.find { |model| model[:key] == key }
    end
  end
end
