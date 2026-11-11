# frozen_string_literal: true

FactoryBot.define do
  factory :feed_entry do
    source
    ghsa_id { nil }
    cve_id { nil }
    white_source_id { nil }
    friends_of_php_id { nil }
    rubysec_id { nil }
    rustsec_id { nil }
    identifier { "#{source}:#{SecureRandom.uuid}" }
    raw_payload { Faker::Types.complex_rb_hash(number: 20).deep_stringify_keys }

    transient do
      # use advisory_payload_overrides to change anything in the advisory payload
      advisory_payload_overrides do
        {}
      end
    end

    advisory_payload { create(:advisory_payload, advisory_payload_overrides) }

    FeedEntry.resolution_states.each do |name, value|
      trait(name.to_sym) do
        resolution_state { value }
      end
    end

    trait :subject_to_blocklist do
      source { AdvisoryDB.sources_subject_to_blocklist.sample }
    end

    factory :cve_feed_entry do
      source { "nvd" }
      cve_id { "CVE-5555-1234" }
      advisory_payload { create(:cve_advisory_payload, advisory_payload_overrides) }

      after(:build) do |_feed_entry, evaluator|
        evaluator.raw_payload["published"] = 1.minute.ago.strftime("%FT%RZ")
        evaluator.raw_payload.merge(Faker::Types.complex_rb_hash(number: 20).deep_stringify_keys)

        evaluator.raw_payload = evaluator.raw_payload.deep_stringify_keys
      end

      trait :api_v1 do
        after(:build) do |_, evaluator|
          evaluator.raw_payload["CVE_data_version"] = "1.0"
        end
      end
    end

    # WhiteSource was used an importer/source for some time, but was removed
    # There are still WhiteSource feed entries in production, and thus the data is kept here
    factory :white_source_feed_entry do
      source { "white_source" }
      white_source_id { "WS-1234-1234" }
    end

    factory :friends_of_php_feed_entry do
      source { "friends_of_php" }
      friends_of_php_id { "api-platform/core/CVE-2019-1000011.yaml" }
      advisory_payload { create(:friends_of_php_advisory_payload, advisory_payload_overrides) }
    end

    factory :rubysec_feed_entry do
      source { "rubysec" }
      rubysec_id { "gems/yard/CVE-2019-1020001.yml" }
      advisory_payload { create(:rubysec_advisory_payload, advisory_payload_overrides) }
    end

    factory :rustsec_feed_entry do
      source { "rustsec" }
      rustsec_id { "crates/nanorand/RUSTSEC-2020-0089.yml" }
      advisory_payload { create(:rustsec_advisory_payload, advisory_payload_overrides) }
    end

    factory :repository_advisory_feed_entry do
      source { "repository_advisories" }
      ghsa_id
    end

    factory :cve_review_feed_entry do
      source { "cve_review" }
      ghsa_id
    end

    factory :advisory_improvement_feed_entry do
      source { "advisory_improvement" }
      transient do
        pr_number { 3 }
      end
      raw_payload { Faker::Types.complex_rb_hash(number: 20).deep_stringify_keys.merge("pr_number" => pr_number) }
    end

    factory :malware_feed_entry do
      source { "malware_advisory" }
      advisory_payload { create(:malware_advisory_payload) }
    end
  end
end
