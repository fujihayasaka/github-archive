# typed: true
# frozen_string_literal: true

FactoryBot.define do
  T.bind(self, T.untyped)

  factory :sponsorship_newsletter_tier do
    transient do
      tier { nil }
    end

    sponsorship_newsletter

    before(:create) do |object, evaluator|
      listing = object.sponsorship_newsletter.sponsors_listing
      object.sponsors_tier = evaluator.tier || listing&.default_tier
      if object.sponsors_tier.nil? && listing
        object.sponsors_tier = create(:sponsors_tier, :published, sponsors_listing: listing)
      end
    end
  end
end
