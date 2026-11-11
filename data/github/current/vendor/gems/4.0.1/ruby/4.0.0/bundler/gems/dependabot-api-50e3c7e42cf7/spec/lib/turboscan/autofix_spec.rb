# frozen_string_literal: true

require "rails_helper"

class TurboscanDependabotFixClientStub < Twirp::Client
  client_for Turboscan::Proto::SuggestedFixesService

  def initialize(path, &block)
    super(Faraday.new do |conn|
      conn.adapter :test do |stub|
        stub.post(path, &block)
      end
    end)
  end
end

RSpec.describe Turboscan::Autofix do
  let(:sarif_content) { JSON.parse(fixture("sarif/styled-components.sarif")) }
  let(:autofix_job) { create(:autofix_suggestion_job, sarif_content: sarif_content) }

  describe "#generate_dependabot_autofix" do
    let(:request_cls) { Turboscan::Proto::GenerateDependabotFixRequest }
    let(:response_cls) { Turboscan::Proto::GenerateDependabotFixResponse }
    let(:path) { "github.turboscan.SuggestedFixes/GenerateDependabotFix" }

    it "sends data to generate an autofix" do
      client = TurboscanDependabotFixClientStub.new(path) do |req|
        generate_dependabot_fix_request = request_cls.decode(req.body)
        expect(generate_dependabot_fix_request.to_h).to eq(
          request_id: autofix_job.id,
          repository_id: autofix_job.pull_request.repo.github_id,
          commit_oid: autofix_job.target_sha,
          sarif: autofix_job.sarif_content.to_json,
          file_paths: autofix_job.sarif.affected_file_paths
        )

        [200, { "Content-Type" => "application/protobuf" }, response_cls.encode(response_cls.new(success: true))]
      end

      response = described_class.new(client: client).generate_dependabot_fix(autofix_job)
      expect(response.to_h).to include(success: true)
    end

    it "handles errors returned from service" do
      client = TurboscanDependabotFixClientStub.new(path) do
        [
          500,
          { "Content-Type" => "application/json" },
          Twirp::Encoding.encode_json(Twirp::Error.internal("service failure").to_h),
        ]
      end

      expect do
        described_class.new(client: client).generate_dependabot_fix(autofix_job)
      end.to raise_error(Turboscan::Autofix::Error, "internal - service failure")
    end
  end
end
