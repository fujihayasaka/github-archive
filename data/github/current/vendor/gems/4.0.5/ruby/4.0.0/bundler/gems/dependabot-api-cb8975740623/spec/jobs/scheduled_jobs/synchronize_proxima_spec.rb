# frozen_string_literal: true

require "rails_helper"

RSpec.describe ScheduledJobs::SynchronizeProxima, type: :job do
  include ActiveJob::TestHelper

  subject(:job) { described_class.new }

  let(:json_header) { { "Content-Type" => "application/json" } }
  let(:proxima_sync_response) do
    {
      "ecosystem_versions" => [
        { "ecosystem" => "npm", "version" => "a1b2fe30ec865b2a7fafd0bb36ee64282559fe98" },
        { "ecosystem" => "gomod", "version" => "800437640d2ff4f6380ef21b90f685be7ac140e6" },
        { "ecosystem" => "bundler", "version" => "a1b2fe30ec865b2a7fafd0bb36ee64282559fe98" },
      ],
    }
  end

  before do
    allow(Dependabot::Application).to receive(:dotcom_proxima_sync_endpoint).
      and_return("https://api-internal.example.com/proxima/sync")

    stub_request(:get, "https://api-internal.example.com/proxima/sync").to_return(
      status: 200,
      body: proxima_sync_response.to_json,
      headers: json_header
    )
  end

  context "on proxima", :proxima do
    it "updates ecosystem versions" do
      job.perform_now

      expect(UpdaterVersion.find_by(ecosystem: "npm").version).to eq("a1b2fe30ec865b2a7fafd0bb36ee64282559fe98")
      expect(UpdaterVersion.find_by(ecosystem: "gomod").version).to eq("800437640d2ff4f6380ef21b90f685be7ac140e6")
      expect(UpdaterVersion.find_by(ecosystem: "bundler").version).to eq("a1b2fe30ec865b2a7fafd0bb36ee64282559fe98")
    end
  end

  context "in the cloud", :cloud do
    it "noops" do
      job.perform_now

      expect(UpdaterVersion.count).to eq(0)
    end
  end
end
