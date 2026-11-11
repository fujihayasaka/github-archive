# frozen_string_literal: true

require "rails_helper"

RSpec.describe UpdateConfigsService::V1::UpdateJobSerializer, type: :serializer do
  subject(:serialized_job) do
    described_class.new(update_job)
  end

  let(:update_job) do
    FactoryBot.create(:update_job)
  end

  describe "#status" do
    it "contains the update_job_status" do
      expect(serialized_job.to_h[:status].to_h).not_to be_empty
    end
  end

  describe "#trigger_type" do
    context "with an unexpected trigger" do
      it "is UNKNOWN" do
        expect(serialized_job.to_h[:trigger_type]).to eql("UNKNOWN")
      end
    end

    context "with a scan trigger" do
      let(:update_job) { FactoryBot.create(:update_job, trigger_type: "scan") }

      it "is SECURITY" do
        expect(serialized_job.to_h[:trigger_type]).to eql("SECURITY")
      end
    end
  end

  describe "#pull_requests" do
    context "with no pull requests" do
      it "is an empty list" do
        expect(serialized_job.to_h[:pull_requests]).to be_empty
      end
    end

    context "with a scheduled job" do
      let(:update_job) { FactoryBot.create(:update_job, trigger_type: "scan") }

      it "has one pull request" do
        pull_request = create(:pull_request, update_job_id: update_job.id, github_number: 6)
        expect(serialized_job.to_h[:pull_requests]).to eql([{ github_number: pull_request.github_number }])
      end
    end

    context "with a rebase job" do
      it "has one pull request" do
        pull_request = create(:pull_request, update_job: update_job, github_number: 7)
        pull_request.transition_to!(:updating)
        job = pull_request.create_rebase_update_jobs(manual: false).first

        expect(described_class.new(job).to_h[:pull_requests]).to eql([{ github_number: pull_request.github_number }])
      end
    end
  end
end
