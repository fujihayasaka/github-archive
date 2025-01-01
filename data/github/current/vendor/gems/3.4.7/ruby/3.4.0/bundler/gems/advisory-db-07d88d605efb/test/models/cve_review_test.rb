# frozen_string_literal: true

require "test_helper"

class CVEReviewTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    AdvisoryDB::Features.stubs(:enabled?).returns(false)
  end

  # Validation related tests

  test "can be made with only a ghsa (and title) and defaults to decision:undecided" do
    cve_review = CVEReview.create!(ghsa_id: "ghsa-1234-1234-1234", title: "Untitled")
    assert_equal "undecided", cve_review.decision
  end

  test "can not be made without a GHSA ID" do
    assert_raises(ActiveRecord::RecordInvalid) do
      CVEReview.create!
    end
  end

  test "requires a title" do
    cve_review = build(:cve_review, title: nil)
    assert cve_review.invalid?
    cve_review.title = ""
    assert cve_review.invalid?
    cve_review.title = "a"
    assert cve_review.valid?
  end

  # CVERequest.create_or_reopen_from_cve_request related tests

  test "When CVE requested on GHSA that has not been requested before, a new CVE Review is made" do
    cve_request = create :cve_request
    assert_difference("CVEReview.count", 1) do
      CVEReview.create_or_reopen_from_cve_request!(cve_request)
    end
    new_cve_review = CVEReview.last
    assert_equal new_cve_review.ghsa_id, cve_request.ghsa_id
    assert_equal new_cve_review.state, "open"
    assert_equal new_cve_review.decision, "undecided"
    assert_nil new_cve_review.assigned_cve_id
    assert_nil new_cve_review.comment
  end

  test "When CVE requested on GHSA and there is an existing CVE Review with decision undecided, the existing request is used" do
    existing_cve_review = create :undecided_cve_review
    cve_request = create :cve_request, ghsa_id: existing_cve_review.ghsa_id
    assert_no_difference("CVEReview.count") do
      CVEReview.create_or_reopen_from_cve_request!(cve_request)
    end
    assert existing_cve_review.cve_requests.include?(cve_request)
    assert_equal existing_cve_review.reload.state, "open"
  end

  test "When CVE requested on GHSA and there is an existing CVE Review with decision not_assigned, the existing request is returned" do
    existing_cve_review = create :not_assigned_cve_review
    cve_request = create :cve_request, ghsa_id: existing_cve_review.ghsa_id
    assert_no_difference("CVEReview.count") do
      CVEReview.create_or_reopen_from_cve_request!(cve_request)
    end
    assert existing_cve_review.cve_requests.include?(cve_request)
    assert_equal existing_cve_review.reload.state, "open"
  end

  test "When CVE requested on GHSA and there is an existing CVE Review with decision assigned, an exception is raised" do
    existing_cve_review = create :assigned_cve_review, state: :notified
    cve_request = create :cve_request, ghsa_id: existing_cve_review.ghsa_id
    assert_no_difference("CVEReview.count") do
      assert_raises(AASM::InvalidTransition) do
        CVEReview.create_or_reopen_from_cve_request!(cve_request)
      end
    end
    # BUT, the request is still attached, which might not be ideal
    assert existing_cve_review.cve_requests.include?(cve_request)
    # state does not change on cve review
    assert_equal existing_cve_review.reload.state, "notified"
  end

  test "defaults to using CVSS v4 vector string when present" do
    AdvisoryDB::Features.expects(:enabled?).with("advisory_db_cvss_v4").at_least_once.returns(true)

    cve_request = create(:cve_request, :with_cvss_v4)

    assert_difference("CVEReview.count", 1) do
      CVEReview.create_or_reopen_from_cve_request!(cve_request)
    end

    new_cve_review = CVEReview.last

    assert_equal cve_request.cvss_v4, new_cve_review.cvss_vectorString
    assert_equal cve_request.cvss_v4, new_cve_review.cvss_v4
    assert_equal "high", new_cve_review.advisory_payload[:severity]
  end

  test "defaults to using CVSS v4 vector string when both a v3 and v4 vector string are present" do
    AdvisoryDB::Features.expects(:enabled?).with("advisory_db_cvss_v4").at_least_once.returns(true)

    cve_request = create(:cve_request, :with_cvss_v3, :with_cvss_v4)

    assert_difference("CVEReview.count", 1) do
      CVEReview.create_or_reopen_from_cve_request!(cve_request)
    end

    new_cve_review = CVEReview.last

    assert_equal cve_request.cvss_v4, new_cve_review.cvss_vectorString
    assert_equal "high", new_cve_review.advisory_payload[:severity]
  end

  test "falls back to using CVSS v3 vector string when no v4 string is present and a v3 vector string is" do
    AdvisoryDB::Features.expects(:enabled?).with("advisory_db_cvss_v4").at_least_once.returns(true)

    cve_request = create(:cve_request, :with_cvss_v3)

    assert_difference("CVEReview.count", 1) do
      CVEReview.create_or_reopen_from_cve_request!(cve_request)
    end

    new_cve_review = CVEReview.last

    assert_equal cve_request.cvss_v3, new_cve_review.cvss_vectorString
    assert_equal "moderate", new_cve_review.advisory_payload[:severity]
  end

  test "cvss_vectorString is nil if no v3 or v4 vector string is present" do
    AdvisoryDB::Features.expects(:enabled?).with("advisory_db_cvss_v4").at_least_once.returns(true)

    cve_request = create(:cve_request)

    assert_difference("CVEReview.count", 1) do
      CVEReview.create_or_reopen_from_cve_request!(cve_request)
    end

    new_cve_review = CVEReview.last

    assert_nil new_cve_review.cvss_vectorString
    assert_nil new_cve_review.advisory_payload[:severity]
  end

  test "cvss_vectorString updates from a v3 vector string to a v4 vector string when the CVE Review is updated with a v4 vector string" do
    cve_review = create(:cve_review, cvss_vectorString: "CVSS:3.1/AV:N/AC:H/PR:L/UI:N/S:U/C:H/I:N/A:N")
    assert_equal cve_review.cvss_vectorString, "CVSS:3.1/AV:N/AC:H/PR:L/UI:N/S:U/C:H/I:N/A:N"
    assert_equal cve_review.advisory_payload[:severity], "moderate"

    cve_review.update!(cvss_vectorString: "CVSS:4.0/AV:A/AC:H/AT:N/PR:L/UI:N/VC:L/VI:H/VA:H/SC:H/SI:L/SA:H")
    assert_equal cve_review.cvss_vectorString, "CVSS:4.0/AV:A/AC:H/AT:N/PR:L/UI:N/VC:L/VI:H/VA:H/SC:H/SI:L/SA:H"
    assert_equal cve_review.cvss_v4, "CVSS:4.0/AV:A/AC:H/AT:N/PR:L/UI:N/VC:L/VI:H/VA:H/SC:H/SI:L/SA:H"
    assert_equal cve_review.advisory_payload[:severity], "high"
  end

  test "When CVE Review has all fields at max length, a CVE Request gets properly made" do
    cve_request = create :cve_request,
      title: "A" * 1024,
      description: "A" * 10_000, # techincally a medium blob can have 2^24 characters, but that 10K seems like a reasonable test limit
      affected_products_payload: [
        {
          ecosystem: "A" * 50,
          package: "A" * 100,
          affected_versions: "A" * 1024,
          patches: "A" * 1024,
        },
      ]

    assert_difference("CVEReview.count", 1) do
      CVEReview.create_or_reopen_from_cve_request!(cve_request)
    end

    new_cve_review = CVEReview.last
    assert_equal new_cve_review.ghsa_id, cve_request.ghsa_id
    # attributes copied directly from the cve request into the cve review
    assert_equal 1024, new_cve_review.title.length
    assert_equal 10_000, new_cve_review.description.length
  end

  # State model tests
  test "state is open for a brand new CVEReview" do
    assert_equal "open", CVEReview.new.state
    assert_equal "open", CVEReview.create_or_reopen_from_cve_request!(create(:cve_request)).state
  end

  test "only cve reviews which are fully filled out with details can move to state notifed" do
    assert create(:assigned_cve_review).may_notify?
    refute create(:assigned_cve_review, assigned_cve_id: nil).may_notify?
    assert create(:not_assigned_cve_review).may_notify?
    refute create(:not_assigned_cve_review, comment: nil).may_notify?
  end

  test "notify enqueues no jobs if it cannot be notified" do
    cve_review = create(:cve_review, :notified)
    assert_no_enqueued_jobs do
      assert_raises(AASM::InvalidTransition) do
        cve_review.notify!
      end
    end
  end

  test "notify enqueues the publish to hydro job if notifiable" do
    cve_review = create(:not_assigned_cve_review)
    assert_enqueued_with(
      job: PublishCVEReviewToHydroJob,
      args: [
        cve_review_id: cve_review.id,
      ],
    ) do
      cve_review.notify!
    end
  end

  test "notify enqueues ImportJob if review is assigned" do
    cve_review = create(:assigned_cve_review)
    assert_enqueued_with(
      job: ImportJob,
      args: [
        "cve_review",
        { cve_review_id: cve_review.id,
          report_to_slack: false },
      ],
    ) do
      cve_review.notify!
    end
  end

  test "notify does not enqueue ImportJob if review is not_assigned" do
    cve_review = create(:not_assigned_cve_review)
    # we could look that no ImportJob is enqueued (only: ImportJob)
    # but it is safer to list the jobs we do expect enqueued
    assert_no_enqueued_jobs(except: PublishCVEReviewToHydroJob) do
      cve_review.notify!
    end
  end

  test "only not_assigned and notified reviews can be reopened" do
    # those which are already notified can only receive a request when decision was not_assigned
    assert create(:not_assigned_cve_review, state: "notified").may_receive_request?
    refute create(:assigned_cve_review,     state: "notified").may_receive_request?

    # those which have not been notified can always receive
    assert create(:assigned_cve_review,     state: "open").may_receive_request?
  end

  test "when a not_assigned review receives request, it updates review_requested_at and decision" do
    create_time = 1.day.ago
    cve_review = create(:not_assigned_cve_review, state: "notified", created_at: create_time, review_requested_at: create_time)

    freeze_time do
      cve_review.receive_request!
      assert_equal Time.current, cve_review.review_requested_at
    end
    assert_equal cve_review.decision, "undecided"
  end

  test "can handle UTF8 in description field for generating JSON" do
    cve_review = create :assigned_cve_review,
      :notified,
      :all_fields_populated,
      :repository_advisory_published,
      description: "testing encoding (...) ❤️🤠."
    assert_nothing_raised do
      cve_review.cve_json_builder.to_json
    end
  end

  test "de-dups references" do
    cve_review = create :assigned_cve_review,
      :notified,
      :all_fields_populated,
      :repository_advisory_published,
      misc_references: ["https://example.com", "https://example.com"]

    assert_equal 1, cve_review.misc_references.length
  end

  test "state can only transition to rejected from notified or open_update" do
    # curation_state in_triage
    cve_review = create(:cve_review, :assigned, state: "open")
    refute cve_review.may_reject?
    # curation_state waiting
    cve_review.update!(state: "notified")
    assert cve_review.may_reject?
    # curation_state open
    create(:advisory_review, ghsa_id: cve_review.ghsa_id, cve_id: cve_review.assigned_cve_id, feed_entry_type: :repository_advisory_feed_entry)
    assert cve_review.reload.may_reject?
    # curation_state published
    cve_review.update!(state: "submitted")
    refute cve_review.may_reject?
    # curation_state open_update
    cve_review.update!(state: "open_update")
    assert cve_review.may_reject?

    cve_review.reject
    assert_equal "rejected", cve_review.state
  end

  test "curation state scopes scope by curation state" do
    in_triage_1 = create :cve_review, :open, :undecided
    in_triage_2 = create :cve_review, :open, :not_assigned
    waiting = create :cve_review, :notified, :assigned
    open = create :cve_review, :notified, :assigned # Needs feed entry below
    create :repository_advisory_feed_entry, ghsa_id: open.ghsa_id
    published = create :cve_review, :submitted, :assigned
    closed = create :cve_review, :notified, :not_assigned

    assert_equal "in_triage", in_triage_1.curation_state
    assert_equal "in_triage", in_triage_2.curation_state
    scope = CVEReview.curation_state_in_triage
    assert_kind_of ActiveRecord::Relation, scope
    assert_equal 2, scope.count
    assert_includes scope, in_triage_1
    assert_includes scope, in_triage_2
    scope = CVEReview.curation_state_in_triage(after_id: in_triage_1.id)
    assert_kind_of ActiveRecord::Relation, scope
    assert_equal [in_triage_2], scope
    assert_includes scope, in_triage_2
    scope = CVEReview.by_curation_state("in_triage")
    assert_kind_of ActiveRecord::Relation, scope
    assert_equal 2, scope.count
    assert_includes scope, in_triage_1
    assert_includes scope, in_triage_2

    assert_equal "waiting", waiting.curation_state
    scope = CVEReview.curation_state_waiting
    assert_kind_of ActiveRecord::Relation, scope
    assert_equal [waiting], scope
    scope = CVEReview.by_curation_state("waiting")
    assert_kind_of ActiveRecord::Relation, scope
    assert_equal [waiting], scope

    assert_equal "open", open.curation_state
    scope = CVEReview.curation_state_open
    assert_kind_of ActiveRecord::Relation, scope
    assert_equal [open], scope
    scope = CVEReview.by_curation_state("open")
    assert_kind_of ActiveRecord::Relation, scope
    assert_equal [open], scope

    assert_equal "published", published.curation_state
    scope = CVEReview.curation_state_published
    assert_kind_of ActiveRecord::Relation, scope
    assert_equal [published], scope
    scope = CVEReview.by_curation_state("published")
    assert_kind_of ActiveRecord::Relation, scope
    assert_equal [published], scope

    assert_equal "closed", closed.curation_state
    scope = CVEReview.curation_state_closed
    assert_kind_of ActiveRecord::Relation, scope
    assert_equal [closed], scope
    scope = CVEReview.by_curation_state("closed")
    assert_kind_of ActiveRecord::Relation, scope
    assert_equal [closed], scope
  end

  test "curation_state_waiting does not include open CVE Reviews that were created for GHSL" do
    cve_review = create(:cve_review, :assigned, :notified)
    create(:ghsl_request, cve_review: cve_review)
    assert_equal "open", cve_review.curation_state
    assert_equal 1, CVEReview.count

    assert_equal 0, CVEReview.curation_state_waiting.length
  end

  test "curation_state_open includes open CVE Reviews that were created for GHSL" do
    cve_review = create(:cve_review, :assigned, :notified)
    create(:ghsl_request, cve_review: cve_review)
    assert_equal "open", cve_review.curation_state
    assert_equal 1, CVEReview.count

    assert_equal 1, CVEReview.curation_state_open.length
  end

  test "curation_state_rejected only includes CVE Reviews that were published and later rejected" do
    create(:cve_review, state: "open")
    create(:cve_review, state: "notified")
    create(:cve_review, state: "submitted")
    create(:cve_review, state: "rejected")
    assert_equal 4, CVEReview.count

    rejected_cve_reviews = CVEReview.curation_state_rejected
    assert_equal 1, rejected_cve_reviews.length
    assert_equal "rejected", rejected_cve_reviews.first.state
  end

  test "curation_state_open_update only includes CVE Reviews that have state open_update" do
    create(:cve_review, :curation_state_in_triage)
    create(:cve_review, :curation_state_waiting)
    create(:cve_review, :curation_state_open)
    create(:cve_review, :curation_state_published)
    create(:cve_review, :curation_state_closed)
    create(:cve_review, :curation_state_rejected)
    create(:cve_review, state: "open_update")
    assert_equal 7, CVEReview.count

    open_update_cve_reviews = CVEReview.curation_state_open_update
    assert_equal 1, open_update_cve_reviews.length
    assert_equal "open_update", open_update_cve_reviews.first.state
  end

  test "curation_state should be open for a CVE Review that has been assigned and notified and is associated with a GHSL Request" do
    cve_review = create(:cve_review, :assigned, :notified)
    create(:ghsl_request, cve_review: cve_review)

    assert_equal "open", cve_review.curation_state
  end

  test "curation_state should be rejected for a CVE Review that has been published and later rejected" do
    cve_review = create(:cve_review, state: "rejected")
    assert_equal "rejected", cve_review.curation_state
  end

  test "curation_state should be open_update for a CVE Review that has been reopened" do
    cve_review = create(:cve_review, state: "open_update")
    assert_equal "open_update", cve_review.curation_state
  end

  test "has one cve association" do
    cve = create(:cve)
    cve_review = create(:cve_review, assigned_cve_id: cve.cve_id)
    assert_equal cve, cve_review.cve
  end

  # Corresponds to YAML:
  #
  #   problemtype_values:
  #     - "CWE-123: Write-what-where Condition"
  #     - "CWE-456: Missing Initialization of a Variable"
  #
  test "problemtype_values can accept an array of strings" do
    cve_review = create(:cve_review, problemtype_values: nil)

    cve_review.update!(
      problemtype_values: [
        "CWE-123: Write-what-where Condition",
        "CWE-456: Missing Initialization of a Variable",
      ],
    )

    assert_equal(
      [
        "CWE-123: Write-what-where Condition",
        "CWE-456: Missing Initialization of a Variable",
      ],
      cve_review.problemtype_values,
    )
  end

  # Corresponds to YAML:
  #
  #   problemtype_values: "CWE-123: Write-what-where Condition"
  #
  test "problemtype_values can accept a single string" do
    cve_review = create(:cve_review, problemtype_values: nil)

    cve_review.update!(
      problemtype_values: "CWE-123: Write-what-where Condition",
    )

    assert_equal(
      ["CWE-123: Write-what-where Condition"],
      cve_review.problemtype_values,
    )
  end

  # Corresponds to YAML:
  #
  #   problemtype_values: |-
  #     CWE-123: Write-what-where Condition
  #     CWE-456: Missing Initialization of a Variable
  #
  test "problemtype_values can accept a multiline string" do
    cve_review = create(:cve_review, problemtype_values: nil)

    cve_review.update!(
      problemtype_values: <<~STR,
        CWE-123: Write-what-where Condition
        CWE-456: Missing Initialization of a Variable
      STR
    )

    assert_equal(
      [
        "CWE-123: Write-what-where Condition",
        "CWE-456: Missing Initialization of a Variable",
      ],
      cve_review.problemtype_values,
    )
  end

  # Corresponds to YAML:
  #
  #   problemtype_values:
  #     - CWE-123: Write-what-where Condition
  #     - CWE-456: Missing Initialization of a Variable
  #
  test "problemtype_values can accept an array of hashes" do
    cve_review = create(:cve_review, problemtype_values: nil)

    cve_review.update!(
      problemtype_values: [
        { "CWE-123" => "Write-what-where Condition" },
        { "CWE-456" => "Missing Initialization of a Variable" },
      ],
    )

    assert_equal(
      [
        "CWE-123: Write-what-where Condition",
        "CWE-456: Missing Initialization of a Variable",
      ],
      cve_review.problemtype_values,
    )
  end

  # Corresponds to YAML:
  #
  #   problemtype_values:
  #     CWE-123: Write-what-where Condition
  #     CWE-456: Missing Initialization of a Variable
  #
  test "problemtype_values can accept a hash" do
    cve_review = create(:cve_review, problemtype_values: nil)

    cve_review.update!(
      problemtype_values: {
        "CWE-123" => "Write-what-where Condition",
        "CWE-456" => "Missing Initialization of a Variable",
      },
    )

    assert_equal(
      [
        "CWE-123: Write-what-where Condition",
        "CWE-456: Missing Initialization of a Variable",
      ],
      cve_review.problemtype_values,
    )
  end

  test "can be associated with a ghsl request" do
    cve_review = create(:cve_review)
    refute cve_review.ghsl_request
    assert cve_review.valid?
    ghsl_request = create(:ghsl_request, cve_review: cve_review)
    assert_equal ghsl_request, cve_review.ghsl_request
  end

  test "importer objects normalize description endings during save" do
    cve_review = create(:cve_review)
    cve_review.description = +"Some \R\N description \R\N using \r\n nonstandard \N newlines"
    cve_review.save

    assert "Some \R\N description \R\N using \r\n nonstandard \N newlines", cve_review.description
    importer_object = cve_review.importer_object
    assert "Some \n description \n using \n nonstandard \n newlines", importer_object[:advisory_payload][:description]
  end

  test "reopen transitions from submitted to open_update state" do
    cve_review = create(:cve_review, :curation_state_published)
    assert_equal "submitted", cve_review.state

    cve_review.reopen!
    assert_equal "open_update", cve_review.state
  end

  test "reopen transitions from rejected to open_update state" do
    cve_review = create(:cve_review, :curation_state_rejected)
    assert_equal "rejected", cve_review.state

    cve_review.reopen!
    assert_equal "open_update", cve_review.state
  end

  test "submit_to_mitre can transition from open_update to submitted state" do
    cve_review = create(:cve_review, :curation_state_open_update)
    assert_equal "open_update", cve_review.state

    cve_review.submit_to_mitre!
    assert_equal "submitted", cve_review.state
  end

  test "ensure no trailing whitespace in the description" do
    cve_review = create(:cve_review)
    cve_review.description = +"testing strip of trailing whitespace (...) ❤️🤠.\n\t\n\n\r\n\v    \n"
    cve_review.save

    assert_equal cve_review.description, "testing strip of trailing whitespace (...) ❤️🤠."
  end
end
