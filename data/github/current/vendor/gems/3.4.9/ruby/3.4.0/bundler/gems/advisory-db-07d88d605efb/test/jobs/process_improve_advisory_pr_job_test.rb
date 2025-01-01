# frozen_string_literal: true

require "test_helper"
require "webmock"

class ProcessImproveAdvisoryPRJobTest < ActiveJob::TestCase
  include WebMock::API
  WebMock.enable!

  test "makes or updates a feed entry for the improve advisory PR" do
    create(:advisory_review, :accepted, ghsa_id: "GHSA-hfq3-rpjj-f4w2")

    assert_difference -> { FeedEntry.count }, 1 do
      VCR.use_cassette("improve_advisory_pr_success") do
        ProcessImproveAdvisoryPRJob.new.perform(pr_number: 3, head_sha: "be72b0cbcb8db0bdf0bb899f4d91dac938d52de0", actor_login: "octocat", actor_id: 12345)
      end
    end

    assert_no_difference -> { FeedEntry.count } do
      VCR.use_cassette("improve_advisory_pr_success") do
        ProcessImproveAdvisoryPRJob.new.perform(pr_number: 3, head_sha: "be72b0cbcb8db0bdf0bb899f4d91dac938d52de0", actor_login: "octocat", actor_id: 12345)
      end
    end
  end

  test "it stores the PR number on the feed entry" do
    create(:advisory_review, :accepted, ghsa_id: "GHSA-hfq3-rpjj-f4w2")

    VCR.use_cassette("improve_advisory_pr_success") do
      ProcessImproveAdvisoryPRJob.new.perform(pr_number: 3, head_sha: "be72b0cbcb8db0bdf0bb899f4d91dac938d52de0", actor_login: "octocat", actor_id: 12345)
    end
    assert_equal 3, FeedEntry.last.raw_payload["pr_number"]
  end

  test "reports failure status to the PR if importing would overwrite other open PR number" do
    create(:advisory_review, :accepted, ghsa_id: "GHSA-9686-c4g7-g6mw")
    create(:advisory_improvement_feed_entry, identifier: "advisory_improvement/12345/GHSA-9686-c4g7-g6mw", pr_number: 1)

    VCR.use_cassette("improve_advisory_too_many_prs") do
      ProcessImproveAdvisoryPRJob.new.perform(pr_number: 2, head_sha: "4f331541c7528dd19f8cae7a0ca3b0f00bd09f4e", actor_login: "octocat", actor_id: 12345)
    end
    assert_equal 1, FeedEntry.last.raw_payload["pr_number"]

    WebMock.assert_requested(
      :patch,
      Regexp.new("https://api.github.com/repos/#{github_advisories_repo}/check-runs/.+"),
      times: 1,
    ) do |req|
      request_json = JSON.parse(req.body)
      assert_equal "completed", request_json["status"]
      assert_equal "failure", request_json["conclusion"]
      assert_equal ProcessImproveAdvisoryPRJob::ERROR_TOO_MANY_PRS, request_json["output"]["summary"]
    end
  end

  test "reopens advisory review for the published advisory" do
    advisory_review = create(:advisory_review, :accepted, ghsa_id: "GHSA-hfq3-rpjj-f4w2")

    assert_equal "accepted", advisory_review.state
    perform_enqueued_jobs(only: [ResolveFeedEntryJob]) do
      VCR.use_cassette("improve_advisory_pr_success") do
        ProcessImproveAdvisoryPRJob.new.perform(pr_number: 3, head_sha: "be72b0cbcb8db0bdf0bb899f4d91dac938d52de0", actor_login: "octocat", actor_id: 12345)
      end
    end

    advisory_review.reload
    assert_equal "in_review", advisory_review.state
  end

  test "reports successful status to the PR" do
    create(:advisory_review, :accepted, ghsa_id: "GHSA-hfq3-rpjj-f4w2")

    VCR.use_cassette("improve_advisory_pr_success") do
      ProcessImproveAdvisoryPRJob.new.perform(pr_number: 3, head_sha: "be72b0cbcb8db0bdf0bb899f4d91dac938d52de0", actor_login: "octocat", actor_id: 12345)
    end

    WebMock.assert_requested(
      :post,
      Regexp.new("https://api.github.com/repos/#{github_advisories_repo}/check-runs"),
      times: 1,
    ) do |req|
      request_json = JSON.parse(req.body)
      assert_equal "in_progress", request_json["status"]
      assert_nil request_json["conclusion"]
    end

    WebMock.assert_requested(
      :patch,
      Regexp.new("https://api.github.com/repos/#{github_advisories_repo}/check-runs/.+"),
      times: 1,
    ) do |req|
      request_json = JSON.parse(req.body)
      assert_equal "completed", request_json["status"]
      assert_equal "success", request_json["conclusion"]
    end
  end

  test "handles rerequested check runs" do
    create(:advisory_review, :accepted, ghsa_id: "GHSA-hfq3-rpjj-f4w2")

    stub_request(:post, "https://api.github.com/repos/#{github_advisories_repo}/check-runs/56789")
    stub_request(:post, "https://api.github.com/app/installations/123456/access_tokens")
      .to_return(body: { token: 123, expires_at: 1.hour.from_now }.to_json, headers: { content_type: "application/json" })

    stub_request(:get, "https://api.github.com/repos/octocat/advisories/check-runs/56789")
      .to_return(body: { id: 56789,
                         name: "Processing advisory improvement",
                         started_at: Time.zone.parse("2024-05-30 09:47:38 UTC"),
                         completed_at: Time.zone.parse("2024-05-30 09:47:38 UTC"),
                         pull_requests: [{
                           number: 3,
                           head: { sha: "be72b0cbcb8db0bdf0bb899f4d91dac938d52de0",
                                   repo: {
                                     url: "https://api.github.com/repos/github/advisory-database",
                                     name: "advisory-database",
                                   } },
                         }] }.to_json, headers: { content_type: "application/json" })

    stub_request(:get, "https://api.github.com/repos/octocat/advisories/pulls/3/files")
      .to_return(body: [{
        sha: "d814cebd1012dc073a173db3208e9b9d73b756ef",
        filename: "advisories/github-reviewed/2022/02/GHSA-hfq3-rpjj-f4w2/GHSA-hfq3-rpjj-f4w2.json",
        status: "modified",
        contents_url: "https://api.github.com/repos/octocat/advisories/contents/advisories/github-reviewed/2022/02/GHSA-hfq3-rpjj-f4w2/GHSA-hfq3-rpjj-f4w2.json?ref=be72b0cbcb8db0bdf0bb899f4d91dac938d52de0",
      }].to_json,
        headers: { content_type: "application/json" })

    stub_request(:get, "https://api.github.com/repos/octocat/advisories/contents/advisories/github-reviewed/2022/02/GHSA-hfq3-rpjj-f4w2/GHSA-hfq3-rpjj-f4w2.json?ref=be72b0cbcb8db0bdf0bb899f4d91dac938d52de0")
      .to_return(body: {
        content: "ewogICJzY2hlbWFfdmVyc2lvbiI6ICIxLjEuMCIsCiAgImlkIjogIkdIU0Et\naGZxMy1ycGpqLWY0dzIiLAogICJtb2RpZmllZCI6ICIyMDIyLTAyLTAxVDIy\nOjUzOjUyWiIsCiAgInB1Ymxpc2hlZCI6ICIyMDIyLTAyLTAxVDIyOjUzOjUy\nWiIsCiAgImFsaWFzZXMiOiBbCgogIF0sCiAgInN1bW1hcnkiOiAiRXNzZSBl\nYSBvZmZpY2lhIHNpdCBpcHN1bSBpbmNpZGlkdW50IGxhYm9yaXMgc3VudCBj\nb25zZWN0ZXR1ciBlYS4iLAogICJkZXRhaWxzIjogIlN1bnQgaW4gcGFyaWF0\ndXIgY29tbW9kbyBldSB2b2x1cHRhdGUgZXNzZSB1dCBjb25zZXF1YXQgc2l0\nIGFsaXF1YS4gSW4gZG9sb3Igc2ludCBleCBjdXBpZGF0YXQuIEV4Y2VwdGV1\nciBub3N0cnVkIHJlcHJlaGVuZGVyaXQgZGVzZXJ1bnQgcGFyaWF0dXIgZXhl\ncmNpdGF0aW9uIGV0IGV4ZXJjaXRhdGlvbiBMb3JlbSBtaW5pbSBsYWJvcnVt\nIGxhYm9yZS4gVXQgbW9sbGl0IGV4ZXJjaXRhdGlvbiBpcHN1bSBldCBpZCBh\nbWV0LiBDb25zZWN0ZXR1ciB1dCBpcnVyZSBpZCBjb25zZXF1YXQgaXBzdW0g\nYWxpcXVhIGVsaXQgc2l0IGVzc2UgdWxsYW1jby4iLAogICJzZXZlcml0eSI6\nIFsKCiAgXSwKICAiYWZmZWN0ZWQiOiBbCiAgICB7CiAgICAgICJwYWNrYWdl\nIjogewogICAgICAgICJlY29zeXN0ZW0iOiAiUnVieUdlbXMiLAogICAgICAg\nICJuYW1lIjogInJpY2siCiAgICAgIH0sCiAgICAgICJyYW5nZXMiOiBbCiAg\nICAgICAgewogICAgICAgICAgInR5cGUiOiAiRUNPU1lTVEVNIiwKICAgICAg\nICAgICJldmVudHMiOiBbCiAgICAgICAgICAgIHsKICAgICAgICAgICAgICAi\naW50cm9kdWNlZCI6ICI0LjUuNiIKICAgICAgICAgICAgfSwKICAgICAgICAg\nICAgewogICAgICAgICAgICAgICJmaXhlZCI6ICI1LjAuMSIKICAgICAgICAg\nICAgfQogICAgICAgICAgXQogICAgICAgIH0KICAgICAgXQogICAgfQogIF0s\nCiAgInJlZmVyZW5jZXMiOiBbCiAgICB7CiAgICAgICJ0eXBlIjogIldFQiIs\nCiAgICAgICJ1cmwiOiAiaHR0cHM6Ly9naXRodWIuY29tL2NocmlzYmxvb203\nL2Fkdmlzb3JpZXMtdGVzdC8iCiAgICB9CiAgXSwKICAiZGF0YWJhc2Vfc3Bl\nY2lmaWMiOiB7CiAgICAiY3dlX2lkcyI6IFsKCiAgICBdLAogICAgInNldmVy\naXR5IjogIk1PREVSQVRFIiwKICAgICJnaXRodWJfcmV2aWV3ZWQiOiB0cnVl\nCiAgfQp9Cg==\n",
      }.to_json,
        headers: { content_type: "application/json" })

    stub_request(:patch, "https://api.github.com/repos/octocat/advisories/check-runs/56789")

    ProcessImproveAdvisoryPRJob.new.perform(pr_number: 3, head_sha: "be72b0cbcb8db0bdf0bb899f4d91dac938d52de0", actor_login: "octocat", actor_id: 12345, check_run_id: 56789)

    WebMock.assert_requested(
      :get,
      Regexp.new("https://api.github.com/repos/#{github_advisories_repo}/check-runs/56789"),
      times: 1,
    )

    WebMock.assert_requested(
      :patch,
      Regexp.new("https://api.github.com/repos/#{github_advisories_repo}/check-runs/.+"),
      times: 1,
    ) do |req|
      request_json = JSON.parse(req.body)
      assert_equal "completed", request_json["status"]
      assert_equal "success", request_json["conclusion"]
    end
  end

  test "reports failure status to the PR when no advisory file" do
    assert_no_difference -> { FeedEntry.count } do
      VCR.use_cassette("improve_advisory_pr_no_file") do
        ProcessImproveAdvisoryPRJob.new.perform(pr_number: 1, head_sha: "9b96bc47acd5b57a7d6a79b0013ea89214369b9c", actor_login: "octocat", actor_id: 12345)
      end
    end

    WebMock.assert_requested(
      :patch,
      Regexp.new("https://api.github.com/repos/#{github_advisories_repo}/check-runs/.+"),
      times: 1,
    ) do |req|
      request_json = JSON.parse(req.body)
      assert_equal "completed", request_json["status"]
      assert_equal "failure", request_json["conclusion"]
      assert_equal ProcessImproveAdvisoryPRJob::ERROR_NO_FILES, request_json["output"]["summary"]
    end
  end

  test "reports failure status to the PR when too many advisory files" do
    assert_no_difference -> { FeedEntry.count } do
      VCR.use_cassette("improve_advisory_pr_too_many_files") do
        ProcessImproveAdvisoryPRJob.new.perform(pr_number: 1, head_sha: "6b4c0a3114e9bde17432857cd30696ecad0c5c2b", actor_login: "octocat", actor_id: 12345)
      end
    end

    WebMock.assert_requested(
      :patch,
      Regexp.new("https://api.github.com/repos/#{github_advisories_repo}/check-runs/.+"),
      times: 1,
    ) do |req|
      request_json = JSON.parse(req.body)
      assert_equal "completed", request_json["status"]
      assert_equal "failure", request_json["conclusion"]
      assert_equal ProcessImproveAdvisoryPRJob::ERROR_TOO_MANY_FILES, request_json["output"]["summary"]
    end
  end

  test "reports failure status to the PR when advisory doesn't exist for file" do
    assert_no_difference -> { FeedEntry.count } do
      VCR.use_cassette("improve_advisory_pr_no_advisory") do
        ProcessImproveAdvisoryPRJob.new.perform(pr_number: 1, head_sha: "6b4c0a3114e9bde17432857cd30696ecad0c5c2b", actor_login: "octocat", actor_id: 12345)
      end
    end

    WebMock.assert_requested(
      :patch,
      Regexp.new("https://api.github.com/repos/#{github_advisories_repo}/check-runs/.+"),
      times: 1,
    ) do |req|
      request_json = JSON.parse(req.body)
      assert_equal "completed", request_json["status"]
      assert_equal "failure", request_json["conclusion"]
      assert_equal ProcessImproveAdvisoryPRJob::ERROR_UNABLE_TO_MATCH, request_json["output"]["summary"]
    end
  end

  test "reports failure status to the PR when advisory file isn't JSON" do
    create(:advisory_review, :accepted, ghsa_id: "GHSA-qcjw-97hh-g9q8")

    assert_no_difference -> { FeedEntry.count } do
      VCR.use_cassette("improve_advisory_pr_bad_json") do
        ProcessImproveAdvisoryPRJob.new.perform(pr_number: 1, head_sha: "9c296bff41e44da525f78d2da17742023519f562", actor_login: "octocat", actor_id: 12345)
      end
    end

    WebMock.assert_requested(
      :patch,
      Regexp.new("https://api.github.com/repos/#{github_advisories_repo}/check-runs/.+"),
      times: 1,
    ) do |req|
      request_json = JSON.parse(req.body)
      assert_equal "completed", request_json["status"]
      assert_equal "failure", request_json["conclusion"]
      assert_equal ProcessImproveAdvisoryPRJob::ERROR_BAD_JSON, request_json["output"]["summary"]
    end
  end

  test "reports failure status to the PR when advisory file isn't OSV" do
    create(:advisory_review, :accepted, ghsa_id: "GHSA-qcjw-97hh-g9q8")

    assert_no_difference -> { FeedEntry.count } do
      VCR.use_cassette("improve_advisory_pr_bad_osv") do
        ProcessImproveAdvisoryPRJob.new.perform(pr_number: 10, head_sha: "8050c1cf89208eafcae81f61368b600704f32fd1", actor_login: "octocat", actor_id: 12345)
      end
    end

    WebMock.assert_requested(
      :patch,
      Regexp.new("https://api.github.com/repos/#{github_advisories_repo}/check-runs/.+"),
      times: 1,
    ) do |req|
      request_json = JSON.parse(req.body)
      assert_equal "completed", request_json["status"]
      assert_equal "failure", request_json["conclusion"]
      assert request_json["output"]["summary"].include?("valid OSV")
    end
  end

  test "reports failure status to the PR when advisory in file doesn't match filename" do
    create(:advisory_review, :accepted, ghsa_id: "GHSA-qcjw-97hh-g9q8")

    assert_no_difference -> { FeedEntry.count } do
      VCR.use_cassette("improve_advisory_pr_mismatched_ghsa") do
        ProcessImproveAdvisoryPRJob.new.perform(pr_number: 10, head_sha: "0f820bcbcfeaa85cb9fe866d05728197f8b04295", actor_login: "octocat", actor_id: 12345)
      end
    end

    WebMock.assert_requested(
      :patch,
      Regexp.new("https://api.github.com/repos/#{github_advisories_repo}/check-runs/.+"),
      times: 1,
    ) do |req|
      request_json = JSON.parse(req.body)
      assert_equal "completed", request_json["status"]
      assert_equal "failure", request_json["conclusion"]
      assert_equal ProcessImproveAdvisoryPRJob::ERROR_GHSAS_DONT_MATCH, request_json["output"]["summary"]
    end
  end

  test "retries on API errors" do
    assert_enqueued_with(
      job: ProcessImproveAdvisoryPRJob,
      args: [
        pr_number: 3,
        head_sha: "be72b0cbcb8db0bdf0bb899f4d91dac938d52de0",
        actor_login: "octocat",
        actor_id: 12345,
      ],
    ) do
      VCR.use_cassette("improve_advisory_pr_success") do
        AdvisoryDB.github.stubs(:create_check_run).raises(Octokit::ServerError)
        ProcessImproveAdvisoryPRJob.perform_now(pr_number: 3, head_sha: "be72b0cbcb8db0bdf0bb899f4d91dac938d52de0", actor_login: "octocat", actor_id: 12345)
      end
    end
  end

  test "reports failure if no significant changes are detected" do
    create(:advisory_review, :accepted,
      ghsa_id: "GHSA-633g-f9jj-2j2g",
      cve_id: "CVE-2022-0002",
      advisory_payload: build(:advisory_payload,
        summary: "Magnam quo porro quisquam consequatur animi optio id ad sapiente omnis qui ut dolores amet",
        description: "Laborum eveniet molestiae. Non porro minima. Earum voluptates error.\n\nDolorem non et. Qui rerum enim. Expedita quas quisquam.\n\nAsperiores laudantium doloribus. Fuga sit praesentium. Iste eligendi fuga.\n\nDolor dignissimos eos. Aut reiciendis voluptatum. In aut quis.\n\nVel laudantium quo. Officiis quisquam natus. Eos error asperiores.\n\nNam quos ipsam. Rerum velit eligendi. Est modi recusandae.\n\nEnim ut temporibus. Temporibus eveniet fugiat. Sed qui aut.\n\nIusto fugiat illo. Sapiente minus error. Dignissimos maxime qui.\n\nDebitis harum impedit. Quis ea quo. Veniam ut ea.\n\nId suscipit velit. Dolorem quam sint. Exercitationem optio placeat.",
        references: ["http://morissette.org/jami"],
        source_code_location: nil,
        cvss_v3: nil,
        cwe_ids: [],
        severity: "high",
        vulnerabilities: {
          0 => build(:vulnerability_payload,
            ecosystem: "pip",
            package_name: "blue-angel",
            vulnerable_version_range: ">= 0.3.7, < 0.3.9",
            first_patched_version: nil),
        }))

    VCR.use_cassette("improve_advisory_pr_no_significant_changes") do
      # PR where only change is to modified date, which we ignore
      ProcessImproveAdvisoryPRJob.new.perform(pr_number: 4, head_sha: "8804a37296c434925a0b7a6221d2178e08da82b3", actor_login: "octocat", actor_id: 12345)
    end

    WebMock.assert_requested(
      :patch,
      Regexp.new("https://api.github.com/repos/#{github_advisories_repo}/check-runs/.+"),
      times: 1,
    ) do |req|
      request_json = JSON.parse(req.body)
      assert_equal "completed", request_json["status"]
      assert_equal "failure", request_json["conclusion"]
      assert_equal ProcessImproveAdvisoryPRJob::ERROR_NO_SIGNIFICANT_CHANGES, request_json["output"]["summary"]
    end
  end

  test "does not report insignificant changes if all fields removed" do
    create(:advisory_review, :accepted,
      ghsa_id: "GHSA-633g-f9jj-2j2g",
      cve_id: "CVE-2022-0002",
      advisory_payload: build(:advisory_payload,
        summary: "Magnam quo porro quisquam consequatur animi optio id ad sapiente omnis qui ut dolores amet",
        description: "Laborum eveniet molestiae. Non porro minima. Earum voluptates error.\n\nDolorem non et. Qui rerum enim. Expedita quas quisquam.\n\nAsperiores laudantium doloribus. Fuga sit praesentium. Iste eligendi fuga.\n\nDolor dignissimos eos. Aut reiciendis voluptatum. In aut quis.\n\nVel laudantium quo. Officiis quisquam natus. Eos error asperiores.\n\nNam quos ipsam. Rerum velit eligendi. Est modi recusandae.\n\nEnim ut temporibus. Temporibus eveniet fugiat. Sed qui aut.\n\nIusto fugiat illo. Sapiente minus error. Dignissimos maxime qui.\n\nDebitis harum impedit. Quis ea quo. Veniam ut ea.\n\nId suscipit velit. Dolorem quam sint. Exercitationem optio placeat.",
        references: ["http://morissette.org/jami"],
        source_code_location: nil,
        cvss_v3: nil,
        cwe_ids: [],
        severity: "high",
        vulnerabilities: {
          0 => build(:vulnerability_payload,
            ecosystem: "pip",
            package_name: "blue-angel",
            vulnerable_version_range: ">= 0.3.7, < 0.3.9",
            first_patched_version: nil),
        }))

    VCR.use_cassette("improve_advisory_pr_no_significant_changes_2") do
      # PR where everything other than required fields have been removed
      ProcessImproveAdvisoryPRJob.new.perform(pr_number: 6, head_sha: "d0331ead50315f2e26c8c6f5fbe8e5045aaebd22", actor_login: "octocat", actor_id: 12345)
    end

    WebMock.assert_requested(
      :patch,
      Regexp.new("https://api.github.com/repos/#{github_advisories_repo}/check-runs/.+"),
      times: 1,
    ) do |req|
      request_json = JSON.parse(req.body)
      assert_equal "completed", request_json["status"]
      assert_equal "success", request_json["conclusion"]
    end
  end
end
