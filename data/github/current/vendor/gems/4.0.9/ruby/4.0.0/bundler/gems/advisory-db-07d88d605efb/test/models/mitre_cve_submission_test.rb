# frozen_string_literal: true

require "test_helper"

class MITRECVESubmissionTest < ActiveSupport::TestCase
  test "increments a stat when a new mitre cve submission is created" do
    cve_review = create :assigned_cve_review, :notified, :all_fields_populated, :repository_advisory_published, assigned_cve_id: "CVE-2021-0003"
    submission_pr_url = "https://github.com/CVEProject/cvelist/pull/12345"

    AdvisoryDB.stats.expects(:increment).once.with("curation.cve_submission")

    VCR.use_cassette("cve_api_create_cve_2021_0003") do
      MITRECVESubmission.record_cve_submission(cve_review: cve_review, pull_request_url: submission_pr_url)
    end
  end

  test "record_cve_rejection for unpublished CVE" do
    assert_equal 0, MITRECVESubmission.count
    cve_review = create(:cve_review, :curation_state_open)
    rejection_params = {
      reason: "some reason",
      replaced_by: "CVE-2000-0001",
    }
    CVEAPI::Client.any_instance.expects(:reject_cve).with(cve_review.assigned_cve_id, previously_published: false, rejected_reasons: ["some reason"], replaced_by: ["CVE-2000-0001"])

    MITRECVESubmission.record_cve_rejection(cve_review: cve_review, rejection_params: rejection_params)

    assert_equal 1, MITRECVESubmission.count
    mitre_cve_submission = MITRECVESubmission.first
    assert_equal cve_review.ghsa_id, mitre_cve_submission.ghsa_id
    assert_equal "api", mitre_cve_submission.pull_request_url
  end

  test "record_cve_rejection for published CVE that has been reopened" do
    cve_review = create(:cve_review, :curation_state_open_update)
    assert_equal 1, MITRECVESubmission.count
    rejection_params = {
      reason: "some reason",
      replaced_by: "CVE-2000-0001",
    }
    CVEAPI::Client.any_instance.expects(:reject_cve).with(cve_review.assigned_cve_id, previously_published: true, rejected_reasons: ["some reason"], replaced_by: ["CVE-2000-0001"])

    new_updated_at = 1.day.from_now.change(usec: 0)
    Timecop.freeze(new_updated_at) do
      MITRECVESubmission.record_cve_rejection(cve_review: cve_review, rejection_params: rejection_params)
    end

    assert_equal 1, MITRECVESubmission.count
    mitre_cve_submission = MITRECVESubmission.first
    assert_equal cve_review.ghsa_id, mitre_cve_submission.ghsa_id
    assert_equal "api", mitre_cve_submission.pull_request_url
    assert_equal new_updated_at, mitre_cve_submission.updated_at
  end
end
