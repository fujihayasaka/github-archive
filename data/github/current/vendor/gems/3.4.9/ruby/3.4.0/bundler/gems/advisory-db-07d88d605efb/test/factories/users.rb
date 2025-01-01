# frozen_string_literal: true

FactoryBot.define do
  factory :user do
    login { SecureRandom.hex(10) }
  end
end
