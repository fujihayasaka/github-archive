# frozen_string_literal: true

require "test_helper"
require "rake"
require "active_support/core_ext/kernel/reporting"

class ConvertPayloadStructureTest < ActiveSupport::TestCase
  setup do
    AdvisoryDB::Application.load_tasks if Rake::Task.tasks.empty?
  end

  test "rake payload_structure:backfill_structured_payload runs without error" do
    create_list(:advisory_review, 5)
    review_with_withdrawn_vulns = AdvisoryReview.last
    vulns = review_with_withdrawn_vulns.advisory_payload["vulnerabilities"]
    vulns.each_value do |v|
      v["withdrawn"] = true
    end
    review_with_withdrawn_vulns.save!

    output = capture_io do
      assert_nothing_raised do
        Rake::Task["payload_structure:backfill_structured_payload"].execute({ dry_run: "false" })
      end
    end

    lines = output[0].split("\n")
    assert(lines.any? { |l| l.include? "Transitioned 5 advisory reviews" })

    AdvisoryReview.all.each do |advisory_review|
      sap = advisory_review.structured_advisory_payload
      ap = advisory_review.advisory_payload

      assert_equal ap["summary"], sap.summary
      assert_equal ap["description"], sap.description
      assert_equal ap["source_code_location"], sap.source_code_location
      assert_equal ap["severity"], sap.severity
      assert_equal ap["cvss_v3"], sap.cvss_v3
      assert_equal ap["withdrawn"], sap.withdrawn

      db_cwe_ids = advisory_review.structured_advisory_payload.cwe_ids.order(index: :asc)
      ap["cwe_ids"].each_with_index do |cwe_id, i|
        assert_equal cwe_id, db_cwe_ids[i].cwe_id
      end

      db_refs = advisory_review.structured_advisory_payload.references.order(index: :asc)
      ap["references"].each_with_index do |ref, i|
        assert_equal ref, db_refs[i].url
      end

      db_vulns = advisory_review.structured_advisory_payload.vulnerabilities.order(index: :asc)

      if advisory_review == review_with_withdrawn_vulns
        assert_equal db_vulns.count, 0
      else
        assert_equal db_vulns.count, ap["vulnerabilities"].count
      end
      ap["vulnerabilities"].each do |i, apv|
        if apv["withdrawn"]
          assert_nil db_vulns[i]
          next
        end

        vuln = db_vulns[i]
        assert_equal apv["ecosystem"], vuln.package_ecosystem
        assert_equal apv["package_name"], vuln.package_name
        assert_equal apv["vulnerable_version_range"], vuln.vulnerable_version_range
        assert_equal apv["first_patched_version"], vuln.first_patched_version
      end
    end
  end

  test "rake payload_structure:backfill_structured_payload runs without error with missing enumeration properties" do
    create_list(:advisory_review, 2)
    first_review = AdvisoryReview.all[0]
    second_review = AdvisoryReview.all[1]

    first_review.advisory_payload.delete("cwe_ids")
    first_review.advisory_payload.delete("references")
    first_review.advisory_payload.delete("vulnerabilities")
    first_review.save!

    second_review.save!

    output = capture_io do
      assert_nothing_raised do
        Rake::Task["payload_structure:backfill_structured_payload"].execute({ dry_run: "false" })
      end
    end

    lines = output[0].split("\n")
    assert(lines.any? { |l| l.include? "Transitioned 2 advisory reviews" })
  end

  test "rake payload_structure:verify_structured_payload runs with errors when structured payloads don't exist" do
    create_list(:advisory_review, 2)
    AdvisoryReview.all[0]
    AdvisoryReview.all[1]

    Failbot.stubs(:report!).raises("The failbot method should not be called during this test run")
    GitHub::Telemetry::Logs.logger.stubs(:error).raises("The logger.error method should not be called during this test run")

    output = capture_io do
      assert_nothing_raised do
        Rake::Task["payload_structure:verify_structured_payload"].execute
      end
    end

    lines = output[0].split("\n")
    assert(lines.any? { |l| l.include? "2 set(s) of advisory payloads didn't match" })
  end

  test "rake payload_structure:verify_structured_payload logs errors only when given arguments to do so" do
    create_list(:advisory_review, 2)
    AdvisoryReview.all[0]
    AdvisoryReview.all[1]

    error_list = []
    Failbot.stubs(:report!).with do |error, _hash|
      error_list << error
    end

    output = capture_io do
      assert_nothing_raised do
        Rake::Task["payload_structure:verify_structured_payload"].execute({ console_only_errors: "false" })
      end
    end

    lines = output[0].split("\n")
    assert(lines.any? { |l| l.include? "2 set(s) of advisory payloads didn't match" })

    assert_equal 2, error_list.count
    assert(error_list.all? { |e| e.message.include? "No structured payload was found." })
  end

  test "rake payload_structure:verify_structured_payload runs without error" do
    create_list(:advisory_review, 5)

    # first, backfill and make sure backfill worked as expected.
    output = capture_io do
      assert_nothing_raised do
        Rake::Task["payload_structure:backfill_structured_payload"].execute({ dry_run: "false" })
      end
    end

    lines = output[0].split("\n")
    assert(lines.any? { |l| l.include? "Transitioned 5 advisory reviews" })

    Failbot.stubs(:report!).raises("The failbot method should not be called during this test run")
    GitHub::Telemetry::Logs.logger.stubs(:error).raises("The logger.error method should not be called during this test run")

    # next, verify and make sure no errors are called
    output = capture_io do
      assert_nothing_raised do
        Rake::Task["payload_structure:verify_structured_payload"].execute
      end
    end

    lines = output[0].split("\n")
    assert(lines.any? { |l| l.include? "Compared 5 advisory reviews" })

    # we don't test content in this case, just look for the success messages
  end
end
