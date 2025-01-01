# frozen_string_literal: true

require "test_helper"

class ApplyBlocklistJobTest < ActiveJob::TestCase
  test "blocklists advisory reviews with matching descriptions" do
    pattern = SecureRandom.hex
    blocklisted_term = create(:blocklisted_term, pattern: pattern)
    matching_advisory_payload = create(:advisory_payload, description: "foo #{pattern} baz")
    advisory_review = create(:advisory_review, :open, advisory_payload: matching_advisory_payload)
    create(:advisory_review, :open)

    assert_difference -> { BlocklistMatch.count }, 1 do
      ApplyBlocklistJob.new.perform
    end

    blocklist_match = BlocklistMatch.last
    assert_equal blocklisted_term, blocklist_match.blocklisted_term
    assert_equal advisory_review, blocklist_match.advisory_review
  end

  test "considers the advisory review's summary" do
    pattern = SecureRandom.hex
    blocklisted_term = create(:blocklisted_term, pattern: pattern)
    matching_advisory_payload = create(:advisory_payload, summary: "foo #{pattern} baz")
    advisory_review = create(:advisory_review, :open, advisory_payload: matching_advisory_payload)
    create(:advisory_review, :open)

    assert_difference -> { BlocklistMatch.count }, 1 do
      ApplyBlocklistJob.new.perform
    end

    blocklist_match = BlocklistMatch.last
    assert_equal blocklisted_term, blocklist_match.blocklisted_term
    assert_equal advisory_review, blocklist_match.advisory_review
  end

  test "blocklist terms are not added when it doesn't match" do
    pattern = "cve@github.com"
    create(:blocklisted_term, pattern: pattern, level: "remove", term_type: "cna")
    advisory_review = create(:advisory_review, :open)
    create(:cve_feed_entry, :subject_to_blocklist, advisory_review: advisory_review, raw_payload: {
      sourceIdentifier: "cve1@github.com",
    })

    assert_difference -> { BlocklistMatch.count }, 0 do
      ApplyBlocklistJob.new.perform
    end

    assert_nil BlocklistMatch.last
  end

  test "blocklist can be applied by type:cna for API 1.0 raw payloads" do
    pattern = "cve@github.com"
    blocklisted_term = create(:blocklisted_term, pattern: pattern, level: "remove", term_type: "cna")
    advisory_review = create(:advisory_review, :open)
    create(:cve_feed_entry, :subject_to_blocklist, :api_v1, advisory_review: advisory_review, raw_payload: {
      sourceIdentifier: "cve@github.com",
    })

    assert_difference -> { BlocklistMatch.count }, 1 do
      ApplyBlocklistJob.new.perform
    end

    blocklist_match = BlocklistMatch.last
    assert_equal blocklisted_term, blocklist_match.blocklisted_term
    assert_equal advisory_review, blocklist_match.advisory_review
  end

  test "blocklist can be applied by type:cna for API 2.0 raw payloads" do
    pattern = "cve@github.com"
    blocklisted_term = create(:blocklisted_term, pattern: pattern, level: "remove", term_type: "cna")
    advisory_review = create(:advisory_review, :open)
    create(:cve_feed_entry, :subject_to_blocklist, advisory_review: advisory_review, raw_payload: {
      sourceIdentifier: "cve@github.com",
    })

    assert_difference -> { BlocklistMatch.count }, 1 do
      ApplyBlocklistJob.new.perform
    end

    blocklist_match = BlocklistMatch.last
    assert_equal blocklisted_term, blocklist_match.blocklisted_term
    assert_equal advisory_review, blocklist_match.advisory_review
  end

  test "blocklist can be applied by type:cpe for API 1.0 raw payloads" do
    pattern = "cpe:2.3:a:ibm:security_verify_access:*:*:*:*:*:*:*:*"
    blocklisted_term = create(:blocklisted_term, pattern: pattern, level: "remove", term_type: "cpe")
    advisory_review = create(:advisory_review, :open)
    create(:cve_feed_entry, :subject_to_blocklist, :api_v1, advisory_review: advisory_review,
      raw_payload: {
        CVE_data_version: "4.0",
        configurations: {
          nodes: [{
            operator: "OR",
            cpe_match: [{
              vulnerable: true,
              cpe23Uri: "cpe:2.3:a:ibm:security_verify_access:*:*:*:*:*:*:*:*",
            }, {
              vulnerable: true,
              cpe23Uri: "cpe:2.3:a:ibm:security_verify_access:*:*:*:*:*:*:*:*",
            }],
          }],
        },
      })

    assert_difference -> { BlocklistMatch.count }, 1 do
      ApplyBlocklistJob.new.perform
    end

    blocklist_match = BlocklistMatch.last
    assert_equal blocklisted_term, blocklist_match.blocklisted_term
    assert_equal advisory_review, blocklist_match.advisory_review
  end

  test "blocklist can be applied by type:cpe for API 2.0 raw_payloads" do
    pattern = "cpe:2.3:a:adobe:after_effects:*:*:*:*:*:*:*:*"
    blocklisted_term = create(:blocklisted_term, pattern: pattern, level: "remove", term_type: "cpe")
    advisory_review = create(:advisory_review, :open)
    create(:cve_feed_entry, :subject_to_blocklist, advisory_review: advisory_review, raw_payload: {
      configurations: [{
        operator: "AND",
        nodes: [{
          operator: "OR",
          negate: false,
          cpeMatch: [
            {
              vulnerable: true,
              criteria: "cpe:2.3:a:adobe:after_effects:*:*:*:*:*:*:*:*",
              versionStartIncluding: "18.0",
              versionEndExcluding: "18.4.5",
              matchCriteriaId: "7A19CF14-F244-4D2D-9792-F248D2157E7B",
            },
            {
              vulnerable: true,
              criteria: "cpe:2.3:a:adobe:after_effects:*:*:*:*:*:*:*:*",
              versionStartIncluding: "22.0",
              versionEndExcluding: "22.2.1",
              matchCriteriaId: "B618F268-1E4A-4C60-AB75-3F4055489C74",
            },
          ],
        }],
      }],
    })

    assert_difference -> { BlocklistMatch.count }, 1 do
      ApplyBlocklistJob.new.perform
    end

    blocklist_match = BlocklistMatch.last
    assert_equal blocklisted_term, blocklist_match.blocklisted_term
    assert_equal advisory_review, blocklist_match.advisory_review
  end

  test "considers NVD feed entry descriptions" do
    pattern = SecureRandom.hex
    blocklisted_term = create(:blocklisted_term, pattern: pattern)
    matching_advisory_payload = create(:advisory_payload, description: "foo #{pattern} baz")
    advisory_review = create(:advisory_review, :open)
    create(:feed_entry, :subject_to_blocklist, advisory_review: advisory_review, advisory_payload: matching_advisory_payload)
    create(:advisory_review, :open)

    assert_difference -> { BlocklistMatch.count }, 1 do
      ApplyBlocklistJob.new.perform
    end

    blocklist_match = BlocklistMatch.last
    assert_equal blocklisted_term, blocklist_match.blocklisted_term
    assert_equal advisory_review, blocklist_match.advisory_review
  end

  test "considers NVD feed entry summaries" do
    pattern = SecureRandom.hex
    blocklisted_term = create(:blocklisted_term, pattern: pattern)
    matching_advisory_payload = create(:advisory_payload, summary: "foo #{pattern} baz")
    advisory_review = create(:advisory_review, :open)
    create(:feed_entry, :subject_to_blocklist, advisory_review: advisory_review, advisory_payload: matching_advisory_payload)
    create(:advisory_review, :open)

    assert_difference -> { BlocklistMatch.count }, 1 do
      ApplyBlocklistJob.new.perform
    end

    blocklist_match = BlocklistMatch.last
    assert_equal blocklisted_term, blocklist_match.blocklisted_term
    assert_equal advisory_review, blocklist_match.advisory_review
  end

  test "ignores non-NVD feed entry descriptions" do
    pattern = SecureRandom.hex
    create(:blocklisted_term, pattern: pattern)
    matching_advisory_payload = create(:advisory_payload, description: "foo #{pattern} baz")
    advisory_review = create(:advisory_review, :open)
    create(:feed_entry, source: "munger", advisory_review: advisory_review, advisory_payload: matching_advisory_payload)
    create(:advisory_review, :open)

    assert_no_difference -> { BlocklistMatch.count } do
      ApplyBlocklistJob.new.perform
    end
  end

  test "ignores non-NVD feed entry summaries" do
    pattern = SecureRandom.hex
    create(:blocklisted_term, pattern: pattern)
    matching_advisory_payload = create(:advisory_payload, summary: "foo #{pattern} baz")
    advisory_review = create(:advisory_review, :open)
    create(:feed_entry, source: "munger", advisory_review: advisory_review, advisory_payload: matching_advisory_payload)
    create(:advisory_review, :open)

    assert_no_difference -> { BlocklistMatch.count } do
      ApplyBlocklistJob.new.perform
    end
  end

  test "removes outdated blocklist matches" do
    advisory_review = create(:advisory_review, :open)
    create(:blocklist_match, advisory_review: advisory_review)
    create(:advisory_review, :open)

    assert_difference -> { BlocklistMatch.count }, -1 do
      ApplyBlocklistJob.new.perform
    end
  end

  test "state change for advisory reviews that match blocklist removal" do
    pattern = SecureRandom.hex
    term = create(:blocklisted_term, pattern: pattern)
    matching_advisory_payload = create(:advisory_payload, description: "foo #{pattern} baz")
    advisory_review = create(:advisory_review, :open, advisory_payload: matching_advisory_payload)

    assert_no_changes -> { advisory_review.reload.state } do
      ApplyBlocklistJob.new.perform
    end

    term.update(level: "remove")

    assert_changes -> { advisory_review.reload.state }, to: "closed" do
      ApplyBlocklistJob.new.perform
    end
  end

  test "no state change for advisory reviews that don't match the blocklist" do
    advisory_review = create(:advisory_review, :closed)
    create(:blocklist_match, advisory_review: advisory_review)

    assert_no_changes -> { advisory_review.reload.state } do
      ApplyBlocklistJob.new.perform
    end
  end
end
