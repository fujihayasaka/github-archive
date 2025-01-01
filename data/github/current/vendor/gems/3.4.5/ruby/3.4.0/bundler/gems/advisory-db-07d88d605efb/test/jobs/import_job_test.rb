# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

class ImportJobTest < ActiveJob::TestCase
  include JobTestHelper

  test "job retries when NVDImporter::NVDUnavailableError is raised" do
    assert_retry_on_error(NVDImporter::NVDUnavailableError, ImportJob, args: [NVDImporter.source], kwargs: { cve_id: "CVE-2020-1234" })
  end

  test "job retries when read timeout occurs" do
    assert_retry_on_error(Net::ReadTimeout, ImportJob, args: [NVDImporter.source], kwargs: { cve_id: "CVE-2020-1234" })
  end
end
