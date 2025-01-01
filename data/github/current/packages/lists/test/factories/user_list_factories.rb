# typed: true
# frozen_string_literal: true

FactoryBot.define do
  T.bind(self, T.untyped)

  factory :user_list do
    user  { create(:user) }
    transient do
      num_items { 0 }
    end

    sequence :name do |n|
      "#{Faker::Music.album}-#{n}"
    end

    after(:create) do |list, evaluator|
      create_list(:user_list_item, evaluator.num_items, user_list: list)
    end
  end
end
