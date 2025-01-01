# frozen_string_literal: true

FactoryBot.define do
  factory :label do
    name { "Do not publish #{Label.count}" }
  end
end
