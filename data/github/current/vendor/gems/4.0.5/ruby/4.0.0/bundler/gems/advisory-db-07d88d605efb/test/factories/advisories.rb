# frozen_string_literal: true

FactoryBot.define do
  factory :advisory do
    ghsa_id
    published_at { 1.second.ago }
    reviewed_at { 1.second.ago }
    cve_id { nil }
    white_source_id { nil }
    npm_id { nil }

    # create an associated advisory review, and ensure its IDs match this advisory
    advisory_review do
      unless AdvisoryReview.exists?(ghsa_id: ghsa_id)
        create(
          :advisory_review,
          :accepted,
          create_advisory: false,
          ghsa_id: ghsa_id,
          cve_id: cve_id,
          white_source_id: white_source_id,
          npm_id: npm_id,
        )
      end
    end

    summary { build(:summary) }
    description { build(:description) }
    severity
    source_code_location { nil }

    trait :withdrawn do
      withdrawn_at { 1.second.ago }
    end

    transient do
      reference_count { 1 }
      vulnerability_count { 1 }
    end

    after(:create) do |advisory, evaluator|
      created_at = advisory.created_at
      updated_at = advisory.updated_at

      evaluator.reference_count.times do
        create(:reference, advisory: advisory, created_at: created_at, updated_at: updated_at)
      end

      evaluator.vulnerability_count.times do
        create(:vulnerability, advisory: advisory, created_at: created_at, updated_at: updated_at)
      end

      advisory.update_columns(created_at: created_at, updated_at: updated_at)
    end

    factory :unreviewed_advisory do
      summary { nil }
      severity { nil }
      reviewed { false }
      reviewed_at { nil }
      vulnerability_count { 0 }
    end
  end
end
