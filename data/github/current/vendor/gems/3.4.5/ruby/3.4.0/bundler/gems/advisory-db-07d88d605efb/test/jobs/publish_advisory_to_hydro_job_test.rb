# frozen_string_literal: true

require "test_helper"

class PublishAdvisoryToHydroJobTest < ActiveJob::TestCase
  test "publishes a SubmitAdvisory message to Hydro" do
    advisory = create(:advisory)

    assert_changes -> { hydro_messages.count }, from: 0, to: 1 do
      PublishAdvisoryToHydroJob.new.perform(advisory)
    end

    message = hydro_messages.last
    assert_equal advisory.ghsa_id, message[:advisory][:ghsa_id]
    assert message[:review_lab_ref].blank?
  end

  test "publishes the status to Hydro" do
    advisory = create(:advisory)

    assert_changes -> { hydro_messages.count }, from: 0, to: 1 do
      PublishAdvisoryToHydroJob.new.perform(advisory)
    end

    message = hydro_messages.last
    assert_equal :REVIEWED, message[:status]

    advisory = create(:unreviewed_advisory)

    assert_changes -> { hydro_messages.count }, from: 1, to: 2 do
      PublishAdvisoryToHydroJob.new.perform(advisory)
    end

    message = hydro_messages.last
    assert_equal :UNREVIEWED, message[:status]
  end

  test "publishes the source_code_location when it is set" do
    source_code_location = "https://github.com/github/advisory-db"
    advisory = create(:advisory, source_code_location: source_code_location)

    assert_changes -> { hydro_messages.count }, from: 0, to: 1 do
      PublishAdvisoryToHydroJob.new.perform(advisory)
    end

    message = hydro_messages.last
    assert_equal source_code_location, message[:advisory][:source_code_location]
  end

  test "publishes the advisory's vulnerabilities to Hyrdo" do
    advisory = create(:advisory, vulnerability_count: 0)
    create(:vulnerability, {
      advisory: advisory,
      package_ecosystem: "rubygems",
      package_name: "rails",
      vulnerable_version_range: "< 6.0.0",
      first_patched_version: "6.0.0",
      index: 0,
    })
    create(:vulnerability, {
      advisory: advisory,
      package_ecosystem: "npm",
      package_name: "lodash",
      vulnerable_version_range: "< 5.0.0",
      first_patched_version: nil,
      index: 1,
    })

    PublishAdvisoryToHydroJob.new.perform(advisory)

    message = hydro_messages.last
    assert_equal [
      {
        package_ecosystem: :RUBYGEMS,
        package_name: "rails",
        vulnerable_version_range: "< 6.0.0",
        first_patched_version: "6.0.0",
        affected_functions: [], # Leave empty until we remove it from the Protobuf
        affected_functions_json: "", # Leave empty until we remove it from the Protobuf
      },
      {
        package_ecosystem: :NPM,
        package_name: "lodash",
        vulnerable_version_range: "< 5.0.0",
        first_patched_version: "",
        affected_functions: [], # Leave empty until we remove it from the Protobuf
        affected_functions_json: "", # Leave empty until we remove it from the Protobuf
      },
    ], message[:advisory][:vulnerabilities]
  end

  test "publishes the identifiers for an advisory when all are populated" do
    advisory = create(:advisory, cve_id: "CVE-1888-1234", white_source_id: "WS-2345-2345", npm_id: 1234)

    assert_changes -> { hydro_messages.count }, from: 0, to: 1 do
      PublishAdvisoryToHydroJob.new.perform(advisory)
    end

    message = hydro_messages.last

    assert message[:advisory][:ghsa_id].starts_with?("GHSA-")
    assert_equal advisory.ghsa_id, message[:advisory][:ghsa_id]

    assert message[:advisory][:cve_id].starts_with?("CVE-")
    assert_equal advisory.cve_id, message[:advisory][:cve_id]

    assert message[:advisory][:white_source_id].starts_with?("WS-")
    assert_equal advisory.white_source_id, message[:advisory][:white_source_id]

    assert message[:advisory][:npm_id].present?
    assert_equal advisory.npm_id, message[:advisory][:npm_id]

    refute message[:advisory][:external_identifier].present?
  end

  test "publishes the CWE ID when it is populated" do
    cwe_1 = create(:cwe, cwe_id: "CWE-79")
    cwe_2 = create(:cwe, cwe_id: "CWE-1302")
    advisory = create(:advisory, cve_id: "CVE-1888-1234", white_source_id: "WS-2345-2345", npm_id: 1234, cwes: [cwe_1, cwe_2])

    assert_changes -> { hydro_messages.count }, from: 0, to: 1 do
      PublishAdvisoryToHydroJob.new.perform(advisory)
    end

    message = hydro_messages.last

    assert_equal ["CWE-79", "CWE-1302"], message[:advisory][:cwe_ids]
  end

  test "publishes when only ghsa_id is set" do
    advisory = create(:advisory, cve_id: nil, white_source_id: nil, npm_id: nil)

    assert_changes -> { hydro_messages.count }, from: 0, to: 1 do
      PublishAdvisoryToHydroJob.new.perform(advisory)
    end

    message = hydro_messages.last

    assert message[:advisory][:ghsa_id].starts_with?("GHSA-")
    assert_equal advisory.ghsa_id, message[:advisory][:ghsa_id]

    # values publish with default values, there is no null or nil in hydro
    assert_equal "", message[:advisory][:cve_id]
    assert_equal "", message[:advisory][:white_source_id]
    assert_equal 0, message[:advisory][:npm_id]

    refute message[:advisory][:external_identifier].present?
  end

  test "publishes a test message to a specific review-lab" do
    advisory = create(:advisory)
    review_lab_ref = "foo/bar-baz"

    assert_changes -> { hydro_messages.count }, from: 0, to: 1 do
      PublishAdvisoryToHydroJob.new.perform(advisory, review_lab_ref: review_lab_ref)
    end

    message = hydro_messages.last
    assert_equal advisory.ghsa_id, message[:advisory][:ghsa_id]
    assert_equal review_lab_ref, message[:review_lab_ref]
  end

  test "publishes the cvss_v3 when it is set" do
    cvss_v3 = "CVSS:3.1/AV:N/AC:H/PR:L/UI:R/S:C/C:H/I:L/A:L"
    advisory = create(:advisory, cvss_v3: cvss_v3)

    assert_changes -> { hydro_messages.count }, from: 0, to: 1 do
      PublishAdvisoryToHydroJob.new.perform(advisory)
    end

    message = hydro_messages.last
    assert_equal cvss_v3, message[:advisory][:cvss_v3]
  end

  test "publishes the reviewed_at timestamp when it is set" do
    advisory = create(:advisory, reviewed_at: Time.zone.now)

    assert_changes -> { hydro_messages.count }, from: 0, to: 1 do
      PublishAdvisoryToHydroJob.new.perform(advisory)
    end

    message = hydro_messages.last
    refute_nil message[:advisory][:reviewed_at]
  end

  test "publishes the nvd_published_at timestamp when it is set" do
    advisory = create(:advisory, nvd_published_at: 1.minute.ago)

    assert_changes -> { hydro_messages.count }, from: 0, to: 1 do
      PublishAdvisoryToHydroJob.new.perform(advisory)
    end

    message = hydro_messages.last
    refute_nil message[:advisory][:nvd_published_at]
  end

  test "publishes the version_id alongside the advisory" do
    advisory = create(:advisory, nvd_published_at: 1.minute.ago)

    assert_changes -> { hydro_messages.count }, from: 0, to: 1 do
      PublishAdvisoryToHydroJob.new.perform(advisory)
    end

    message = hydro_messages.last
    assert_equal advisory.versions.last.id, message[:version_id]
  end

  test "publishes the hydro_payload_hash alongside the advisory" do
    advisory = create(:advisory, nvd_published_at: 1.minute.ago)

    assert_changes -> { hydro_messages.count }, from: 0, to: 1 do
      PublishAdvisoryToHydroJob.new.perform(advisory)
    end

    message = hydro_messages.last
    assert_equal Digest::MD5.hexdigest(JSON.dump(advisory.hydro_payload)), message[:hydro_payload_hash]
  end

  test "publishes when Advisory description is non-ascii compatible" do
    description = "### Overview\nVersions after and including `2.3.0` are improperly validating the JWT token signature when using the `JWTValidator.verify` method.  Improper validation of the JWT token signature when not using the default Authorization Code Flow can allow an attacker to bypass authentication and authorization.\n\n### Am I affected?\nYou are affected by this vulnerability if all of the following conditions apply:\n\n- You are using `omniauth-auth0`.\n- You are using `JWTValidator.verify` method directly OR you are not authenticating using the SDK\xE2\x80\x99s default Authorization Code Flow.\n\n### How to fix that?\nUpgrade to version `2.4.1`.\n\n### Will this update impact my users?\nThe fix provided in this version will not affect your users."
    advisory = create(:advisory, description: description.dup.force_encoding(::Encoding::ASCII_8BIT))

    assert_changes -> { hydro_messages.count }, from: 0, to: 1 do
      PublishAdvisoryToHydroJob.new.perform(advisory)
    end

    message = hydro_messages.last
    assert_equal description, message[:advisory][:description]
  end

  test "publishes credits when advisory improvements are provided" do
    advisory = create(:advisory)
    PublishAdvisoryToHydroJob.new.perform(advisory)

    message = hydro_messages.last
    assert_equal 0, message[:advisory][:credits].length

    PublishAdvisoryToHydroJob.new.perform(advisory, credits: [{ recipient_id: 1234 }])

    message = hydro_messages.last
    assert_equal 1, message[:advisory][:credits].length
    assert_equal 1234, message[:advisory][:credits][0][:recipient_id]
  end

  test "increments dogstat if result returns an error" do
    expect_hydro_publish_error_stat_for(PublishAdvisoryToHydroJob)

    advisory = create(:advisory)
    PublishAdvisoryToHydroJob.new.perform(advisory)
  end

  class TestPublishAdvisoryToHydroJob < PublishAdvisoryToHydroJob
    def perform(_advisory, _credits: [], _review_lab_ref: "")
      raise StandardError "test error"
    rescue StandardError
      raise ActiveJob::DeserializationError
    end
  end

  test "job retries when ActiveJob::DeserializationError is raised" do
    test_job = TestPublishAdvisoryToHydroJob.new(true)
    perform_enqueued_jobs do
      test_job.perform_now
    rescue StandardError => _error # rubocop:disable Lint/SuppressedException
    end

    assert_equal 5, test_job.exception_executions["[ActiveJob::DeserializationError]"]
  end
end
