# frozen_string_literal: true

FactoryBot.define do
  factory :advisory_review do
    ghsa_id
    cve_id
    white_source_id { nil }
    npm_id { nil }
    advisory_payload { build(:advisory_payload, summary: summary, description: description) }

    transient do
      feed_entry_count { 1 }
      feed_entry_type { nil }
      approval_count { 0 }
      assign_curator { false }
      create_advisory { false }
      summary { build(:summary) }
      description { build(:description) }
    end

    after(:create) do |advisory_review, evaluator|
      if evaluator.feed_entry_type
        feed_entry = create evaluator.feed_entry_type,
          advisory_review: advisory_review,
          cve_id: advisory_review.cve_id, # ensure consistency b/t feed entry and advisory review for cve id
          white_source_id: advisory_review.white_source_id,
          advisory_payload: advisory_review.advisory_payload,
          ghsa_id: evaluator.feed_entry_type == :repository_advisory_feed_entry ? advisory_review.ghsa_id : nil # ensure consistency b/t feed entry and advisory review for repo advisory feeds

        advisory_review.update cve_id: feed_entry.cve_id,
          white_source_id: feed_entry.white_source_id,
          friends_of_php_id: feed_entry.friends_of_php_id,
          rubysec_id: feed_entry.rubysec_id,
          rustsec_id: feed_entry.rustsec_id
      else
        evaluator.feed_entry_count.times do
          create(:feed_entry, advisory_review: advisory_review)
        end
      end

      evaluator.approval_count.times do
        create(:advisory_review_approval, :approved, advisory_review_id: advisory_review.id)
      end

      if evaluator.assign_curator
        create(:advisory_review_approval, advisory_review_id: advisory_review.id, user_id: create(:user).id)
      end

      if evaluator.create_advisory && !Advisory.exists?(ghsa_id: advisory_review.ghsa_id)
        create(:advisory, ghsa_id: advisory_review.ghsa_id, cve_id: advisory_review.cve_id, white_source_id: advisory_review.white_source_id, nvd_published_at: advisory_review.nvd_published_at)
      end
    end

    factory :overlapping_advisory_review do
      cve_id

      after(:create) do |advisory_review|
        other_advisory_review = create(:advisory_review, cve_id: nil, feed_entry_count: 0)
        create(:feed_entry, advisory_review: other_advisory_review, cve_id: advisory_review.cve_id)
      end
    end

    trait :with_cvss_v3 do
      advisory_payload do
        build(
          :advisory_payload,
          summary: summary,
          description: description,
          cvss_v3: "CVSS:3.1/AV:N/AC:H/PR:L/UI:N/S:U/C:H/I:N/A:N",
          cvss_v4: "",
          severity: "moderate",
        )
      end
    end

    trait :with_cvss_v4 do
      advisory_payload do
        build(
          :advisory_payload,
          summary: summary,
          description: description,
          cvss_v3: "",
          cvss_v4: "CVSS:4.0/AV:N/AC:L/AT:N/PR:N/UI:N/VC:L/VI:L/VA:L/SC:H/SI:H/SA:H",
          severity: "high",
        )
      end
    end

    trait :manual do
      in_review
      feed_entry_count { 0 }
    end

    trait :open do
      state { "open" }
    end

    trait :closed do
      state { "closed" }
    end

    trait :accepted do
      state { "accepted" }
      create_advisory { true }
    end

    trait :rejected do
      state { "rejected" }
    end

    trait :in_review do
      state { "in_review" }
    end

    trait :curation_state_waiting do
      state { "in_review" }
      feed_entry_count { 1 }
      feed_entry_type { :cve_review_feed_entry }
    end

    trait :curation_state_open do
      state { "in_review" }
      feed_entry_count { 1 }
      feed_entry_type { :cve_feed_entry }
    end

    trait :curation_state_open_create do
      curation_state_open
      create_advisory { false }
    end

    trait :curation_state_open_update do
      curation_state_open
      approval_count { 2 }
      create_advisory { true }
    end

    trait :curation_state_ready_to_publish do
      curation_state_open_create
      approval_count { 1 }
      state { "approved_to_publish" }
    end

    trait :curation_state_ready_to_withdraw do
      curation_state_open_update
      approval_count { 1 }
      state { "approved_to_withdraw" }
    end

    trait :curation_state_published do
      state { "accepted" }
      approval_count { 2 }
      create_advisory { true }
    end

    trait :curation_state_published_unreviewed do
      curation_state_published
      approval_count { 0 }
      after(:create) { |advisory_review| advisory_review.advisory.update(reviewed: false, reviewed_at: nil) }
    end

    trait :curation_state_withdrawn do
      curation_state_published
      after(:create) { |advisory_review| advisory_review.advisory.withdraw }
    end

    trait :curation_state_closed do
      state { "rejected" }
    end

    trait :ml_filtered do
      closed
      feed_entry_count { 1 }
      after(:create) do |advisory_review|
        advisory_review.reload.feed_entries.first.update! ml_reject_prediction: "reject"
      end
    end

    trait :ai_predict do
      advisory_payload { build(:advisory_payload, summary: "Out-of-bounds write", description: "A remote code execution vulnerability exists in the way that the Chakra scripting engine handles objects in memory in Microsoft Edge, aka 'Chakra Scripting Engine Memory Corruption Vulnerability'. This CVE ID is unique from CVE-2019-0912, CVE-2019-0913, CVE-2019-0914, CVE-2019-0915, CVE-2019-0916, CVE-2019-0917, CVE-2019-0922, CVE-2019-0924, CVE-2019-0925, CVE-2019-0927, CVE-2019-0933, CVE-2019-0937.") }
    end
  end
end
