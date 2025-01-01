# typed: true
# frozen_string_literal: true

FactoryBot.define do
  T.bind(self, T.untyped)

  factory :repository_sponsorable do
    sponsorable { create(:user, :sponsorable) }
    repository { create(:repository, owner: sponsorable) }
    source { :owner }

    trait :owner do
      source { :owner }
    end

    trait :funding_file do
      repository { create(:repository_preferred_file, :funding).repository }
      source { :repo_funding_file }
    end

    trait :global_funding_file do
      repository do
        org = create(:organization)
        create(:repository, owner: org, name: Repository::GLOBAL_HEALTH_FILES_NAME, from_example: :funding_links)
        create(:repository, owner: org)
      end
      source { :global_funding_file }
    end
  end
end
