# frozen_string_literal: true

require "test_helper"

class PrimaryHydroProcessorTest < ActiveJob::TestCase
  # TESTS FOR AdvisoryPrediction message type

  test "enqueues a ProcessAdvisoryPredictionJob for an AdvisoryPrediction message" do
    feed_entry = create :feed_entry

    AdvisoryDB.hydro_publisher.publish(
      {
        identifier: feed_entry.identifier,
        reject_prediction: "NOT_REJECT",
      },
      schema: "advisory_db.v0.AdvisoryPrediction", topic_format_options: { format_version: Hydro::Topic::FormatVersion::V1 },
    )

    assert_enqueued_with(
      job: ProcessAdvisoryPredictionJob,
      args: [
        identifier: feed_entry.identifier,
        reject_prediction: "NOT_REJECT",
      ],
    ) do
      AdvisoryDB.primary_hydro_executor.run_processor_loop
    end
  end

  test "enqueues a ProcessAdvisoryPredictionJob for each AdvisoryPrediction message" do
    3.times do
      AdvisoryDB.hydro_publisher.publish(
        {
          identifier: "not_real_identifier",
          reject_prediction: ["REJECT", "NOT_REJECT"].sample,
        },
        schema: "advisory_db.v0.AdvisoryPrediction", topic_format_options: { format_version: Hydro::Topic::FormatVersion::V1 },
      )
    end

    assert_enqueued_jobs 3, only: ProcessAdvisoryPredictionJob do
      AdvisoryDB.primary_hydro_executor.run_processor_loop
    end
  end

  # TESTS FOR CVERequest message type

  def make_cve_request(*args)
    ::AdvisoryDB.hydro_publisher.publish(
      FactoryBot.create(:cve_request_hydro_payload, *args),
      schema: "advisory_db.v0.CVERequest", topic_format_options: { format_version: Hydro::Topic::FormatVersion::V1 },
    )
  end

  test "Creates a new CVERequest object for each CVERequest hydro object" do
    make_cve_request(
      ghsa_id: "GHSA-1234-1234-1234",
      cvss_v3: "CVSS:3.1/AV:A/AC:H/PR:L/UI:R/S:U/C:L/I:H/A:N",
      cvss_v4: "CVSS:4.0/AV:N/AC:L/AT:N/PR:N/UI:N/VC:H/VI:H/VA:H/SC:N/SI:N/SA:N",
    )

    assert_difference("CVERequest.count", 1) do
      AdvisoryDB.primary_hydro_executor.run_processor_loop
    end

    new_cve_request = CVERequest.last
    expected_request_values = {
      "ghsa_id" => "GHSA-1234-1234-1234",
      "actor_id" => 1234,
      "actor_login" => "testuser",
      "advisory_permalink" => "https://github.com/testorg/testrepo/security/advisories/GHSA-1234-1234-1234",
      "advisory_state" => "draft",
      "title" => "This is a test advisory title",
      "description" => "This is a test advisory description",
      "severity" => "low",
      "cvss_v3" => "CVSS:3.1/AV:A/AC:H/PR:L/UI:R/S:U/C:L/I:H/A:N",
      "cvss_v4" => "CVSS:4.0/AV:N/AC:L/AT:N/PR:N/UI:N/VC:H/VI:H/VA:H/SC:N/SI:N/SA:N",
    }
    expected_request_values.each_pair do |field, expected_value|
      assert_equal expected_value, new_cve_request[field]
    end
    assert_equal "cargo", new_cve_request.affected_products_payload[0]["ecosystem"]
    assert_equal "popular_package", new_cve_request.affected_products_payload[0]["package"]
    assert_equal "< 1.2.3", new_cve_request.affected_products_payload[0]["affected_versions"]
    assert_equal "1.2.3", new_cve_request.affected_products_payload[0]["patches"]
  end

  test "Creates a new CVERequest object with affected products if that is included in the incoming CVERequest hydro message" do
    message_affected_products = [
      {
        package_ecosystem: "npm",
        package_name: "nodemon",
        vulnerable_version_range: "< 1.0.0",
        first_patched_version: "1.0.0",
      },
      {
        package_ecosystem: "go",
        package_name: "gomon",
        vulnerable_version_range: "< 1.2.3",
        first_patched_version: "1.2.3",
      },
      {
        package_ecosystem: "nuget",
        package_name: "nugetmon",
        vulnerable_version_range: "< 2.3.4",
        first_patched_version: "2.3.4",
      },
    ]

    make_cve_request(affected_products: message_affected_products)
    assert_difference("CVERequest.count", 1) do
      AdvisoryDB.primary_hydro_executor.run_processor_loop
    end

    affected_products_payload = CVERequest.last.affected_products_payload
    message_affected_products.each_with_index do |message_affected_product, index|
      assert_equal message_affected_product[:package_ecosystem], affected_products_payload[index]["ecosystem"]
      assert_equal message_affected_product[:package_name], affected_products_payload[index]["package"]
      assert_equal message_affected_product[:vulnerable_version_range], affected_products_payload[index]["affected_versions"]
      assert_equal message_affected_product[:first_patched_version], affected_products_payload[index]["patches"]
    end
  end

  test "Enqueues the ResolveCVERequestJob" do
    make_cve_request

    assert_enqueued_with(job: ResolveCVERequestJob) do
      AdvisoryDB.primary_hydro_executor.run_processor_loop
    end
  end

  test "can handle unicode in the title" do
    test_str = "Unicode: ❤🤠️ 测试"
    make_cve_request title: test_str,
      description: test_str,
      cvss_v3: test_str

    assert_difference("CVERequest.count", 1) do
      AdvisoryDB.primary_hydro_executor.run_processor_loop
    end

    new_cve_request = CVERequest.last
    assert_equal test_str, new_cve_request.title
    assert_equal test_str, new_cve_request.description
    assert_equal test_str, new_cve_request.cvss_v3
  end

  test "reports exception to failbot" do
    make_cve_request ghsa_id: "ThisIsInvalidWillCauseException"

    AdvisoryDB.primary_hydro_executor.run_processor_loop

    last_failbot_report = Failbot.backend.reports.last
    assert_equal "ActiveRecord::ValueTooLong", last_failbot_report["exception_detail"].last["type"]
  end

  test "continues to process requests after one raises an exception" do
    make_cve_request ghsa_id: "ThisIsInvalidWillCauseException"
    make_cve_request ghsa_id: "GHSA-0000-000v-alid"

    assert_difference("CVERequest.count", 1) do
      AdvisoryDB.primary_hydro_executor.run_processor_loop
    end

    assert_equal "GHSA-0000-000v-alid", CVERequest.last.ghsa_id
  end

  test "Re-processes messages if they initially failed to process" do
    # in test mode, hydro-client uses a MemorySink backend, not a Kafka backend
    # That memory sink is recreated each time we make an executor, therefore,
    # tests that depend on offsets in "kafka", like this one, need to use the same executor instance
    make_cve_request ghsa_id: "GHSA-1000-000v-alid"

    executor = AdvisoryDB.primary_hydro_executor

    assert_difference("CVERequest.count", 1) do
      executor.run_processor_loop
    end

    assert_equal "GHSA-1000-000v-alid", CVERequest.last.ghsa_id

    make_cve_request ghsa_id: "GHSA-2000-000v-alid"

    # set it up so DB call fails
    # make DB return Mysql2::Error::ConnectionError
    PrimaryHydroProcessor.any_instance.stubs(:process_cve_request).raises(Mysql2::Error::ConnectionError, "Test")
    assert_no_difference("CVERequest.count") do
      executor.run_processor_loop
    end

    PrimaryHydroProcessor.any_instance.unstub(:process_cve_request)
    assert_difference("CVERequest.count", 1) do
      executor.run_processor_loop
    end

    assert_equal "GHSA-2000-000v-alid", CVERequest.last.ghsa_id

    # make sure it does not re-process the message once it succeeded
    assert_no_difference("CVERequest.count") do
      executor.run_processor_loop
    end
  end

  # TESTS FOR github.v1.RepositoryAdvisoryCurationRequest message type

  def send_repository_advisory_curation_request_message(hydro_payload)
    ::AdvisoryDB.hydro_publisher.publish(
      hydro_payload,
      schema: "advisory_db.v0.RepositoryAdvisoryCurationRequest", topic_format_options: { format_version: Hydro::Topic::FormatVersion::V1 },
    )
  end

  test "enqueues a ProcessRepositoryAdvisoryCurationRequestJob for a RepositoryAdvisoryPublish message" do
    payload = FactoryBot.create(:repository_advisory_curation_request_hydro_payload)
    send_repository_advisory_curation_request_message(payload)

    expected_obj = RepositoryAdvisoryCurationData.new(
      ghsa_id: payload["repository_advisory_content"]["ghsa_id"],
      permalink: payload["repository_advisory_content"]["permalink"],
      title: payload["repository_advisory_content"]["title"],
      description: payload["repository_advisory_content"]["description"],
      severity: payload["repository_advisory_content"]["severity"].downcase,
      cve_id: payload["repository_advisory_content"]["cve_id"],
      cwe_ids: payload["repository_advisory_content"]["cwe_ids"],
      cvss_v3: payload["repository_advisory_content"]["cvss_v3"],
      cvss_v4: payload["repository_advisory_content"]["cvss_v4"],
      affected_products: payload["repository_advisory_content"]["affected_products"],
    )

    assert_enqueued_with(
      job: ProcessRepositoryAdvisoryCurationRequestJob,
      args: [
        repo_advisory_curation_data_hash: expected_obj.to_h,
      ],
    ) do
      AdvisoryDB.primary_hydro_executor.run_processor_loop
    end
  end

  test "enqueues a ProcessRepositoryAdvisoryCurationRequestJob that includes multiple affected products if they were given" do
    affected_products_with_indifferent_access = [
      {
        package_ecosystem: "npm",
        package_name: "nodemon",
        vulnerable_version_range: "< 1.0.0",
        first_patched_version: "1.0.0",
        affected_functions: [],
        affected_functions_json: "",
      },
      {
        package_ecosystem: "go",
        package_name: "gomon",
        vulnerable_version_range: "< 1.2.3",
        first_patched_version: "1.2.3",
        affected_functions: [],
        affected_functions_json: "",
      },
      {
        package_ecosystem: "nuget",
        package_name: "nugetmon",
        vulnerable_version_range: "< 2.3.4",
        first_patched_version: "2.3.4",
        affected_functions: [],
        affected_functions_json: "",
      },
    ].map(&:with_indifferent_access)
    hydro_payload = create(:repository_advisory_curation_request_hydro_payload)
    hydro_payload["repository_advisory_content"]["affected_products"] = affected_products_with_indifferent_access

    send_repository_advisory_curation_request_message(hydro_payload)

    expected_repository_advisory_curation_data_hash = {
      affected_products: affected_products_with_indifferent_access,
      ghsa_id: hydro_payload["repository_advisory_content"]["ghsa_id"],
      permalink: hydro_payload["repository_advisory_content"]["permalink"],
      title: hydro_payload["repository_advisory_content"]["title"],
      description: hydro_payload["repository_advisory_content"]["description"],
      severity: hydro_payload["repository_advisory_content"]["severity"].downcase,
      cve_id: hydro_payload["repository_advisory_content"]["cve_id"],
      cwe_ids: hydro_payload["repository_advisory_content"]["cwe_ids"],
      cvss_v3: hydro_payload["repository_advisory_content"]["cvss_v3"],
      cvss_v4: hydro_payload["repository_advisory_content"]["cvss_v4"],
    }.with_indifferent_access
    assert_enqueued_with(
      job: ProcessRepositoryAdvisoryCurationRequestJob,
      args: [
        repo_advisory_curation_data_hash: expected_repository_advisory_curation_data_hash,
      ],
    ) do
      AdvisoryDB.primary_hydro_executor.run_processor_loop
    end
  end

  # TESTS FOR MalwareAdvisories message type

  test "enqueues a ProcessMalwareAdvisoriesJob for a MalwareAdvisories message" do
    hydro_payload = {
      malware_advisories: [
        {
          affected_products: [
            {
              package_ecosystem: "npm",
              package_name: "qjwt",
              vulnerable_version_range: "< 0",
              first_patched_version: "",
              affected_functions: [],
              affected_functions_json: "",
            },
          ],
        },
        {
          affected_products: [
            {
              package_ecosystem: "npm",
              package_name: "uitk-react-rating",
              vulnerable_version_range: "< 0",
              first_patched_version: "",
              affected_functions: [],
              affected_functions_json: "",
            },
          ],
        },
        {
          affected_products: [
            {
              package_ecosystem: "npm",
              package_name: "qjwtsss",
              vulnerable_version_range: "< 0",
              first_patched_version: "",
              affected_functions: [],
              affected_functions_json: "",
            },
          ],
        },
      ],
    }
    ::AdvisoryDB.hydro_publisher.publish(
      hydro_payload,
      schema: "advisory_db.v0.MalwareAdvisories", topic_format_options: { format_version: Hydro::Topic::FormatVersion::V1 },
    )

    assert_enqueued_with(
      job: ProcessMalwareAdvisoriesJob,
      args: [
        hydro_payload,
      ],
    ) do
      AdvisoryDB.primary_hydro_executor.run_processor_loop
    end
  end

  # TESTS for AdvisoryAlertingEvent message type
  test "enqueues a ProcessAdvisoryAlertingEventJob after receiving an AdvisoryAlertingEvent message" do
    ghsa_id = generate(:ghsa_id)
    hydro_payload = {
      ghsa_id: ghsa_id,
      alerting_event_id: 1,
      processed_at: 5.minutes.ago,
      finished_at: Time.zone.now,
      alert_count: 1,
      notification_count: 1,
    }

    AdvisoryDB.hydro_publisher.publish(hydro_payload, schema: "advisory_db.v0.AdvisoryAlertingEvent", topic_format_options: { format_version: Hydro::Topic::FormatVersion::V1 })
    assert_enqueued_with(
      job: ProcessAdvisoryAlertingEventJob,
      args: [
        {
          ghsa_id: ghsa_id,
          alerting_event_id: 1,
          processed_at: Google::Protobuf::Timestamp.from_time(hydro_payload[:processed_at]).to_h,
          finished_at: Google::Protobuf::Timestamp.from_time(hydro_payload[:finished_at]).to_h,
          alert_count: 1,
          notification_count: 1,
        },
      ],
    ) do
      AdvisoryDB.primary_hydro_executor.run_processor_loop
    end
  end
end
