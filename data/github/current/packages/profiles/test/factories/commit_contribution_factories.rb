# typed: true
# frozen_string_literal: true

FactoryBot.define do
  T.bind(self, T.untyped)

  factory :commit_contribution do
    repository
    user
    committed_date { 1.day.from_now.to_date }
    commit_count { 5 }

    trait :with_summaries do
      after(:create) do |commit_contribution|
        summary_collection = CommitContributionSummary::Collection.new(repository: commit_contribution.repository)
        summary_collection.add(
          user_id: commit_contribution.user_id,
          date: commit_contribution.committed_date,
          count: [commit_contribution.commit_count, 1].max, # Handle User.ghost case
        )
        summary_collection.update!
      end
    end
  end

end
