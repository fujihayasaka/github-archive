# frozen_string_literal: true

require "test_helper"

class ResolveAdvisoryPRsJobTest < ActiveJob::TestCase
  test "it merges PRs" do
    VCR.use_cassette("merged_advisory_improvement_pr") do
      ResolveAdvisoryPRsJob.new.perform(ghsa_id: "GHSA-qcjw-97hh-g9q8", pr_numbers: [4], merge: true)
    end

    WebMock.assert_requested(
      :put,
      "https://api.github.com/repos/#{github_advisories_repo}/pulls/4/merge",
      times: 1,
    )
  end

  test "it closes PRs" do
    VCR.use_cassette("closed_advisory_improvement_pr") do
      ResolveAdvisoryPRsJob.new.perform(ghsa_id: "GHSA-qcjw-97hh-g9q8", pr_numbers: [4], merge: false)
    end

    WebMock.assert_requested(
      :patch,
      "https://api.github.com/repos/#{github_advisories_repo}/pulls/4",
      times: 1,
    ) do |req|
      request_json = JSON.parse(req.body)
      assert_equal "closed", request_json["state"]
    end
  end
end
