# typed: true
# frozen_string_literal: true

FactoryBot.define do
  T.bind(self, T.untyped)

  factory :sponsors_agreement do
    body do
      parts = [
        Faker::Lorem.paragraphs(number: 2),
        "## 1. #{Faker::Lorem.sentence}",
        Faker::Lorem.paragraph,
        "## 2. #{Faker::Lorem.sentence}",
        "(a) #{Faker::Lorem.paragraph}",
        "(b) #{Faker::Lorem.paragraph}",
        "(c) #{Faker::Lorem.paragraph}",
        "## 3. #{Faker::Lorem.sentence}",
        "(a) **#{Faker::Lorem.word}** #{Faker::Lorem.paragraph}",
        "(b) **#{Faker::Lorem.word}** #{Faker::Lorem.paragraph}",
        "## 4. #{Faker::Lorem.sentence}",
        "**#{Faker::Lorem.paragraph.upcase}**",
        "## 5. #{Faker::Lorem.sentence}",
        Faker::Lorem.paragraph,
        "- #{Faker::Lorem.sentence}",
        "- #{Faker::Lorem.sentence}",
        "- #{Faker::Lorem.sentence}",
        Faker::Lorem.paragraph,
      ]
      parts.join("\n\n")
    end
    sequence(:version, "v00001")

    trait :optional_data_provision do
      kind { :optional_data_provision }
    end

    trait :invoiced_sponsor do
      kind { :invoiced_sponsor }
    end
  end
end
