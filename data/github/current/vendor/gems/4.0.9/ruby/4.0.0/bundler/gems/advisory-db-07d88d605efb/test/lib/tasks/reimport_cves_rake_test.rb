# frozen_string_literal: true

require "test_helper"
require "rake"
require "webmock"

class ReimportCVEsRakeTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper
  include WebMock::API
  WebMock.enable!

  setup do
    AdvisoryDB::Application.load_tasks if Rake::Task.tasks.empty?
    Rake::Task["advisory_db:reimport_cves"].reenable
  end

  def setup_cve_request(cve_id = "CVE-2020-1234")
    stub_request(:get, "https://services.nvd.nist.gov/rest/json/cves/2.0?cveId=#{cve_id}&startIndex=0")
      .to_return(body: {
        startIndex: 0,
        resultsPerPage: 10,
        totalResults: 1,
        vulnerabilities: [{
          cve: { id: cve_id,
                 descriptions: [
                   {
                     lang: "en",
                     value: "An elevation of privilege vulnerability exists when Windows Error Reporting improperly handles objects in memory.To exploit this vulnerability, an attacker would first have to gain execution on the victim system, aka 'Windows Error Reporting Elevation of Privilege Vulnerability'.",
                   },
                 ] },
        }],
      }.to_json,
        headers: { content_type: "application/json" })
  end

  test "rake advisory_db:reimport_cves enqueues the ImportJob with one CVE ID" do
    create(:advisory, cve_id: "CVE-2020-1234")
    setup_cve_request
    ImportJob.expects(:perform_now).with(NVDImporter.source, cve_id: "CVE-2020-1234", report_to_slack: false)
    Rake::Task["advisory_db:reimport_cves"].invoke
  end

  test "rake advisory_db:reimport_cves enqueues the ImportJob with more than one CVE ID" do
    create(:advisory, cve_id: "CVE-2020-1234")
    create(:advisory, cve_id: "CVE-2020-1235")
    setup_cve_request
    setup_cve_request("CVE-2020-1235")

    assert_enqueued_jobs(2) do
      Rake::Task["advisory_db:reimport_cves"].invoke(true)
    end
  end

  test "rake advisory_db:reimport_cves enqueues the ImportJob with a CVE ID passed in" do
    create(:advisory, cve_id: "CVE-2020-1234")
    setup_cve_request
    ImportJob.expects(:perform_now).with(NVDImporter.source, cve_id: "CVE-2020-1234", report_to_slack: false)
    Rake::Task["advisory_db:reimport_cves"].invoke(false, ["CVE-2020-1234"])
  end

  test "rake advisory_db:reimport_cves does not enqueue a job for an Advisory with no CVE ID" do
    create(:advisory, cve_id: nil)

    assert_no_enqueued_jobs do
      Rake::Task["advisory_db:reimport_cves"].execute
    end
  end

  test "rake advisory_db:reimport_cves does not enqueue a job for an Advisory with no summary" do
    advisory = create(:advisory, cve_id: "CVE-2020-1234")
    advisory.update_attribute("summary", nil)

    assert_no_enqueued_jobs do
      Rake::Task["advisory_db:reimport_cves"].execute
    end
  end
end
