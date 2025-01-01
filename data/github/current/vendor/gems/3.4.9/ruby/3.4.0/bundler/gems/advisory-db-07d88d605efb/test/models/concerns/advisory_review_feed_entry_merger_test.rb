# frozen_string_literal: true

require "test_helper"

class AdvisoryReviewFeedEntryMergerTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  # tests on data transfer
  test "creates an advisory review when it does not exist" do
    feed_entries = Array.new(3) { |i| create(:feed_entry, cve_id: "CVE-5555-123#{i}") }

    assert_difference -> { AdvisoryReview.count }, 3 do
      feed_entries.each do |feed_entry|
        AdvisoryReviewFeedEntryMerger.merge(feed_entry)
      end
    end

    feed_entry = create(:feed_entry, cve_id: "CVE-5555-4444")
    advisory_review, = AdvisoryReviewFeedEntryMerger.merge(feed_entry)
    assert advisory_review.open?, "should be open"
    assert_equal feed_entry.reload.advisory_review, advisory_review
  end

  test "feed entry merging works with cvss V4" do
    # if we create with cvss_v4, it should populate
    feed_entries = Array.new(3) { |i| create(:feed_entry, cve_id: "CVE-5555-123#{i}", advisory_payload: create(:advisory_payload, cvss_v4: "CVSS:4.0/AV:N/AC:L/AT:N/PR:N/UI:N/VC:H/VI:L/VA:L/SC:L/SI:L/SA:L")) }

    assert_difference -> { AdvisoryReview.count }, 3 do
      feed_entries.each do |feed_entry|
        AdvisoryReviewFeedEntryMerger.merge(feed_entry)
      end
    end

    feed_entries.each do |feed_entry|
      assert_equal "CVSS:4.0/AV:N/AC:L/AT:N/PR:N/UI:N/VC:H/VI:L/VA:L/SC:L/SI:L/SA:L", feed_entry.advisory_review.cvss_v4
    end

    # If we merge with no cvss_v4, it should empty out
    feed_entry = create(:feed_entry, cve_id: "CVE-5555-4444")
    advisory_review, = AdvisoryReviewFeedEntryMerger.merge(feed_entry)
    assert advisory_review.open?, "should be open"
    assert_equal feed_entry.reload.advisory_review, advisory_review
    assert_equal "", advisory_review.cvss_v4

    # if we merge with cvss_v4, it should populate
    feed_entry = create(:feed_entry, cve_id: "CVE-5555-4444", advisory_payload: create(:advisory_payload, cvss_v4: "CVSS:4.0/AV:N/AC:L/AT:N/PR:N/UI:N/VC:H/VI:L/VA:L/SC:L/SI:L/SA:L"))
    advisory_review, = AdvisoryReviewFeedEntryMerger.merge(feed_entry)
    assert_equal "CVSS:4.0/AV:N/AC:L/AT:N/PR:N/UI:N/VC:H/VI:L/VA:L/SC:L/SI:L/SA:L", advisory_review.cvss_v4
  end

  test "updates an advisory review if it exists" do
    cve = "CVE-5555-1232"
    advisory_review = create(:advisory_review, state: "open", cve_id: cve)

    feed_entry = create(:feed_entry, cve_id: cve, advisory_review: advisory_review)
    assert_no_difference -> { AdvisoryReview.count } do
      AdvisoryReviewFeedEntryMerger.merge(feed_entry)
    end

    feed_entry = create(:feed_entry, cve_id: cve)
    assert_no_difference -> { AdvisoryReview.count } do
      AdvisoryReviewFeedEntryMerger.merge(feed_entry)
    end
  end

  test "merges ghsa_id if feed entry specifies one" do
    feed_entry = build :repository_advisory_feed_entry
    refute_nil feed_entry.ghsa_id
    assert_difference -> { AdvisoryReview.count }, 1 do
      AdvisoryReviewFeedEntryMerger.merge(feed_entry)
    end
    new_advisory_review = AdvisoryReview.last
    assert_equal feed_entry.ghsa_id, new_advisory_review.ghsa_id
  end

  test "generates ghsa_id if feed entry does not specify" do
    feed_entry = build :cve_feed_entry
    assert_nil feed_entry.ghsa_id
    assert_difference -> { AdvisoryReview.count }, 1 do
      AdvisoryReviewFeedEntryMerger.merge(feed_entry)
    end
    new_advisory_review = AdvisoryReview.last
    refute_nil new_advisory_review.ghsa_id
  end

  test "merges cve_id when it doesn't overlap" do
    create(:advisory_review, cve_id: "CVE-2021-1234")
    advisory_review = create(:advisory_review, cve_id: nil, feed_entry_type: :repository_advisory_feed_entry)
    feed_entry = advisory_review.feed_entries.first

    feed_entry.cve_id = "CVE-2021-5678"
    feed_entry.advisory_payload["references"] += ["https://this.is.a.reference"]
    feed_entry.save!

    AdvisoryReviewFeedEntryMerger.merge(feed_entry)
    assert_equal "CVE-2021-5678", advisory_review.cve_id
    assert advisory_review.references.include?("https://this.is.a.reference")
  end

  test "doesn't merge cve_id when it does overlap" do
    existing_advisory_review = create(:advisory_review)
    advisory_review = create(:advisory_review, cve_id: nil, feed_entry_type: :repository_advisory_feed_entry)
    feed_entry = advisory_review.feed_entries.first

    feed_entry.cve_id = existing_advisory_review.cve_id
    feed_entry.advisory_payload["references"] += ["https://this.is.a.reference"]
    feed_entry.save!

    AdvisoryReviewFeedEntryMerger.merge(feed_entry)
    assert_nil advisory_review.cve_id
    assert advisory_review.references.include?("https://this.is.a.reference")
  end

  test "sets ids if not already set" do
    cve_id = "CVE-5555-1234"

    cve_feed_entry = create :cve_feed_entry, cve_id: cve_id
    AdvisoryReviewFeedEntryMerger.merge(cve_feed_entry)

    assert advisory_review = AdvisoryReview.find_by(cve_id: cve_id)
    assert_equal [cve_feed_entry], advisory_review.feed_entries
    assert_equal cve_feed_entry.cve_id, advisory_review.cve_id
    assert_nil advisory_review.friends_of_php_id
    assert_nil advisory_review.rubysec_id
    assert_nil advisory_review.rustsec_id

    fophp_feed_entry = create :friends_of_php_feed_entry, cve_id: cve_id
    AdvisoryReviewFeedEntryMerger.merge(fophp_feed_entry)

    advisory_review.reload
    assert_equal [cve_feed_entry, fophp_feed_entry], advisory_review.feed_entries
    assert_equal cve_feed_entry.cve_id,              advisory_review.cve_id
    assert_equal fophp_feed_entry.friends_of_php_id, advisory_review.friends_of_php_id
    assert_nil advisory_review.rubysec_id
    assert_nil advisory_review.rustsec_id

    rubysec_feed_entry = create :rubysec_feed_entry, cve_id: cve_id
    AdvisoryReviewFeedEntryMerger.merge(rubysec_feed_entry)

    advisory_review.reload
    assert_equal [cve_feed_entry, fophp_feed_entry, rubysec_feed_entry], advisory_review.feed_entries
    assert_equal cve_feed_entry.cve_id,              advisory_review.cve_id
    assert_equal fophp_feed_entry.friends_of_php_id, advisory_review.friends_of_php_id
    assert_equal rubysec_feed_entry.rubysec_id,      advisory_review.rubysec_id
    assert_nil advisory_review.rustsec_id

    rustsec_feed_entry = create :rustsec_feed_entry, cve_id: cve_id
    AdvisoryReviewFeedEntryMerger.merge(rustsec_feed_entry)

    advisory_review.reload
    assert_equal [cve_feed_entry, fophp_feed_entry, rubysec_feed_entry, rustsec_feed_entry], advisory_review.feed_entries
    assert_equal cve_feed_entry.cve_id,              advisory_review.cve_id
    assert_equal fophp_feed_entry.friends_of_php_id, advisory_review.friends_of_php_id
    assert_equal rubysec_feed_entry.rubysec_id,      advisory_review.rubysec_id
    assert_equal rustsec_feed_entry.rustsec_id,      advisory_review.rustsec_id
  end

  test "sets default_ecosystem if advisory review does not have one set" do
    ghsa_id = generate(:ghsa_id)
    create(:advisory_review, ghsa_id: ghsa_id, default_ecosystem: nil)
    feed_entry = create :rubysec_feed_entry, ghsa_id: ghsa_id
    advisory_review, = AdvisoryReviewFeedEntryMerger.merge(feed_entry)

    assert_equal "rubygems", advisory_review.default_ecosystem

    feed_entry = create :rustsec_feed_entry, ghsa_id: ghsa_id
    advisory_review, = AdvisoryReviewFeedEntryMerger.merge(feed_entry)

    assert_equal "rubygems", advisory_review.default_ecosystem
  end

  test "merges reference lists" do
    cve_id = "CVE-5555-1234"
    repository_advisory_feed_entry = create :repository_advisory_feed_entry, cve_id: cve_id
    repository_advisory_feed_entry.advisory_payload["references"] = [
      "https://b.com",
      "https://c.com",
    ]
    AdvisoryReviewFeedEntryMerger.merge(repository_advisory_feed_entry)

    fophp_feed_entry = create :friends_of_php_feed_entry, cve_id: cve_id
    fophp_feed_entry.advisory_payload["references"] = [
      "https://a.com",
      "https://b.com",
      "https://d.com",
    ]
    advisory_review, = AdvisoryReviewFeedEntryMerger.merge(fophp_feed_entry)
    assert_equal [
      "https://a.com",
      "https://b.com",
      "https://c.com",
      "https://d.com",
    ], advisory_review.advisory_payload["references"]
  end

  test "merges CWE lists" do
    cve_id = "CVE-5555-1234"
    repository_advisory_feed_entry = create :repository_advisory_feed_entry, cve_id: cve_id
    repository_advisory_feed_entry.advisory_payload["cwe_ids"] = [
      "CWE-129",
      "CWE-116",
    ]
    AdvisoryReviewFeedEntryMerger.merge(repository_advisory_feed_entry)

    fophp_feed_entry = create :friends_of_php_feed_entry, cve_id: cve_id
    fophp_feed_entry.advisory_payload["cwe_ids"] = [
      "CWE-79",
      "CWE-129",
      "CWE-532",
    ]
    advisory_review, = AdvisoryReviewFeedEntryMerger.merge(fophp_feed_entry)
    assert_equal [
      "CWE-79",
      "CWE-116",
      "CWE-129",
      "CWE-532",
    ], advisory_review.advisory_payload["cwe_ids"]
  end

  test "merges vulnerability lists" do
    initial_advisory_payload = create(:advisory_payload,
      vulnerabilities: {
        0 => {
          ecosystem: "pip",
          package_name: "some_python_package",
          vulnerable_version_range: "< 1.0.0",
          first_patched_version: "1.0.0",
          withdrawn: false,
        },
        1 => {
          ecosystem: "npm",
          package_name: "realpackage",
          vulnerable_version_range: "< 1.2.3",
          first_patched_version: "1.2.4",
          withdrawn: false,
        },
        2 => {
          ecosystem: "maven",
          package_name: "realpackage",
          vulnerable_version_range: "< 1.2",
          first_patched_version: "",
          withdrawn: false,
        },
        3 => {
          ecosystem: "go",
          package_name: "realpackage",
          vulnerable_version_range: "< 1.2",
          first_patched_version: "",
          withdrawn: false,
        },
      })
    advisory_review = create(:advisory_review, :rejected, advisory_payload: initial_advisory_payload)

    feed_entry = create(:feed_entry,
      :unresolved,
      ghsa_id: advisory_review.ghsa_id, # make sure it will resolve onto above advisory review
      advisory_payload_overrides: {
        vulnerabilities: {
          0 => {
            ecosystem: "npm", # duplicate of a vulnerability from above
            package_name: "realpackage",
            vulnerable_version_range: "< 1.2.3",
            first_patched_version: "1.2.4",
            withdrawn: false,
          },
          1 => {
            ecosystem: "npm", # vulnerability with same ecosystem and package but different vulnerable_version_range
            package_name: "realpackage",
            vulnerable_version_range: ">= 2.0.0, < 2.3.4",
            first_patched_version: "2.3.5",
            withdrawn: false,
          },
          2 => {
            ecosystem: "maven",
            package_name: "realpackage",
            vulnerable_version_range: "< 1.2",
            first_patched_version: "1.2", # adding a first_patched_version to a vulnerability that already existed
            withdrawn: false,
          },
          3 => {
            ecosystem: "composer", # new vulnerability
            package_name: "realpackage",
            vulnerable_version_range: "< 3",
            first_patched_version: "3",
            withdrawn: false,
          },
          4 => {
            ecosystem: "go", # duplicate package with no first patched version
            package_name: "realpackage",
            vulnerable_version_range: "< 1.2",
            first_patched_version: "",
            withdrawn: false,
          },
        },
      })

    assert_equal 4, advisory_review.advisory_payload["vulnerabilities"].count

    AdvisoryReviewFeedEntryMerger.merge(feed_entry)

    advisory_review.reload
    assert_equal 6, advisory_review.advisory_payload["vulnerabilities"].count

    expected_vulnerabilities = {
      0 => {
        ecosystem: "pip",
        package_name: "some_python_package",
        vulnerable_version_range: "< 1.0.0",
        first_patched_version: "1.0.0",
        withdrawn: false,
      },
      1 => {
        ecosystem: "npm",
        package_name: "realpackage",
        vulnerable_version_range: "< 1.2.3",
        first_patched_version: "1.2.4",
        withdrawn: false,
      },
      2 => {
        ecosystem: "maven",
        package_name: "realpackage",
        vulnerable_version_range: "< 1.2",
        first_patched_version: "1.2",
        withdrawn: false,
      },
      3 => {
        ecosystem: "go",
        package_name: "realpackage",
        vulnerable_version_range: "< 1.2",
        first_patched_version: "",
        withdrawn: false,
      },
      4 => {
        ecosystem: "npm",
        package_name: "realpackage",
        vulnerable_version_range: ">= 2.0.0, < 2.3.4",
        first_patched_version: "2.3.5",
        withdrawn: false,
      },
      5 => {
        ecosystem: "composer",
        package_name: "realpackage",
        vulnerable_version_range: "< 3",
        first_patched_version: "3",
        withdrawn: false,
      },
    }.with_indifferent_access
    assert_equal expected_vulnerabilities, advisory_review.advisory_payload["vulnerabilities"]
  end

  test "overwrites a blank description in advisory_payload" do
    cve_id = "CVE-5555-1234"
    fophp_feed_entry = create :friends_of_php_feed_entry, cve_id: cve_id
    advisory_review, = AdvisoryReviewFeedEntryMerger.merge(fophp_feed_entry)
    assert_nil advisory_review.advisory_payload["description"]

    cve_feed_entry = create :cve_feed_entry, cve_id: cve_id
    AdvisoryReviewFeedEntryMerger.merge(cve_feed_entry)
    advisory_review.reload
    assert advisory_review.advisory_payload["description"]
    assert_equal cve_feed_entry.advisory_payload["description"], advisory_review.advisory_payload["description"]
  end

  test "overwrites a non-blank description in advisory_payload if the new feed entry is a repository_advisory" do
    cve_feed_entry = create :cve_feed_entry,
      advisory_payload_overrides: { description: "the description from the cve feed entry" }
    advisory_review, = AdvisoryReviewFeedEntryMerger.merge(cve_feed_entry)
    assert_equal "the description from the cve feed entry", advisory_review.description

    repository_advisory_feed_entry = create :repository_advisory_feed_entry,
      ghsa_id: advisory_review.ghsa_id,
      advisory_payload_overrides: { description: "the description from the repo advisory" }

    # make sure it takes description from the repo advisory
    AdvisoryReviewFeedEntryMerger.merge(repository_advisory_feed_entry)
    advisory_review.reload
    assert_equal "the description from the repo advisory", advisory_review.description

    # make sure it does not take the description from a feed entry that is not a repository advisory
    cve_review_feed_entry = create :cve_review_feed_entry,
      ghsa_id: advisory_review.ghsa_id,
      advisory_payload_overrides: { description: "the description from the cve review" }

    AdvisoryReviewFeedEntryMerger.merge(cve_review_feed_entry)
    advisory_review.reload
    assert_equal "the description from the repo advisory", advisory_review.description
  end

  # Test that verifies unicode characters being saved into a yaml column works.
  # This was originally called a paper_trail bug, but it turns out to be a bit more fundamental to rails.
  # Original issue: https://github.com/paper-trail-gem/paper_trail/issues/1348
  #
  # This has since been monkey patched via `lib/monkey_patch_serialized.rb` and so special reloads should not be a thing.
  # This test is still valuable because it makes sense Rails' serialized.rb doesn't blow our stuff up.
  test "merges advisory_payload changes when it contains a unicode character" do
    advisory_review = create(:advisory_review,
      advisory_payload: { "description" => "\u2022" })
    feed_entry = create(:cve_feed_entry, cve_id: advisory_review.cve_id)

    assert_changes -> { advisory_review.reload.advisory_payload } do
      assert_nothing_raised do
        AdvisoryReviewFeedEntryMerger.merge(feed_entry)
      end
    end
  end

  # tests on auto_publication
  test "Advisory Review is auto-publishable if it is an open NVD review without a reviewed advisory" do
    advisory_review = create(:advisory_review, :open, feed_entry_type: :cve_feed_entry)
    feed_entry = advisory_review.reload.feed_entries.first
    assert AdvisoryReviewFeedEntryMerger.new(feed_entry).send(:advisory_changes_auto_publishable?)

    advisory_review = create(:advisory_review, :open, feed_entry_type: :cve_feed_entry, create_advisory: true)
    feed_entry = advisory_review.reload.feed_entries.first
    refute AdvisoryReviewFeedEntryMerger.new(feed_entry).send(:advisory_changes_auto_publishable?)
  end

  test "Advisory Review is not auto-publishable if review has begun" do
    advisory_review = create(:advisory_review, :in_review, feed_entry_type: :cve_feed_entry)
    feed_entry = advisory_review.reload.feed_entries.first
    refute AdvisoryReviewFeedEntryMerger.new(feed_entry).send(:advisory_changes_auto_publishable?)

    advisory_review.reject!
    refute AdvisoryReviewFeedEntryMerger.new(feed_entry).send(:advisory_changes_auto_publishable?)

    advisory_review = create(:advisory_review, :accepted, feed_entry_type: :cve_feed_entry, create_advisory: true)
    feed_entry = advisory_review.reload.feed_entries.first
    refute AdvisoryReviewFeedEntryMerger.new(feed_entry).send(:advisory_changes_auto_publishable?)
  end

  test "Advisory Review is not auto-publishable if it is not only NVD" do
    advisory_review = create(:advisory_review, :open, feed_entry_type: :repository_advisory_feed_entry)
    feed_entry = advisory_review.reload.feed_entries.first
    refute AdvisoryReviewFeedEntryMerger.new(feed_entry).send(:advisory_changes_auto_publishable?)

    create(:cve_feed_entry, advisory_review: advisory_review)
    refute AdvisoryReviewFeedEntryMerger.new(feed_entry).send(:advisory_changes_auto_publishable?)
  end

  test "Advisory Review is auto-publishable if there is a malware feed entry" do
    advisory_review = create(:advisory_review, :open, feed_entry_type: :malware_feed_entry)
    feed_entry = advisory_review.reload.feed_entries.first
    assert AdvisoryReviewFeedEntryMerger.new(feed_entry).send(:advisory_changes_auto_publishable?)
  end

  test "auto-publishes advisory review when auto_publishable" do
    feed_entry = create(:cve_feed_entry)
    advisory_review, = AdvisoryReviewFeedEntryMerger.merge(feed_entry)

    assert advisory_review.advisory

    feed_entry = create(:repository_advisory_feed_entry)
    advisory_review, = AdvisoryReviewFeedEntryMerger.merge(feed_entry)

    refute advisory_review.advisory
  end

  test "continues processing if auto-publishing fails" do
    advisory_review = create(:advisory_review, :open, feed_entry_type: :cve_feed_entry)
    advisory_review["advisory_payload"]["cvss_v3"] = "asdfsdf" # invalid advisory value
    advisory_review.save!

    merger = AdvisoryReviewFeedEntryMerger.new(advisory_review.feed_entries.first)
    assert merger.send(:advisory_changes_auto_publishable?)

    advisory_review, = assert_nothing_raised do
      advisory_review, = merger.merge
    end
    refute advisory_review.advisory
  end

  # test on skipping curation
  test "Advisory Review may not skip curation if there is no associated Advisory and the CVE is curatable" do
    advisory_review = create(:advisory_review, feed_entry_type: :cve_feed_entry, cve_id: "CVE-2020-12345")
    feed_entry = advisory_review.reload.feed_entries.first
    refute AdvisoryReviewFeedEntryMerger.new(feed_entry).send(:feed_changes_may_skip_curation?)
  end

  test "Advisory Review may skip curation if there is no associated Advisory and the CVE is not curatable" do
    advisory_review = create(:advisory_review, feed_entry_type: :cve_feed_entry, cve_id: "CVE-1999-12345")
    feed_entry = advisory_review.reload.feed_entries.first
    assert AdvisoryReviewFeedEntryMerger.new(feed_entry).send(:feed_changes_may_skip_curation?)
  end

  test "Advisory Review may not skip curation if the Advisory Review is not auto_publishable" do
    advisory_review = create(:advisory_review, :open, feed_entry_type: :cve_feed_entry)
    advisory_review.close!
    feed_entry = advisory_review.reload.feed_entries.first
    merger = AdvisoryReviewFeedEntryMerger.new(feed_entry)

    refute merger.send(:advisory_changes_auto_publishable?)
    refute merger.send(:feed_changes_may_skip_curation?)
  end

  test "Advisory Review may skip curation if approved feed references are being added to an accepted reviewed advisory" do
    advisory_review = create(:advisory_review, :open, feed_entry_type: :cve_feed_entry, approval_count: 2)
    advisory_review.advisory_payload["references"] = ["https://not.approved.ref.com"]
    advisory_review.save!
    feed_entry = advisory_review.feed_entries.first
    feed_entry.advisory_payload["references"] = ["https://not.approved.ref.com"]
    feed_entry.mark_as_resolved
    Publisher.new(advisory_review).publish

    approved_reference = "https://www.debian.org/package"
    feed_entry.advisory_payload["references"] << approved_reference
    feed_entry.save!

    merger = AdvisoryReviewFeedEntryMerger.new(feed_entry)
    added_refs = merger.feed_entry_changes["advisory_payload"]["references"] - advisory_review.advisory_payload["references"]
    assert_equal ["references"], merger.feed_entry_changes["advisory_payload"].keys
    assert_equal [approved_reference], added_refs

    merger.send(:update_advisory_review)
    assert merger.send(:feed_changes_may_skip_curation?)
  end

  test "Advisory Review may not skip curation if mixed feed references are being added to an accepted reviewed advisory" do
    advisory_review = create(:advisory_review, :open, feed_entry_type: :cve_feed_entry, approval_count: 2)
    feed_entry = advisory_review.feed_entries.first
    feed_entry.mark_as_resolved
    Publisher.new(advisory_review).publish

    approved_reference = "https://www.debian.org/package"
    random_reference = generate(:url)
    feed_entry.advisory_payload["references"] << approved_reference
    feed_entry.advisory_payload["references"] << random_reference
    feed_entry.save!

    merger = AdvisoryReviewFeedEntryMerger.new(feed_entry)
    added_refs = merger.feed_entry_changes["advisory_payload"]["references"] - advisory_review.advisory_payload["references"]
    assert_equal ["references"], merger.feed_entry_changes["advisory_payload"].keys
    assert_equal [approved_reference, random_reference], added_refs

    merger.send(:update_advisory_review)
    refute merger.send(:feed_changes_may_skip_curation?)
  end

  test "Advisory Review may not skip curation if feed references are being removed from an accepted reviewed advisory" do
    advisory_review = create(:advisory_review, :open, feed_entry_type: :cve_feed_entry, approval_count: 2)
    feed_entry = advisory_review.feed_entries.first
    feed_entry.mark_as_resolved
    Publisher.new(advisory_review).publish

    removed_reference = feed_entry.advisory_payload["references"].shift
    feed_entry.advisory_payload["references"] << "https://www.debian.org/package"
    feed_entry.save!

    assert advisory_review.advisory.references.pluck(:url).include? removed_reference
    refute feed_entry.advisory_payload["references"].include? removed_reference

    merger = AdvisoryReviewFeedEntryMerger.new(feed_entry)
    merger.send(:update_advisory_review)
    refute merger.send(:feed_changes_may_skip_curation?)
  end

  test "Advisory Review may not skip curation if any non reference feed changes are included for an accepted reviewed advisory" do
    advisory_review = create(:advisory_review, :open, feed_entry_type: :cve_feed_entry, approval_count: 2)
    feed_entry = advisory_review.feed_entries.first
    feed_entry.mark_as_resolved
    Publisher.new(advisory_review).publish

    approved_reference = "https://www.debian.org/package"
    cwe_1 = create(:cwe)
    feed_entry.advisory_payload["references"] << approved_reference
    feed_entry.advisory_payload["cwe_ids"] << cwe_1.cwe_id
    feed_entry.save!

    merger = AdvisoryReviewFeedEntryMerger.new(feed_entry)
    added_refs = merger.feed_entry_changes["advisory_payload"]["references"] - advisory_review.advisory_payload["references"]
    assert_equal ["cwe_ids", "references"], merger.feed_entry_changes["advisory_payload"].keys
    assert_equal [approved_reference], added_refs

    merger.send(:update_advisory_review)
    refute merger.send(:feed_changes_may_skip_curation?)
  end

  test "Advisory Review may skip curation if feed references are added to an accepted unreviewed advisory" do
    advisory_review = create(:advisory_review, :open, feed_entry_type: :cve_feed_entry)
    feed_entry = advisory_review.feed_entries.first
    Publisher.new(advisory_review).auto_publish
    feed_entry.mark_as_resolved
    advisory_review.revert! # curator decides not curate

    new_reference = generate(:url)
    feed_entry.advisory_payload["references"] << new_reference
    feed_entry.save!

    refute advisory_review.advisory.references.pluck(:url).include? new_reference
    assert feed_entry.advisory_payload["references"].include? new_reference
    assert AdvisoryReviewFeedEntryMerger.new(feed_entry).send(:feed_changes_may_skip_curation?)
  end

  test "Advisory Review may not skip curation if feed references are removed from an accepted unreviewed advisory" do
    advisory_review = create(:advisory_review, :open, feed_entry_type: :cve_feed_entry)
    advisory_review.advisory_payload["references"] = ["http://www.a.com", "http://www.b.com"]
    advisory_review.save!
    feed_entry = advisory_review.feed_entries.first
    feed_entry.advisory_payload["references"] = ["http://www.a.com", "http://www.b.com"]
    Publisher.new(advisory_review).auto_publish
    feed_entry.mark_as_resolved
    advisory_review.revert! # curator decides not curate

    feed_entry.advisory_payload["references"] = ["http://www.a.com"]
    feed_entry.save!

    assert advisory_review.advisory.references.pluck(:url).include? "http://www.b.com"
    refute feed_entry.advisory_payload["references"].include? "http://www.b.com"
    refute AdvisoryReviewFeedEntryMerger.new(feed_entry).send(:feed_changes_may_skip_curation?)
  end

  test "Advisory Review may skip curation if a feed CVSS score is added to an accepted unreveiwed advisory" do
    advisory_review = create(:advisory_review, :open, feed_entry_type: :cve_feed_entry)
    feed_entry = advisory_review.feed_entries.first
    advisory_review.advisory_payload["cvss_v3"] = nil
    advisory_review.save!
    Publisher.new(advisory_review).auto_publish
    feed_entry.advisory_payload["cvss_v3"] = nil
    feed_entry.mark_as_resolved
    advisory_review.revert! # curator decides not curate

    feed_entry.advisory_payload["cvss_v3"] = "CVSS:3.1/AV:L/AC:H/PR:H/UI:R/S:U/C:L/I:L/A:L"
    feed_entry.save!

    assert_nil advisory_review.advisory.cvss_v3
    refute_nil feed_entry.advisory_payload["cvss_v3"]
    assert AdvisoryReviewFeedEntryMerger.new(feed_entry).send(:feed_changes_may_skip_curation?)
  end

  test "Advisory Review may not skip curation if the feed CVSS score is changed on an accepted unreviewed advisory" do
    advisory_review = create(:advisory_review, :open, feed_entry_type: :cve_feed_entry)
    advisory_review.advisory_payload["cvss_v3"] = "CVSS:3.1/AV:N/AC:H/PR:L/UI:R/S:C/C:H/I:L/A:L"
    advisory_review.save!
    feed_entry = advisory_review.feed_entries.first
    Publisher.new(advisory_review).auto_publish
    feed_entry.mark_as_resolved
    advisory_review.revert! # curator decides not curate

    feed_entry.advisory_payload["cvss_v3"] = "CVSS:3.1/AV:L/AC:H/PR:H/UI:R/S:U/C:L/I:L/A:L"
    feed_entry.save!

    refute_nil advisory_review.advisory.cvss_v3
    refute_equal feed_entry.advisory_payload["cvss_v3"], advisory_review.advisory.cvss_v3
    refute AdvisoryReviewFeedEntryMerger.new(feed_entry).send(:feed_changes_may_skip_curation?)
  end

  test "Advisory Review may skip curation if a feed CWE is added to an accepted unreviewed advisory" do
    advisory_review = create(:advisory_review, :open, feed_entry_type: :cve_feed_entry)
    feed_entry = advisory_review.feed_entries.first
    Publisher.new(advisory_review).auto_publish
    feed_entry.mark_as_resolved
    advisory_review.revert! # curator decides not curate

    cwe_1 = create(:cwe)
    feed_entry.advisory_payload["cwe_ids"] << cwe_1.cwe_id
    feed_entry.save!

    refute advisory_review.advisory.cwes.pluck(:cwe_id).include? cwe_1.cwe_id
    assert feed_entry.advisory_payload["cwe_ids"].include? cwe_1.cwe_id
    assert AdvisoryReviewFeedEntryMerger.new(feed_entry).send(:feed_changes_may_skip_curation?)
  end

  test "Advisory Review may not skip curation if a feed CWE is removed from an accepted review" do
    advisory_review = create(:advisory_review, :open, feed_entry_type: :cve_feed_entry)
    cwe_1 = create(:cwe)
    cwe_2 = create(:cwe)
    advisory_review.advisory_payload["cwe_ids"] = [cwe_1.cwe_id, cwe_2.cwe_id]
    advisory_review.save!
    feed_entry = advisory_review.feed_entries.first
    feed_entry.advisory_payload["cwe_ids"] = [cwe_1.cwe_id, cwe_2.cwe_id]
    Publisher.new(advisory_review).auto_publish
    feed_entry.mark_as_resolved
    advisory_review.revert! # curator decides not curate

    feed_entry.advisory_payload["cwe_ids"] = [cwe_1.cwe_id]
    feed_entry.save!

    assert advisory_review.advisory.cwes.pluck(:cwe_id).include? cwe_2.cwe_id
    refute feed_entry.advisory_payload["cwe_ids"].include? cwe_2.cwe_id
    refute AdvisoryReviewFeedEntryMerger.new(feed_entry).send(:feed_changes_may_skip_curation?)
  end

  test "Advisory Review may not skip curation if the feed Vulnerability count is different than an accepted unreviewed advisory" do
    advisory_review = create(:advisory_review, :open, feed_entry_type: :cve_feed_entry)
    feed_entry = advisory_review.feed_entries.first
    Publisher.new(advisory_review).auto_publish
    feed_entry.mark_as_resolved
    advisory_review.revert! # curator decides not curate

    feed_entry.advisory_payload["vulnerabilities"] = {
      0 => {
        "ecosystem" => "composer",
        "first_patched_version" => "4.2.7",
        "package_name" => "symfony/symfony",
        "vulnerable_version_range" => ">= 4.2.0, < 4.2.7",
      },
      1 => {
        "ecosystem" => "composer",
        "first_patched_version" => "5.2.7",
        "package_name" => "symfony/symfony",
        "vulnerable_version_range" => ">= 5.2.0, < 5.2.7",
      },
    }
    feed_entry.save!

    refute_equal advisory_review.advisory.vulnerabilities.size, feed_entry.advisory_payload["vulnerabilities"].size
    refute AdvisoryReviewFeedEntryMerger.new(feed_entry).send(:feed_changes_may_skip_curation?)
  end

  test "Advisory Review may not skip curation if feed Vulnerabilities are updated on an accepted unreviewed advisory" do
    advisory_review = create(:advisory_review, :open, feed_entry_type: :cve_feed_entry)
    advisory_review.advisory_payload["vulnerabilities"][0]["first_patched_version"] = "4.1.2"
    advisory_review.save!
    feed_entry = advisory_review.feed_entries.first
    Publisher.new(advisory_review).auto_publish
    feed_entry.mark_as_resolved
    advisory_review.revert! # curator decides not curate

    feed_entry.advisory_payload["vulnerabilities"][0]["first_patched_version"] = "4.1.3"
    feed_entry.save!

    assert_equal advisory_review.advisory.vulnerabilities.size, feed_entry.advisory_payload["vulnerabilities"].size
    refute AdvisoryReviewFeedEntryMerger.new(feed_entry).send(:feed_changes_may_skip_curation?)
  end

  test "Advisory Review may skip curation if there is a malware feed entry" do
    advisory_review = create(:advisory_review, :open, feed_entry_type: :malware_feed_entry)
    feed_entry = advisory_review.reload.feed_entries.first

    assert AdvisoryReviewFeedEntryMerger.new(feed_entry).send(:advisory_changes_auto_publishable?)
    assert AdvisoryReviewFeedEntryMerger.new(feed_entry).send(:feed_changes_may_skip_curation?)
  end

  test "skips curation when feed changes are skippable" do
    feed_entry = create(:cve_feed_entry, cve_id: "CVE-1999-9999")
    advisory_review, = AdvisoryReviewFeedEntryMerger.merge(feed_entry)

    assert advisory_review.accepted?
  end

  # tests on state changes
  test "doesn't reopen review when feed entry doesn't contain new information" do
    cve = "CVE-5555-1232"
    advisory_review = create(:advisory_review, state: "accepted", ghsa_id: "GHSA-qcjw-97hh-g9q8", cve_id: cve, create_advisory: true, feed_entry_type: :rubysec_feed_entry)
    feed_entry = create(:cve_feed_entry, cve_id: cve, identifier: "nvd/#{cve}", advisory_payload_overrides: advisory_review.advisory_payload)

    assert_no_changes -> { advisory_review.reload.state } do
      AdvisoryReviewFeedEntryMerger.merge(feed_entry)
    end

    assert_equal feed_entry.reload.advisory_review_id, advisory_review.id
  end

  test "closes when advisory review is auto_closable" do
    feed_entry = create(:cve_feed_entry, advisory_payload_overrides: { description: "** REJECT ** this review should get closed" })
    advisory_review, = AdvisoryReviewFeedEntryMerger.merge(feed_entry)

    assert_equal "closed", advisory_review.state
  end

  test "applies the blocklist" do
    BlocklistedTerm.create!(pattern: "contains")
    BlocklistedTerm.create!(pattern: "terms")
    feed_entry = create(:cve_feed_entry, advisory_payload_overrides: { description: "This feed entry contains blocklisted terms" })
    advisory_review, = AdvisoryReviewFeedEntryMerger.merge(feed_entry)

    assert_equal 2, advisory_review.blocklisted_terms.length
    assert_predicate advisory_review, :open?

    BlocklistedTerm.create!(pattern: "fatal", level: "remove")
    feed_entry = create(:cve_feed_entry, advisory_payload_overrides: { description: "This feed entry contains fatal blocklisted terms" })
    advisory_review, = AdvisoryReviewFeedEntryMerger.merge(feed_entry)

    assert_equal 3, advisory_review.blocklisted_terms.length
    assert_predicate advisory_review, :accepted?
  end

  test "brings advisory review back into review when it has a reviewed advisory" do
    cve = "CVE-5555-1232"
    advisory_review = create(:advisory_review, state: "accepted", cve_id: cve, create_advisory: true, feed_entry_type: :rubysec_feed_entry)
    feed_entry = create(:cve_feed_entry, cve_id: cve, advisory_review: advisory_review)

    assert_changes -> { advisory_review.reload.state }, from: "accepted", to: "in_review" do
      assert_changes -> { advisory_review.reload.curation_state }, from: "published_reviewed", to: "open_update" do
        AdvisoryReviewFeedEntryMerger.merge(feed_entry)
      end
    end
  end

  test "brings advisory review back into review when it has a withdrawn advisory" do
    cve = "CVE-5555-1232"
    advisory_review = create(:advisory_review, state: "accepted", cve_id: cve, create_advisory: true, feed_entry_type: :rubysec_feed_entry)
    advisory_review.advisory.update(withdrawn_at: Time.current)
    feed_entry = create(:cve_feed_entry, cve_id: cve, advisory_review: advisory_review)

    assert_changes -> { advisory_review.reload.state }, from: "accepted", to: "in_review" do
      assert_changes -> { advisory_review.reload.curation_state }, from: "withdrawn", to: "open_update" do
        AdvisoryReviewFeedEntryMerger.merge(feed_entry)
      end
    end
  end

  test "reopens accepted advisory review when it has an unreviewed advisory" do
    cve = "CVE-5555-1232"
    advisory_review = create(:advisory_review, state: "accepted", cve_id: cve, create_advisory: true, feed_entry_type: :rubysec_feed_entry)
    advisory_review.advisory.update(reviewed: false)
    feed_entry = create(:cve_feed_entry, cve_id: cve, advisory_review: advisory_review)

    assert_changes -> { advisory_review.reload.state }, from: "accepted", to: "open" do
      assert_changes -> { advisory_review.reload.curation_state }, from: "published_unreviewed", to: "open_create" do
        AdvisoryReviewFeedEntryMerger.merge(feed_entry)
      end
    end
  end

  test "doesn't reopen rejected or closed advisory review when feed entry is NVD" do
    cve = "CVE-5555-1232"
    advisory_review = create(:advisory_review, state: "rejected", cve_id: cve, feed_entry_type: :repository_advisory_feed_entry)
    feed_entry = create(:cve_feed_entry, cve_id: cve, advisory_review: advisory_review)
    assert_no_changes -> { advisory_review.reload.state } do
      AdvisoryReviewFeedEntryMerger.merge(feed_entry)
    end

    cve = "CVE-5555-1233"
    advisory_review = create(:advisory_review, state: "closed", cve_id: cve, feed_entry_type: :repository_advisory_feed_entry)
    feed_entry = create(:cve_feed_entry, cve_id: cve, advisory_review: advisory_review)
    assert_no_changes -> { advisory_review.reload.state } do
      AdvisoryReviewFeedEntryMerger.merge(feed_entry)
    end
  end

  test "reopens rejected or closed advisory review when feed entry is not NVD" do
    cve = "CVE-5555-1232"
    advisory_review = create(:advisory_review, state: "rejected", cve_id: cve, feed_entry_type: :cve_feed_entry)
    feed_entry = create(:repository_advisory_feed_entry, cve_id: cve, advisory_review: advisory_review)
    assert_changes -> { advisory_review.reload.state }, from: "rejected", to: "open" do
      AdvisoryReviewFeedEntryMerger.merge(feed_entry)
    end

    cve = "CVE-5555-1233"
    advisory_review = create(:advisory_review, state: "closed", cve_id: cve, feed_entry_type: :cve_feed_entry)
    feed_entry = create(:repository_advisory_feed_entry, cve_id: cve, advisory_review: advisory_review)
    assert_changes -> { advisory_review.reload.state }, from: "closed", to: "open" do
      AdvisoryReviewFeedEntryMerger.merge(feed_entry)
    end
  end

  test "reopens but doesn't merge data when feed entry is AdvisoryImprovement" do
    cve = "CVE-5555-1232"
    advisory_review = create(:advisory_review, state: "accepted", cve_id: cve, create_advisory: true, feed_entry_type: :rubysec_feed_entry)
    feed_entry = create(:advisory_improvement_feed_entry, cve_id: cve, advisory_review: advisory_review)
    feed_entry.advisory_payload["references"] = [
      "https://a.com",
      "https://b.com",
    ]

    assert_changes -> { advisory_review.reload.state }, from: "accepted", to: "in_review" do
      AdvisoryReviewFeedEntryMerger.merge(feed_entry)
    end

    assert_equal ["https://nvd.nist.gov/vuln/detail/CVE-1234-1234"], advisory_review.advisory_payload["references"]
  end
end
