# typed: true
# frozen_string_literal: true

FactoryBot.define do
  T.bind(self, T.untyped)

  factory :sponsors_listing_featured_item do
    sponsors_listing
    featureable { create(:repository, owner: sponsors_listing&.sponsorable) }

    trait :featured_user do
      association :sponsors_listing, factory: [:sponsors_listing, :for_org]
      featureable do
        org = sponsors_listing&.sponsorable
        user = org&.admins&.first || org&.members&.first || create(:user)
        if sponsors_listing && sponsors_listing.featured_users.exists?(featureable_id: user.id)
          user = create(:user)
        end
        if org && !org.member?(user)
          org.add_member(user)
        end
        user
      end
    end

    trait :featured_sponsorship do
      association :sponsors_listing, factory: [:sponsors_listing, :for_org, :approved]
      featureable { create(:sponsorship, :paid, sponsorable: sponsors_listing&.sponsorable) }
    end
  end
end
