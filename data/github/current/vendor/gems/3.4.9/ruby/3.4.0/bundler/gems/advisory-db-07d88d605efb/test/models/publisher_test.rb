# frozen_string_literal: true

require "test_helper"

class PublisherTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    create(:user)
    ENV["FEATURE_FLAG_RUN_PUSH_ADVISORIES_TO_REPO_JOB"] = "true"
  end

  teardown do
    ENV["FEATURE_FLAG_RUN_PUSH_ADVISORIES_TO_REPO_JOB"] = nil
  end

  test "requires a persisted advisory review" do
    advisory_review = build(:advisory_review, :in_review)

    publisher = Publisher.new(advisory_review)

    assert publisher.invalid?
    assert publisher.errors.added?(:advisory_review, :unpersisted)
  end

  test "requires an unchanged advisory review" do
    advisory_review = create(:advisory_review, :curation_state_open)

    advisory_review.accept # Changes (but does not save) state
    publisher = Publisher.new(advisory_review)

    assert publisher.invalid?
    assert publisher.errors.added?(:advisory_review, :changed, {
      changes: { "state" => ["in_review", "accepted"] },
    })
  end

  test "requires an advisory review that can transition to accepted for manual publication" do
    # A rejected advisory review cannot be published.
    advisory_review = create(:advisory_review, :curation_state_closed)

    publisher = Publisher.new(advisory_review)

    assert publisher.invalid?(:publication)
    assert publisher.errors.added?(:advisory_review, :unacceptable, {
      state: "rejected",
    })

    # An accepted advisory review cannot be published.
    advisory_review = create(:advisory_review, :curation_state_published_unreviewed)

    publisher = Publisher.new(advisory_review)

    assert publisher.invalid?(:publication)
    assert publisher.errors.added?(:advisory_review, :unacceptable, {
      state: "accepted",
    })
  end

  test "requires an advisory review that can transition to accepted or is already accepted for auto-publication" do
    # A rejected advisory review cannot be published.
    advisory_review = create(:advisory_review, :curation_state_closed)

    publisher = Publisher.new(advisory_review)

    assert publisher.invalid?(:autopublication)
    assert publisher.errors.added?(:advisory_review, :unacceptable, {
      state: "rejected",
    })

    # An accepted advisory review can be published (again).
    advisory_review = create(:advisory_review, :curation_state_published_unreviewed)

    publisher = Publisher.new(advisory_review)

    assert publisher.valid?(:autopublication)
  end

  # See test/models/advisory_payload_test.rb for more details on what makes an
  # advisory payload valid or invalid.
  test "requires a valid advisory payload" do
    advisory_payload = create(:advisory_payload, {
      summary: "Hi!",
      description: "Hello, world!",
      severity: "hi", # <- This is invalid!
      references: [
        "https://github.com",
      ],
      vulnerabilities: {
        0 => {
          ecosystem: "rubygems",
          package_name: "rails",
          vulnerable_version_range: "< 6.0.0",
          first_patched_version: "6.0.0",
        },
      },
      withdrawn: false,
    })
    advisory_review = create(:advisory_review, :curation_state_open, {
      advisory_payload: advisory_payload,
    })

    publisher = Publisher.new(advisory_review)

    assert publisher.invalid?
    assert publisher.errors.added?(:advisory_payload, :invalid_nested_element, {
      nesting: ["severity"],
      nested_attribute: "advisory_payload[severity]",
      detail: { error: :inclusion, value: "hi" },
    })
  end

  test "requires all necessary advisory payload data by default, less for autopublication" do
    advisory_review = create(:advisory_review, :curation_state_ready_to_publish, {
      advisory_payload: create(:cve_advisory_payload),
      approval_count: 2,
    })

    publisher = Publisher.new(advisory_review)

    assert_raises do
      publisher.publish
    end

    assert_nothing_raised do
      publisher.auto_publish
    end
  end

  test "publication fails if called within a transaction" do
    advisory_review = create(:advisory_review, :curation_state_ready_to_publish, {
      advisory_payload: create(:cve_advisory_payload),
      approval_count: 2,
    })

    publisher = Publisher.new(advisory_review)

    Advisory.transaction do
      assert_raises(Publisher::NestedTransactionError) do
        publisher = Publisher.new(advisory_review)
        publisher.publish
      end
    end
  end

  test "autpublication can fix certain errors like invalid CWEs" do
    advisory_review = create(:advisory_review, :curation_state_open, {
      advisory_payload: create(:advisory_payload, cwe_ids: ["CWE-840"]),
    })

    publisher = Publisher.new(advisory_review)

    refute publisher.valid?
    assert_nothing_raised do
      publisher.auto_publish
    end
  end

  test "publish creates a new reviewed advisory" do
    advisory_review = create(:advisory_review, :curation_state_ready_to_publish, approval_count: 2)

    publisher = Publisher.new(advisory_review)

    assert_changes -> { Advisory.count }, from: 0, to: 1 do
      publisher.publish
    end

    advisory = Advisory.order(:id).last
    assert_equal advisory_review.ghsa_id, advisory.ghsa_id
    assert advisory.reviewed?
    refute_nil advisory.reviewed_at
  end

  test "auto_publish creates and updates a new unreviewed advisory" do
    advisory_review = create(:advisory_review, :open, advisory_payload: create(:cve_advisory_payload))

    assert_changes -> { Advisory.count }, from: 0, to: 1 do
      publisher = Publisher.new(advisory_review)
      publisher.auto_publish
    end

    advisory = Advisory.order(:id).last
    assert_equal advisory_review.ghsa_id, advisory.ghsa_id
    refute advisory.reviewed?
    assert_nil advisory.reviewed_at

    advisory_review.advisory_payload["summary"] = "This is an updated summary."
    advisory_review.save!

    assert_no_changes -> { Advisory.count } do
      publisher = Publisher.new(advisory_review)
      publisher.auto_publish
    end

    advisory.reload
    assert_equal advisory_review.advisory_payload["summary"], advisory.summary
    refute advisory.reviewed?
    assert_nil advisory.reviewed_at
  end

  test "auto_publish creates and updates a new reviewed advisory if it has a malware feed entry" do
    advisory_review = create(:advisory_review, :open, feed_entry_type: :malware_feed_entry)

    assert_changes -> { Advisory.count }, from: 0, to: 1 do
      publisher = Publisher.new(advisory_review)
      publisher.auto_publish
    end

    advisory = Advisory.order(:id).last
    assert_equal advisory_review.ghsa_id, advisory.ghsa_id
    assert advisory.reviewed?
    assert advisory.reviewed_at

    advisory_review.advisory_payload["summary"] = "This is an updated summary."
    advisory_review.save!

    assert_no_changes -> { Advisory.count } do
      publisher = Publisher.new(advisory_review)
      publisher.auto_publish
    end

    advisory.reload
    assert_equal advisory_review.advisory_payload["summary"], advisory.summary
    assert advisory.reviewed?
    assert advisory.reviewed_at
  end

  test "auto_publish updates a reviewed_advisory" do
    advisory_review = create(:advisory_review, :curation_state_ready_to_publish, approval_count: 2)

    assert_changes -> { Advisory.count }, from: 0, to: 1 do
      publisher = Publisher.new(advisory_review)
      publisher.publish
    end

    advisory = Advisory.order(:id).last
    assert_equal advisory_review.ghsa_id, advisory.ghsa_id
    assert advisory.reviewed?
    assert advisory.reviewed_at

    advisory_review.advisory_payload["summary"] = "This is an updated summary."
    advisory_review.save!

    assert_no_changes -> { Advisory.count } do
      publisher = Publisher.new(advisory_review)
      publisher.auto_publish
    end

    advisory.reload
    assert_equal advisory_review.advisory_payload["summary"], advisory.summary
    assert advisory.reviewed?
    assert advisory.reviewed_at
  end

  test "publish creates a new advisory with cve_id set" do
    advisory_review = create(:advisory_review, :curation_state_ready_to_publish, cve_id: "CVE-1888-1244", approval_count: 2)

    publisher = Publisher.new(advisory_review)

    assert_changes -> { Advisory.count }, from: 0, to: 1 do
      publisher.publish
    end

    advisory = Advisory.order(:id).last
    assert_equal advisory_review.ghsa_id, advisory.ghsa_id
    assert_equal advisory_review.cve_id, advisory.cve_id
  end

  test "publish sets reviewed_at when publishing a formerly unreviewed advisory" do
    advisory_review = create(:advisory_review, :curation_state_published_unreviewed)
    # Reopen the advisory review
    advisory_review.revisit!
    create_list(:advisory_review_approval, 2, :approved, advisory_review_id: advisory_review.id)
    advisory_review.reload

    advisory = advisory_review.advisory
    assert_nil advisory.reviewed_at

    publisher = Publisher.new(advisory_review)
    assert_no_changes -> { Advisory.count } do
      publisher.publish
    end

    refute_nil advisory.reload.reviewed_at
  end

  test "publish sets nvd_published_at if an advisory_review has a NVD feed entry with publishedDate" do
    advisory_review = create(:advisory_review, :curation_state_ready_to_publish, approval_count: 2)
    feed_entry = create(:cve_feed_entry, advisory_review: advisory_review)
    assert_nil advisory_review.advisory
    Publisher.new(advisory_review).publish

    assert_equal feed_entry.raw_payload["published"].to_datetime, advisory_review.advisory.nvd_published_at
  end

  test "publish returns the new advisory" do
    advisory_review = create(:advisory_review, :curation_state_ready_to_publish, approval_count: 2)

    result = Publisher.new(advisory_review).publish

    advisory = Advisory.order(:id).last
    assert_equal advisory, result
  end

  test "publish creates references" do
    advisory_payload = create(:advisory_payload, {
      reference_count: 2,
    })
    advisory_review = create(:advisory_review, :curation_state_ready_to_publish, {
      advisory_payload: advisory_payload,
      approval_count: 2,
    })
    urls = advisory_review.references
    assert_equal 2, urls.uniq.count

    publisher = Publisher.new(advisory_review)

    assert_changes -> { Reference.count }, from: 0, to: 2 do
      publisher.publish
    end

    references = Reference.order(:index).to_a
    assert_equal urls[0], references[0].url
    assert_equal urls[1], references[1].url
  end

  test "publish creates fix_commits" do
    advisory_payload = create(:advisory_payload)
    advisory_payload["vulnerabilities"].each_value do |vuln|
      vuln["fix_commits"] = ["deadbeef1", "deadbeef2"]
    end
    advisory_review = create(:advisory_review, :curation_state_ready_to_publish, {
      advisory_payload: advisory_payload,
      approval_count: 2,
    })
    fix_commits = advisory_review.vulnerabilities[0]["fix_commits"]
    assert_equal 2, fix_commits.count

    publisher = Publisher.new(advisory_review)

    assert_changes -> { FixCommit.count }, from: 0, to: 2 do
      publisher.publish
    end

    fix_commits_db = FixCommit.order(:index).to_a
    assert_equal fix_commits[0], fix_commits_db[0].commit_url
    assert_equal fix_commits[1], fix_commits_db[1].commit_url
  end

  test "publish creates CWEs" do
    create(:cwe, cwe_id: "CWE-79")
    create(:cwe, cwe_id: "CWE-80")
    advisory_payload = create(:advisory_payload, {
      cwe_ids: ["CWE-79", "CWE-80"],
    })
    advisory_review = create(:advisory_review, :curation_state_ready_to_publish, {
      advisory_payload: advisory_payload,
      approval_count: 2,
    })

    publisher = Publisher.new(advisory_review)
    publisher.publish

    advisory = Advisory.order(:id).last
    assert_equal ["CWE-79", "CWE-80"], advisory.cwes.ids
  end

  test "doesn't publish with an invalid CWE" do
    create(:cwe, cwe_id: "CWE-79")
    advisory_payload = create(:advisory_payload, {
      cwe_ids: ["CWE-79", "CWE-9000"],
    })
    advisory_review = create(:advisory_review, :curation_state_open, {
      advisory_payload: advisory_payload,
    })

    publisher = Publisher.new(advisory_review)

    assert publisher.invalid?
    assert publisher.errors.added?(:advisory_review, :unknown_cwe_id, {
      ids: ["CWE-9000"],
    })
  end

  test "publish creates vulnerabilities" do
    advisory_payload = create(:advisory_payload, {
      vulnerabilities: {
        0 => create(:vulnerability_payload, {
          ecosystem: "rubygems",
          package_name: "foo-new",
          vulnerable_version_range: "< 2.0",
          first_patched_version: "2.0",
          withdrawn: false,
        }),
        1 => create(:vulnerability_payload, {
          ecosystem: "pip",
          package_name: "",
          vulnerable_version_range: "",
          first_patched_version: "",
          withdrawn: true,
        }),
        2 => create(:vulnerability_payload, {
          ecosystem: "npm",
          package_name: "bar-new",
          vulnerable_version_range: "< 2.1",
          first_patched_version: "2.1",
          withdrawn: false,
        }),
      },
    })
    advisory_review = create(:advisory_review, :curation_state_ready_to_publish, {
      advisory_payload: advisory_payload,
      approval_count: 2,
    })
    package_names = advisory_review.vulnerabilities.values.pluck("package_name")
    assert_equal 3, package_names.uniq.count

    publisher = Publisher.new(advisory_review)

    assert_changes -> { Vulnerability.count }, from: 0, to: 3 do
      publisher.publish
    end

    vulnerabilities = Vulnerability.order(:index).to_a
    assert_equal package_names[0], vulnerabilities[0].package_name
    assert_nil vulnerabilities[0].withdrawn_at
    assert_equal package_names[1], vulnerabilities[1].package_name
    refute_nil vulnerabilities[1].withdrawn_at
    assert_equal package_names[2], vulnerabilities[2].package_name
    assert_nil vulnerabilities[2].withdrawn_at
  end

  test "publish updates an existing advisory" do
    ghsa_id = generate(:ghsa_id)
    old_cve_id = generate(:cve_id)
    new_cve_id = generate(:cve_id)
    advisory_review = create(:advisory_review, :curation_state_open, {
      ghsa_id: ghsa_id,
      cve_id: new_cve_id,
      approval_count: 2,
    })
    advisory = create(:advisory, {
      advisory_review: advisory_review,
      ghsa_id: ghsa_id,
      cve_id: old_cve_id,
    })

    publisher = Publisher.new(advisory_review)

    assert_changes(
      -> { advisory.reload.cve_id },
      from: old_cve_id,
      to: new_cve_id,
    ) do
      publisher.publish
    end
  end

  test "publish updates references" do
    ghsa_id = generate(:ghsa_id)
    advisory_payload = create(:advisory_payload, {
      references: [
        "https://keep.me",
        "https://replacement.org",
      ],
    })
    advisory_review = create(:advisory_review, :curation_state_open, {
      ghsa_id: ghsa_id,
      advisory_payload: advisory_payload,
      approval_count: 2,
    })
    advisory = create(:advisory, {
      advisory_review: advisory_review,
      ghsa_id: ghsa_id,
      reference_count: 0,
    })
    reference_to_keep = create(:reference, {
      advisory: advisory,
      url: "https://keep.me",
      index: 0,
    })
    reference_to_replace = create(:reference, {
      advisory: advisory,
      url: "https://replace.me",
      index: 1,
    })
    reference_to_remove = create(:reference, {
      advisory: advisory,
      url: "https://remove.me",
      index: 2,
    })

    publisher = Publisher.new(advisory_review)

    assert_changes(
      -> { Reference.count },
      from: 3,
      to: 2,
    ) do
      publisher.publish
    end

    references = Reference.order(:index).to_a

    assert_equal advisory, references[0].advisory
    assert_equal "https://keep.me", references[0].url
    assert_equal 0, references[0].index

    assert_equal advisory, references[1].advisory
    assert_equal "https://replacement.org", references[1].url
    assert_equal 1, references[1].index

    # Records with exact URL matches are preserved whenever possible.
    assert_equal reference_to_keep.id, references[0].id
    refute Reference.exists?(id: reference_to_replace.id)
    refute Reference.exists?(id: reference_to_remove.id)
  end

  test "publish updates vulnerabilities" do
    ghsa_id = generate(:ghsa_id)
    advisory_payload = create(:advisory_payload, {
      vulnerabilities: {
        0 => create(:vulnerability_payload, {
          ecosystem: "rubygems",
          package_name: "foo-new",
          vulnerable_version_range: "< 2.0",
          first_patched_version: "2.0",
          withdrawn: false,
        }),
        1 => create(:vulnerability_payload, {
          ecosystem: "npm",
          package_name: "bar-new",
          vulnerable_version_range: "< 2.1",
          first_patched_version: "2.1",
          withdrawn: true,
        }),
        2 => create(:vulnerability_payload, {
          ecosystem: "pip",
          package_name: "baz-new",
          vulnerable_version_range: "< 2.2",
          first_patched_version: "2.2",
          withdrawn: false,
        }),
      },
    })
    advisory_review = create(:advisory_review, :curation_state_open, {
      ghsa_id: ghsa_id,
      advisory_payload: advisory_payload,
      approval_count: 2,
    })
    advisory = create(:advisory, {
      advisory_review: advisory_review,
      ghsa_id: ghsa_id,
      vulnerability_count: 0,
    })
    vulnerability_0 = create(:vulnerability, {
      advisory: advisory,
      package_ecosystem: "rubygems",
      package_name: "foo-old",
      vulnerable_version_range: "< 1.0",
      first_patched_version: "1.0",
      index: 0,
    })
    vulnerability_1 = create(:vulnerability, {
      advisory: advisory,
      package_ecosystem: "npm",
      package_name: "bar-old",
      vulnerable_version_range: "< 1.1",
      first_patched_version: "1.1",
      index: 1,
    })
    vulnerability_2 = create(:vulnerability, {
      advisory: advisory,
      package_ecosystem: "pip",
      package_name: "baz-old",
      vulnerable_version_range: "< 1.2",
      first_patched_version: "1.2",
      index: 2,
    })

    publisher = Publisher.new(advisory_review)

    assert_no_changes -> { Vulnerability.count } do
      publisher.publish
    end

    vulnerabilities = Vulnerability.order(:index).to_a

    assert_equal advisory, vulnerabilities[0].advisory
    assert_equal "foo-new", vulnerabilities[0].package_name
    assert_equal "< 2.0", vulnerabilities[0].vulnerable_version_range
    assert_equal "2.0", vulnerabilities[0].first_patched_version
    assert_equal 0, vulnerabilities[0].index
    assert_equal vulnerability_0.id, vulnerabilities[0].id

    assert_equal advisory, vulnerabilities[1].advisory
    assert_equal "bar-new", vulnerabilities[1].package_name
    assert_equal "< 2.1", vulnerabilities[1].vulnerable_version_range
    assert_equal "2.1", vulnerabilities[1].first_patched_version
    assert_equal 1, vulnerabilities[1].index
    refute_nil vulnerabilities[1].withdrawn_at
    assert_equal vulnerability_1.id, vulnerabilities[1].id

    assert_equal advisory, vulnerabilities[2].advisory
    assert_equal "baz-new", vulnerabilities[2].package_name
    assert_equal "< 2.2", vulnerabilities[2].vulnerable_version_range
    assert_equal "2.2", vulnerabilities[2].first_patched_version
    assert_equal 2, vulnerabilities[2].index
    assert_equal vulnerability_2.id, vulnerabilities[2].id
  end

  test "publication transitions the advisory review to accepted if it had been reviewed" do
    advisory_review = create(:advisory_review, :curation_state_open)

    publisher = Publisher.new(advisory_review)

    assert_no_changes -> { advisory_review.reload.state } do
      publisher.auto_publish
    end

    advisory_review.approved_to_publish!
    create_list(:advisory_review_approval, 2, :approved, advisory_review_id: advisory_review.id)

    assert_changes(
      -> { advisory_review.reload.state },
      to: "accepted",
    ) do
      publisher.publish
    end
  end

  test "publication will ignore blank references in reference list" do
    advisory_review = create(:advisory_review, :curation_state_open)

    advisory_review.references.push ""
    advisory_review.save!

    publisher = Publisher.new(advisory_review)

    advisory_review.approved_to_publish!
    create_list(:advisory_review_approval, 2, :approved, advisory_review_id: advisory_review.id)

    assert publisher.simulate

    assert_changes(
      -> { advisory_review.reload.state },
      to: "accepted",
    ) do
      publisher.publish
    end

    advisory = Advisory.find_by(ghsa_id: advisory_review.ghsa_id)
    refute_includes advisory.references, ""
  end

  test "changeset will ignore blank references in reference list" do
    advisory_review = create(:advisory_review, :curation_state_ready_to_publish)
    create_list(:advisory_review_approval, 2, :approved, advisory_review_id: advisory_review.id)
    publisher = Publisher.new(advisory_review)
    publisher.publish

    advisory_review.references.push ""
    advisory_review.save!

    publisher = Publisher.new(advisory_review)
    assert_empty publisher.changeset.keys
  end

  test "publish enqueues external publication jobs" do
    advisory_review = create(:advisory_review, :curation_state_ready_to_publish, approval_count: 2)

    publisher = Publisher.new(advisory_review)

    hydro_job = assert_enqueued_with(job: PublishAdvisoryToHydroJob) do
      assert_enqueued_with(job: PushAdvisoriesToRepoJob) do
        publisher.publish
      end
    end

    advisory = Advisory.order(:id).last
    assert_equal [advisory, { credits: [] }], hydro_job.arguments
    assert advisory.sync_state
  end

  test "auto_publish fails if an external transaction exists" do
    advisory_review = create(:advisory_review, :open, advisory_payload: create(:cve_advisory_payload))

    Advisory.transaction do
      assert_raises(Publisher::NestedTransactionError) do
        publisher = Publisher.new(advisory_review)
        publisher.auto_publish
      end
    end
  end

  test "publish skips repo for malware" do
    advisory_review = create(:advisory_review, :curation_state_open, feed_entry_type: :malware_feed_entry)

    publisher = Publisher.new(advisory_review)

    hydro_job = assert_enqueued_with(job: PublishAdvisoryToHydroJob) do
      assert_no_enqueued_jobs(only: PushAdvisoriesToRepoJob) do
        publisher.auto_publish
      end
    end

    advisory = Advisory.order(:id).last
    assert_equal [advisory, { credits: [] }], hydro_job.arguments
    refute advisory.sync_state
  end

  test "publish queues a job to merge PRs" do
    advisory = create(:advisory, created_at: 1.day.ago, updated_at: 1.day.ago)

    advisory_review = advisory.advisory_review
    advisory_review.update(state: "approved_to_publish")
    create_list(:advisory_review_approval, 2, :approved, advisory_review_id: advisory_review.id)

    create(:advisory_improvement_feed_entry, :resolved, advisory_review: advisory_review)

    assert_enqueued_with(
      job: ResolveAdvisoryPRsJob,
      args: [{ ghsa_id: advisory_review.ghsa_id, pr_numbers: [3], merge: true }],
    ) do
      Publisher.new(advisory_review).publish
    end
  end

  test "publish failure makes no changes to the database" do
    advisory_review = create(:advisory_review, :curation_state_ready_to_publish, approval_count: 2)
    # This simulates an error raised when the advisory review changes state.
    error = ActiveRecord::RecordInvalid.new
    advisory_review.stubs(:accept!).raises(error)

    publisher = Publisher.new(advisory_review)

    assert_no_changes -> { Advisory.count } do
      assert_raise error.class do
        publisher.publish
      end
    end

    assert_equal 0, Reference.count
    assert_equal 0, Vulnerability.count
  end

  test "publish failure does not enqueue external publication jobs" do
    advisory_review = create(:advisory_review, :curation_state_ready_to_publish, approval_count: 2)
    # This simulates an error raised when the advisory review changes state.
    error = ActiveRecord::RecordInvalid.new
    advisory_review.stubs(:accept!).raises(error)

    publisher = Publisher.new(advisory_review)

    assert_no_enqueued_jobs(only: PublishAdvisoryToHydroJob) do
      assert_no_enqueued_jobs(only: PushAdvisoriesToRepoJob) do
        assert_raise error.class do
          publisher.publish
        end
      end
    end
  end

  test "publish sets the cvss_v3 for the advisory" do
    cvss_v3 = "CVSS:3.1/AV:L/AC:H/PR:H/UI:R/S:U/C:L/I:L/A:L"
    advisory_payload = create(:advisory_payload, cvss_v3: cvss_v3)
    advisory_review = create(:advisory_review, :curation_state_ready_to_publish, advisory_payload: advisory_payload, approval_count: 2)

    Publisher.new(advisory_review).publish

    assert_equal cvss_v3, Advisory.last.cvss_v3
  end

  test "simulate returns true if publication succeed" do
    advisory_review = create(:advisory_review, :curation_state_open)

    result = Publisher.new(advisory_review).simulate

    assert_equal true, result
  end

  test "simulate returns false if publication would fail" do
    # A rejected advisory review cannot be published.
    advisory_review = create(:advisory_review, :curation_state_closed)

    result = Publisher.new(advisory_review).simulate

    assert_equal false, result
  end

  test "simulate makes no changes to the database" do
    advisory_review = create(:advisory_review, :curation_state_open)

    publisher = Publisher.new(advisory_review)

    assert_no_changes -> { Advisory.count } do
      publisher.simulate
    end

    assert_equal 0, Reference.count
    assert_equal 0, Vulnerability.count
  end

  test "simulate does not enqueue a Hydro publication job" do
    advisory_review = create(:advisory_review, :curation_state_open)

    publisher = Publisher.new(advisory_review)

    assert_no_enqueued_jobs(only: PublishAdvisoryToHydroJob) do
      publisher.simulate
    end
  end

  test "#changeset empty when an Advisory doesn't exist" do
    advisory_review = create(:advisory_review, :curation_state_open)
    changes = Publisher.new(advisory_review).changeset

    assert changes.empty?
  end

  test "publish is blocked if an advisory_review has a hold label assigned" do
    advisory_review = create(:advisory_review, :curation_state_ready_to_publish, approval_count: 2)
    label = create(:label)
    label.label_settings.hold_publication = "1"
    label.save!
    advisory_review.labels << label
    advisory_review.save!

    publisher = Publisher.new(advisory_review)

    begin
      publisher.publish
      raise "Publication should fail due to hold status on label assigned to review."
    rescue AdvisoryDB::PublicationHeldError => error
      assert error.message.include? "'hold' label"
    end

    advisory = Advisory.order(:id).last
    # Test code is written like there can be multiple advisories, so we're just going to make sure that if there happen to be
    # (there isn't in my testing) that the latest created one deosn't match what we're trying to publish.
    refute advisory.present? && advisory_review.ghsa_id == advisory.ghsa_id
  end
end
