# frozen_string_literal: true

require "rails_helper"
require "chatops/controller/rspec"

RSpec.describe ChatopsController, :cloud do
  include ActiveSupport::Testing::TimeHelpers
  include GzipHelpers

  include_context "chatops controller"

  before do
    Rails.cache.clear
    allow(Dependabot::Application).
      to receive(:dependabot_repository_settings_client).
      and_return(dependabot_repository_settings_client)
  end

  let(:dependabot_repository_settings_client) do
    instance_double(
      GitHub::Twirp::DependabotRepositorySettings,
      get_repository_settings: OpenStruct.new(dependabot_self_hosted_enabled: false),
    )
  end
  let(:client) { Aws::S3::Client.new(stub_responses: true) }

  describe "logs" do
    let(:s3_logs) do
      <<~LOGS.rstrip
        updater | foo
        updater | bar
          proxy | baz
      LOGS
    end

    let!(:update_job) do
      FactoryBot.create(:update_job, id: 123, github_request_id: 111, actions_workflow_run_id: 222)
    end

    before do
      client.stub_responses(:get_object, body: gzip(s3_logs))
      allow(Aws::S3::Client).to receive(:new).and_return(client)
    end

    it "returns link to actions logs" do
      chat "dependabot logs 123", "user"
      expect(chatop_response).to eq("Access the logs directly: https://admin.github.com/stafftools/repositories/hmarr/business/actions_latest_runs?query=222")
    end

    context "with no workflow run id" do
      it "explains itself" do
        update_job.update!(actions_workflow_run_id: nil)
        chat "dependabot logs 123", "user"
        expect(chatop_error).to include("Couldn't find workflow run ID for job 123")
      end
    end

    context "with sensitive logs" do
      # Actions logs don't need special handling for sensitive content
      # since they're accessed through GitHub's Actions interface
      it "redirects to actions logs" do
        chat "dependabot logs 123", "user"
        expect(chatop_response).to eq("Access the logs directly: https://admin.github.com/stafftools/repositories/hmarr/business/actions_latest_runs?query=222")
      end
    end

    context "with a github_request_id" do
      it "redirects to actions logs" do
        chat "dependabot logs --github-request-id 111", "user"
        expect(chatop_response).to eq("Access the logs directly: https://admin.github.com/stafftools/repositories/hmarr/business/actions_latest_runs?query=222")
      end
    end

    context "with a action workflow run id" do
      let(:update_job) do
        FactoryBot.create(:update_job, :processed, :on_gh_actions, id: 123, github_request_id: 111,
                                                                   actions_workflow_run_id: 222)
      end

      before do
        allow(dependabot_repository_settings_client).to receive(:get_repository_settings).
          and_return(OpenStruct.new(dependabot_self_hosted_enabled: false))
      end

      it "returns stafftools url to download logs" do
        chat "dependabot logs 123", "user"
        expect(chatop_response).to eq("Access the logs directly: https://admin.github.com/stafftools/repositories/hmarr/business/actions_latest_runs?query=222")
      end
    end

    context "when update job is running on staging" do
      before do
        # job_sqs_stage enables staging environment for update jobs
        Flipper.enable_actor(:job_sqs_stage, update_job.update_config.repo)
      end

      it "still redirects to actions logs" do
        chat "dependabot logs 123", "user"
        expect(chatop_response).to eq("Access the logs directly: https://admin.github.com/stafftools/repositories/hmarr/business/actions_latest_runs?query=222")
      end
    end
  end
end
