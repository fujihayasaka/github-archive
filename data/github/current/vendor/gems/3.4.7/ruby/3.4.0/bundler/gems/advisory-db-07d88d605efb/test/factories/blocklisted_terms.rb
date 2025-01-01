# frozen_string_literal: true

FactoryBot.define do
  factory :blocklisted_term do
    pattern { SecureRandom.hex }
    level { "warn" }
  end
end
