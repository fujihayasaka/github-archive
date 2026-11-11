# frozen_string_literal: true

FactoryBot.define do
  factory :ai_prediction do
    ai_model { "gpt-4" }
    advisory_review { create(:advisory_review, :ai_predict) }
    predicted_ecosystems { ["npm"] }
    predicted_packages { ["lodash"] }

    factory :ai_prediction_gpt4o do
      ai_model { "gpt-4o-2024-05-13" }
    end
  end
end
