# frozen_string_literal: true

require "rails_helper"

RSpec.describe GitHub::RESTClient::Pagination do
  let(:client) { GitHub::RESTClient.new }
  let(:check_runs_url) { repo_url + "/commits/commit/check-runs" }
  let(:json_header) { { "Content-Type" => "application/json" } }
  let(:empty_check_runs_data) { fixture("github_responses/check_runs_empty.json") }

  let(:github_url) { Dependabot::Application.target_github_internal_api_endpoint }
  let(:repo_url) { "#{github_url}repositories/88632334" }

  before do
    # check run calls. the first page returns empty results, with real data returned on page 2
    stub_request(:get, check_runs_url + "?per_page=100").
      to_return(status: 200, body: empty_check_runs_data,
                headers: json_header.merge(link: paged_url_rel_links(check_runs_url, 1, 5)))

    (2..5).each do |i|
      stub_request(:get, check_runs_url + "?page=#{i}").
        to_return(status: 200, body: empty_check_runs_data,
                  headers: json_header.merge(link: paged_url_rel_links(check_runs_url, i, 5)))
    end

    stub_request(:get, check_runs_url + "?page=#5").
      to_return(status: 200, body: empty_check_runs_data, headers: json_header)
  end

  describe "#paginate" do
    it "returns a custom enumerator when enabled" do
      result = client.check_runs_for_ref(88632334, "commit", { enumerator: true })
      expect(result).to be_a(GitHub::RESTClient::Pagination::Pager)

      # validate that the enumerator only requests the first page by default
      expect(WebMock).not_to have_requested(:get, repo_url + "/commits/commit/check-runs?page=2")
    end

    it "uses legacy behavior when custom page enumeration not enabled" do
      # per_page is only given to match the stubbed request urls, the argument
      # is not significant to the test results
      result = client.check_runs_for_ref(88632334, "commit", { per_page: 100 })
      expect(result).not_to be_a(GitHub::RESTClient::Pagination::Pager)

      client.auto_paginate = true
      result = client.check_runs_for_ref(88632334, "commit", { per_page: 100 })
      expect(result).not_to be_a(GitHub::RESTClient::Pagination::Pager)

      expect(WebMock).to have_requested(:get, repo_url + "/commits/commit/check-runs?page=2")
      expect(WebMock).to have_requested(:get, repo_url + "/commits/commit/check-runs?page=3")
      expect(WebMock).to have_requested(:get, repo_url + "/commits/commit/check-runs?page=4")
      expect(WebMock).to have_requested(:get, repo_url + "/commits/commit/check-runs?page=5")
    end
  end

  describe "::Pager" do
    describe "#total_pages" do
      it "gives the total number of pages for a request" do
        enumerator = client.check_runs_for_ref(88632334, "commit", { enumerator: true })
        expect(enumerator.total_pages).to eq(5)
      end
    end

    it "can be used for lazy enumeration" do
      enumerator = client.check_runs_for_ref(88632334, "commit", { enumerator: true })
      expect(enumerator.lazy.with_index.map { |_, i| i }.take(1).force).to eq([0])

      # validate that the enumerator only requested the first page
      expect(WebMock).not_to have_requested(:get, repo_url + "/commits/commit/check-runs?page=2")
    end

    it "enumerates up to a max number of API response pages" do
      enumerator = client.check_runs_for_ref(88632334, "commit", { enumerator: { max_pages: 1 } })

      expect(enumerator.map(&:to_h)).to eq([{ check_runs: [], total_count: 0 }])
      expect(WebMock).not_to have_requested(:get, repo_url + "/commits/commit/check-runs?page=2")
    end
  end
end
