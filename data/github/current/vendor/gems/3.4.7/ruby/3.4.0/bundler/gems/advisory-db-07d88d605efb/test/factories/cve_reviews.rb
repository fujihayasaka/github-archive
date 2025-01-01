# frozen_string_literal: true

FactoryBot.define do
  factory :cve_review do
    ghsa_id
    decision { "undecided" }
    assigned_cve_id { nil }
    confirm_reference { "https://github.com/testorg/testrepo/security/advisories/#{ghsa_id}" }
    comment { "" }
    title { "Untitled" }

    transient do
      num_cve_requests { 1 }
      cve_request_title { "test repository advisory title" }
    end

    after(:create) do |cve_review, evaluator|
      evaluator.num_cve_requests.times do
        create :cve_request, ghsa_id: cve_review.ghsa_id, title: evaluator.cve_request_title
      end
    end

    trait :undecided

    trait :not_assigned do
      decision { "not_assigned" }
      assigned_cve_id { nil }
      comment { "This is a test reject reason" }
    end

    trait :assigned do
      decision { "assigned" }
      assigned_cve_id { generate(:cve_id) }
      comment { "this request was assigned a CVE ID" }
    end

    factory :open_cve_review, traits: [:open] do
      factory :undecided_cve_review

      factory :not_assigned_cve_review, traits: [:not_assigned]

      factory :assigned_cve_review, traits: [:assigned]
    end

    trait :open do
      state { "open" }
    end

    trait :notified do
      state { "notified" }
    end

    trait :submitted do
      state { "submitted" }
    end

    trait :rejected do
      state { "rejected" }
    end

    trait :open_update do
      state { "open_update" }
    end

    trait :curation_state_in_triage do
      open
    end

    trait :curation_state_waiting do
      notified
      assigned
    end

    trait :curation_state_open do
      curation_state_waiting
      repository_advisory_published
    end

    trait :curation_state_published do
      submitted
      assigned
      repository_advisory_published
      after(:create) do |cve_review|
        create(:mitre_cve_submission, ghsa_id: cve_review.ghsa_id, cve_review: cve_review)
      end
    end

    trait :curation_state_closed do
      notified
      not_assigned
    end

    trait :curation_state_rejected do
      rejected
      assigned
      repository_advisory_published
    end

    trait :curation_state_open_update do
      open_update
      assigned
      repository_advisory_published
      after(:create) do |cve_review|
        create(:mitre_cve_submission, ghsa_id: cve_review.ghsa_id, cve_review: cve_review)
      end
    end

    trait :all_fields_populated do
      title { "Test title for a test CVE Review" }
      description do
        <<~DESCRIPTION.chomp
          Description line 1.
          And here is line 2.

          And this is paragraph2
        DESCRIPTION
      end
      vendor_name { "GitHubOrgName" }
      product { "SoftwareWithVulnerablity" }
      version_values do
        [
          "< 1.2.3",
          ">= 2.0.0, < 2.3.4",
        ]
      end
      problemtype_values do
        [
          "CWE-20: Improper Input Validation",
          "Custom problem type with any ol text here",
        ]
      end
      confirm_reference { "https://github.com/testorg/testreponame/security/advisories/#{ghsa_id}" }
      misc_references do
        [
          "https://hackerone.com/reports/123456789",
          "https://github.com/github/github/commit/abc1233cf1be456109866dbed4be6f2cb9be3a74",
        ]
      end
      cvss_vectorString { "CVSS:3.1/AV:N/AC:L/PR:L/UI:R/S:C/C:H/I:L/A:N" }
      comment do
        <<~COMMENT.chomp
          Line one of the comment.
          Line two of the comment.

          Paragraph two of the comment
        COMMENT
      end
    end

    trait :repository_advisory_published do
      advisory_review { create(:advisory_review, ghsa_id: ghsa_id, cve_id: assigned_cve_id, feed_entry_type: :repository_advisory_feed_entry) }
    end
  end
end
