# typed: true
# frozen_string_literal: true

FactoryBot.define do
  T.bind(self, T.untyped)

  factory :sponsorship_repository do
    sponsors_tier { create(:sponsors_tier, :approved_sponsors_listing) }
    sponsorable { sponsors_tier&.sponsorable || create(:user, :sponsorable) }
    repository do
      org = if sponsorable&.organization?
        sponsorable
      elsif sponsorable
        create(:organization, admin: sponsorable)
      else
        create(:organization)
      end
      repo = create(:repository, :private, owner: org, name: "sponsors-only-repo-#{SecureRandom.hex(3)}")
      repo.add_member(sponsorable, action: :admin) if sponsorable&.user?
      repo
    end
    sponsor { create(:sponsorship, tier: sponsors_tier, sponsorable: sponsors_tier&.sponsorable).sponsor }

    before(:create) do |sponsorship_repo|
      if sponsorship_repo.sponsors_tier && sponsorship_repo.sponsorable && sponsorship_repo.sponsor
        sponsorship = Sponsorship.active.with_tier(sponsorship_repo.sponsors_tier_id)
          .from_sponsor(sponsorship_repo.sponsor_id)
        unless sponsorship.exists?
          create(:sponsorship, tier: sponsorship_repo.sponsors_tier, sponsorable: sponsorship_repo.sponsorable,
            sponsor: sponsorship_repo.sponsor)
        end
      end
    end
  end
end
