# frozen_string_literal: true

require "test_helper"

class UpdateMismatchedCVSSAndSeveritiesJobTest < ActiveJob::TestCase
  test "updates the severity on an Advisory and an Advisory Review with CVSS 3 and CVSS 4 when their severity does not match the CVSS 4 vector string" do
    advisory = create(
      :advisory,
      cvss_v3: "CVSS:3.1/AV:N/AC:L/PR:H/UI:R/S:U/C:L/I:L/A:L",
      cvss_v4: "CVSS:4.0/AV:N/AC:L/AT:N/PR:N/UI:N/VC:L/VI:L/VA:L/SC:H/SI:H/SA:H",
      severity: "moderate", # The severity should be "high," but we're setting it to "moderate" to test that the job updates it
    )
    advisory_review = advisory.advisory_review
    advisory_payload = advisory_review.advisory_payload

    advisory_payload["cvss_v3"] = "CVSS:3.1/AV:N/AC:L/PR:H/UI:R/S:U/C:L/I:L/A:L"
    advisory_payload["cvss_v4"] = "CVSS:4.0/AV:N/AC:L/AT:N/PR:N/UI:N/VC:L/VI:L/VA:L/SC:H/SI:H/SA:H"
    advisory_payload["severity"] = "moderate" # The severity should be "high," but we're setting it to "moderate" to test that the job updates it
    advisory_review.update!(advisory_payload: advisory_review.advisory_payload)

    assert_enqueued_with job: PublishAdvisoryToHydroJob do
      assert_changes -> { advisory.reload.severity }, from: "moderate", to: "high" do
        assert_changes -> { advisory_review.reload.severity }, from: "moderate", to: "high" do
          UpdateMismatchedCVSSAndSeveritiesJob.new.perform(dry_run: false)
        end
      end
    end
  end

  test "updates the severity on an Advisory and not the Advisory Review when the Advisory is the only thing with a mismatched" do
    advisory = create(
      :advisory,
      cvss_v3: "CVSS:3.1/AV:N/AC:L/PR:H/UI:R/S:U/C:L/I:L/A:L",
      cvss_v4: "CVSS:4.0/AV:N/AC:L/AT:N/PR:N/UI:N/VC:L/VI:L/VA:L/SC:H/SI:H/SA:H",
      severity: "moderate", # The severity should be "high," but we're setting it to "moderate" to test that the job updates it
    )
    advisory_review = advisory.advisory_review
    advisory_payload = advisory_review.advisory_payload

    advisory_payload["cvss_v3"] = "CVSS:3.1/AV:N/AC:L/PR:H/UI:R/S:U/C:L/I:L/A:L"
    advisory_payload["cvss_v4"] = "CVSS:4.0/AV:N/AC:L/AT:N/PR:N/UI:N/VC:L/VI:L/VA:L/SC:H/SI:H/SA:H"
    advisory_payload["severity"] = "high"
    advisory_review.update!(advisory_payload: advisory_review.advisory_payload)

    assert_enqueued_with job: PublishAdvisoryToHydroJob do
      assert_changes -> { advisory.reload.severity }, from: "moderate", to: "high" do
        assert_no_changes -> { advisory_review.reload.severity }, from: advisory_review.severity do
          UpdateMismatchedCVSSAndSeveritiesJob.new.perform(dry_run: false)
        end
      end
    end
  end

  test "updates the severity on an Advisory Review and not the Advisory when the Advisory Review is the only thing with a mismatched" do
    advisory = create(
      :advisory,
      cvss_v3: "CVSS:3.1/AV:N/AC:L/PR:H/UI:R/S:U/C:L/I:L/A:L",
      cvss_v4: "CVSS:4.0/AV:N/AC:L/AT:N/PR:N/UI:N/VC:L/VI:L/VA:L/SC:H/SI:H/SA:H",
      severity: "high",
    )
    advisory_review = advisory.advisory_review
    advisory_payload = advisory_review.advisory_payload

    advisory_payload["cvss_v3"] = "CVSS:3.1/AV:N/AC:L/PR:H/UI:R/S:U/C:L/I:L/A:L"
    advisory_payload["cvss_v4"] = "CVSS:4.0/AV:N/AC:L/AT:N/PR:N/UI:N/VC:L/VI:L/VA:L/SC:H/SI:H/SA:H"
    advisory_payload["severity"] = "moderate" # The severity should be "high," but we're setting it to "moderate" to test that the job updates it
    advisory_review.update!(advisory_payload: advisory_review.advisory_payload)

    assert_no_changes -> { advisory.reload.severity }, from: advisory.severity do
      assert_changes -> { advisory_review.reload.severity }, from: "moderate", to: "high" do
        UpdateMismatchedCVSSAndSeveritiesJob.new.perform(dry_run: false)
      end
    end
  end

  test "does not change the severity on an Advisory or Advisory Review with CVSS 3 and CVSS 4 when the severity matches the CVSS 4 vector string" do
    advisory = create(
      :advisory,
      cvss_v3: "CVSS:3.1/AV:N/AC:L/PR:H/UI:R/S:U/C:L/I:L/A:L",
      cvss_v4: "CVSS:4.0/AV:N/AC:L/AT:N/PR:N/UI:N/VC:L/VI:L/VA:L/SC:H/SI:H/SA:H",
      severity: "high",
    )
    advisory_review = advisory.advisory_review
    advisory_payload = advisory_review.advisory_payload

    advisory_payload["cvss_v3"] = "CVSS:3.1/AV:N/AC:L/PR:H/UI:R/S:U/C:L/I:L/A:L"
    advisory_payload["cvss_v4"] = "CVSS:4.0/AV:N/AC:L/AT:N/PR:N/UI:N/VC:L/VI:L/VA:L/SC:H/SI:H/SA:H"
    advisory_payload["severity"] = "high"
    advisory_review.update!(advisory_payload: advisory_review.advisory_payload)

    assert_no_changes -> { advisory_review.reload.severity }, from: advisory_review.severity do
      assert_no_changes -> { advisory.reload.severity }, from: advisory.severity do
        UpdateMismatchedCVSSAndSeveritiesJob.new.perform(dry_run: false)
      end
    end
  end

  test "does not operate on Advisories or Advisory Reviews with only CVSS 3 or CVSS 4" do
    logger = GitHub::Telemetry::Logs.logger

    advisory = create(
      :advisory,
      cvss_v3: "CVSS:3.1/AV:N/AC:L/PR:H/UI:R/S:U/C:L/I:L/A:L",
      severity: "moderate",
    )
    advisory_review = advisory.advisory_review
    advisory_payload = advisory_review.advisory_payload

    advisory_payload["cvss_v3"] = "CVSS:3.1/AV:N/AC:L/PR:H/UI:R/S:U/C:L/I:L/A:L"
    advisory_payload["severity"] = "moderate"
    advisory_review.update!(advisory_payload: advisory_review.advisory_payload)

    logger.expects(:info).with("No Advisories to update.")

    UpdateMismatchedCVSSAndSeveritiesJob.new.perform(dry_run: false, log: true)
  end

  test "does not operate on withdrawn Advisories and Advisory Reviews" do
    logger = GitHub::Telemetry::Logs.logger

    advisory = create(
      :advisory,
      cvss_v3: "CVSS:3.1/AV:N/AC:L/PR:H/UI:R/S:U/C:L/I:L/A:L",
      cvss_v4: "CVSS:4.0/AV:N/AC:L/AT:N/PR:N/UI:N/VC:L/VI:L/VA:L/SC:H/SI:H/SA:H",
      severity: "moderate",
      withdrawn_at: 1.day.ago,
    )
    advisory_review = advisory.advisory_review
    advisory_payload = advisory_review.advisory_payload

    advisory_payload["cvss_v3"] = "CVSS:3.1/AV:N/AC:L/PR:H/UI:R/S:U/C:L/I:L/A:L"
    advisory_payload["cvss_v4"] = "CVSS:4.0/AV:N/AC:L/AT:N/PR:N/UI:N/VC:L/VI:L/VA:L/SC:H/SI:H/SA:H"
    advisory_payload["severity"] = "moderate"
    advisory_review.update!(advisory_payload: advisory_review.advisory_payload)

    logger.expects(:info).with("No Advisories to update.")

    UpdateMismatchedCVSSAndSeveritiesJob.new.perform(dry_run: false, log: true)
  end

  test "rescues errors and does not update Advisories or Advisory Reviews" do
    advisory = create(
      :advisory,
      cvss_v3: "CVSS:3.1/AV:N/AC:L/PR:H/UI:R/S:U/C:L/I:L/A:L",
      cvss_v4: "CVSS:4.0/AV:N/AC:L/AT:N/PR:N/UI:N/VC:L/VI:L/VA:L/SC:H/SI:H/SA:H",
      severity: "moderate", # The severity should be "high," but we're setting it to "moderate" to test that the job updates it
    )
    advisory_review = advisory.advisory_review
    advisory_payload = advisory_review.advisory_payload

    advisory_payload["cvss_v3"] = "CVSS:3.1/AV:N/AC:L/PR:H/UI:R/S:U/C:L/I:L/A:L"
    advisory_payload["cvss_v4"] = "CVSS:4.0/AV:N/AC:L/AT:N/PR:N/UI:N/VC:L/VI:L/VA:L/SC:H/SI:H/SA:H"
    advisory_payload["severity"] = "moderate" # The severity should be "high," but we're setting it to "moderate" to test that the job updates it
    advisory_review.update!(advisory_payload: advisory_review.advisory_payload)

    UpdateMismatchedCVSSAndSeveritiesJob.any_instance.stubs(:perform).raises(StandardError.new("Exception raised while updating mismatched CVSS and severities."))

    assert_no_changes -> { advisory_review.reload.severity }, from: advisory_review.severity do
      assert_no_changes -> { advisory.reload.severity }, from: advisory.severity do
        assert_raises StandardError do
          UpdateMismatchedCVSSAndSeveritiesJob.new.perform(dry_run: false)
        end
      end
    end
  end

  test "can be executed as a dry run" do
    advisory = create(
      :advisory,
      cvss_v3: "CVSS:3.1/AV:N/AC:L/PR:H/UI:R/S:U/C:L/I:L/A:L",
      cvss_v4: "CVSS:4.0/AV:N/AC:L/AT:N/PR:N/UI:N/VC:L/VI:L/VA:L/SC:H/SI:H/SA:H",
      severity: "moderate",
    )
    advisory_review = advisory.advisory_review
    advisory_payload = advisory_review.advisory_payload

    advisory_payload["cvss_v3"] = "CVSS:3.1/AV:N/AC:L/PR:H/UI:R/S:U/C:L/I:L/A:L"
    advisory_payload["cvss_v4"] = "CVSS:4.0/AV:N/AC:L/AT:N/PR:N/UI:N/VC:L/VI:L/VA:L/SC:H/SI:H/SA:H"
    advisory_payload["severity"] = "moderate"
    advisory_review.update!(advisory_payload: advisory_review.advisory_payload)

    assert true, File.exist?("log/dry_run_update_mismatched_cvss_and_severities_job.log")

    assert_no_changes -> { advisory_review.reload.severity }, from: advisory_review.severity do
      assert_no_changes -> { advisory.reload.severity }, from: advisory.severity do
        UpdateMismatchedCVSSAndSeveritiesJob.new.perform # The default is a dry run
      end
    end
  end
end
