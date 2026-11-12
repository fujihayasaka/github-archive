# frozen_string_literal: true

require "rails_helper"

RSpec.describe Stafftools::ResyncRepoJob, type: :job do
  include ActiveSupport::Testing::TimeHelpers

  let(:installation_id) { 25222 }
  let(:github_url) { Dependabot::Application.target_github_internal_api_endpoint }

  let(:account) do
    FactoryBot.create(
      :account, :active, :dependabot,
      installation_id: installation_id,
    )
  end

  let(:repo) do
    FactoryBot.create(:repo, account: account)
  end

  let(:job) do
    described_class.new(
      account: account,
      github_id: repo.github_id
    )
  end

  let(:json_header) do
    { "Content-Type" => "application/json" }
  end

  let(:repo_url) do
    "#{github_url}repositories/#{repo.github_id}"
  end

  let(:repo_details) do
    fixture("github_responses/repo.json")
  end

  let(:dot_github_folder_url) do
    repo_url + "/contents/.github"
  end

  let(:config_file_url) do
    dot_github_folder_url + "/dependabot.yml"
  end

  let(:alt_config_file_url) do
    dot_github_folder_url + "/dependabot.yaml"
  end

  let(:config_file_body) do
    fixture("github_responses/contents_config_file_minimal.json")
  end

  let(:install_url) do
    "#{github_url}organizations/#{account.github_id}/installation"
  end

  let(:install_details) do
    fixture("github_responses/installation.json")
  end

  let(:app_install_url) do
    "#{github_url}app/installations/#{installation_id}"
  end

  let(:install_access_token_url) do
    "#{github_url}installations/#{installation_id}/access_tokens"
  end

  let(:install_access_token) do
    erb_fixture("github_responses/installation_access_token.json")
  end

  let(:not_found_body) do
    fixture("github_responses/not_found.json")
  end

  shared_context "a healthy remote repository" do
    before do
      stub_request(:get, repo_url).to_return(status: 200, body: repo_details, headers: json_header)
      stub_request(:get, install_url).to_return(status: 200, body: install_details, headers: json_header)
      stub_request(:get, app_install_url).to_return(status: 200, body: "{}", headers: json_header)
      stub_request(:post, install_access_token_url).
        with(body: anything).
        to_return(status: 200, body: install_access_token, headers: json_header)
    end
  end

  before do
    allow(Dependabot::Application.dependabot_repository_settings_client).
      to receive(:get_repository_settings).
      and_return(OpenStruct.new(dependabot_config_file_enabled: true))

    allow(GitHubHelpers).
      to receive(:installation_access_token_for).
      and_return("token")
  end

  context "with a deactivated Repo" do
    before do
      travel_to(4.days.ago) do
        FactoryBot.create(:update_config, :deleted, repo: repo)
      end
    end

    it { expect(repo).not_to be_active }

    context "when the update config has been forgotten and can be fixed" do
      include_context "a healthy remote repository"

      before do
        stub_request(:get, config_file_url).to_return(status: 200, body: config_file_body, headers: json_header)
      end

      it "is activated" do
        expect { job.perform_now }.to change { repo.reload.active? }.from(false).to(true)
      end

      it "does not trigger an update job" do
        expect { job.perform_now }.not_to change { UpdateJob.scheduled.count }
      end
    end

    context "when the update config has been legitimately deleted" do
      include_context "a healthy remote repository"

      before do
        stub_request(:get, config_file_url).to_return(status: 404, body: not_found_body, headers: json_header)
        stub_request(:get, dot_github_folder_url).to_return(status: 404, body: not_found_body, headers: json_header)
        stub_request(:get, alt_config_file_url).to_return(status: 404, body: not_found_body, headers: json_header)
      end

      it "is not activated" do
        expect { job.perform_now }.not_to change { repo.reload.active? }.from(false)
      end
    end

    context "when the update config cannot be retrieved due to a 401" do
      include_context "a healthy remote repository"

      before do
        stub_request(:get, config_file_url).to_return(status: 401, body: "", headers: json_header)
      end

      it "is not activated" do
        expect { job.perform_now }.not_to change { repo.reload.active? }.from(false)
      end

      it "retries" do
        expect { job.perform_now }.to have_enqueued_job(described_class)
      end
    end

    context "when the update config cannot be retrieved due to a 422" do
      include_context "a healthy remote repository"

      before do
        stub_request(:get, config_file_url).to_return(status: 422, body: "", headers: json_header)
      end

      it "is not activated" do
        expect { job.perform_now }.not_to change { repo.reload.active? }.from(false)
      end

      it "retries" do
        expect { job.perform_now }.to have_enqueued_job(described_class)
      end
    end

    context "when the update config is unparsable" do
      include_context "a healthy remote repository"

      let(:config_file_body) do
        fixture("github_responses/contents_config_file.json")
      end

      before do
        stub_request(:get, config_file_url).to_return(status: 200, body: config_file_body, headers: json_header)
      end

      it "is not activated" do
        expect { job.perform_now }.not_to change { repo.reload.active? }.from(false)
      end

      it "does not retry" do
        expect { job.perform_now }.not_to have_enqueued_job(described_class)
      end
    end

    context "when the installation id has become invalid" do
      let(:github_installation) do
        fixture("github_responses/installation.json")
      end

      before do
        allow(SynchronizeAccountState).to receive(:new) { instance_double(SynchronizeAccountState, run: nil) }

        allow(GitHubHelpers).
          to receive(:installation_access_token_for).
          and_raise(GitHubHelpers::InvalidInstallationId, "token")
      end

      it "is deactivated" do
        expect { job.perform_now }.not_to change { repo.reload.active? }.from(false)
      end

      it "does not retry" do
        expect { job.perform_now }.not_to have_enqueued_job(described_class)
      end
    end

    context "when there is an unexpected error" do
      include_context "a healthy remote repository"

      before do
        stub_request(:get, config_file_url).to_return(status: 504, body: "", headers: json_header)
      end

      it "is not activated" do
        expect { job.perform_now }.not_to change { repo.reload.active? }.from(false)
      end

      it "retries" do
        expect { job.perform_now }.to have_enqueued_job(described_class)
      end
    end

    context "when the repository has an accessible config file, but has been archived" do
      let(:archived_repo_details) do
        repo_details.gsub('"archived": false', '"archived": true')
      end

      before do
        stub_request(:get, config_file_url).to_return(status: 200, body: config_file_body, headers: json_header)
        stub_request(:get, repo_url).to_return(status: 200, body: archived_repo_details, headers: json_header)
        stub_request(:get, install_url).to_return(status: 200, body: install_details, headers: json_header)
        stub_request(:get, app_install_url).to_return(status: 200, body: "{}", headers: json_header)
      end

      it "is not activated" do
        expect { job.perform_now }.not_to change { repo.reload.active? }.from(false)
      end
    end

    context "when the repository has an accessible config file, but has been transfered" do
      include_context "a healthy remote repository"

      let(:account) do
        FactoryBot.create(:account, :active, :org, installation_id: 1001)
      end

      let!(:new_account) do
        FactoryBot.create(:account, :active, :dependabot, installation_id: installation_id)
      end

      before do
        stub_request(:get, config_file_url).to_return(status: 200, body: config_file_body, headers: json_header)
      end

      it "is not activated" do
        expect { job.perform_now }.not_to change { repo.reload.active? }.from(false)
      end

      it "triggers a transfer job" do
        expect do
          job.perform_now
        end.to enqueue_job(TransferRepoAccountJob).with(repo: repo, new_account: new_account)
      end

      it "does not trigger an update job" do
        expect { job.perform_now }.not_to change { UpdateJob.scheduled.count }
      end
    end
  end

  context "with an active Repo" do
    before do
      travel_to(4.days.ago) do
        FactoryBot.create(:update_config, :active, repo: repo)
      end
    end

    it { expect(repo).to be_active }

    context "when the repo is using a config file and a file exists in GitHub with no changes" do
      include_context "a healthy remote repository"

      before do
        repo.update(config_file_path: ".github/dependabot.yml")
        time_of_day = repo.default_update_schedule_time_of_day
        hour, minute = time_of_day.split(":").map(&:to_i)
        cron_expression = "#{minute} #{hour} * * 1-5 UTC"
        repo.update_configs.first.update(
          directory: "/.",
          package_manager: "bundler",
          update_schedule: "daily",
          update_schedule_time_of_day: time_of_day,
          update_schedule_cron_expression: cron_expression
        )
        stub_request(:get, config_file_url).to_return(status: 200, body: config_file_body, headers: json_header)
      end

      it "does not trigger an update job" do
        expect { job.perform_now }.not_to change { UpdateJob.scheduled.count }
      end
    end

    context "when the repo is using a config file and a file exists in GitHub with changes" do
      include_context "a healthy remote repository"

      before do
        repo.update(config_file_path: ".github/dependabot.yml")
        repo.update_configs.first.update(update_schedule: "weekly", package_manager: "bundler", directory: "/.")

        stub_request(:get, config_file_url).to_return(status: 200, body: config_file_body, headers: json_header)
      end

      it "pulls in configuration changes from the file in github" do
        expect { job.perform_now }.
          to change { repo.reload.update_configs.first.update_schedule }.from("weekly").to("daily")
      end

      it "does not trigger an update job" do
        expect { job.perform_now }.not_to change { UpdateJob.scheduled.count }
      end
    end

    context "when the repo is using a config file, but no file exists in GitHub anymore" do
      include_context "a healthy remote repository"

      before do
        repo.update(config_file_path: ".github/dependabot.yml")

        stub_request(:get, config_file_url).to_return(status: 404, body: not_found_body, headers: json_header)
        stub_request(:get, dot_github_folder_url).to_return(status: 404, body: not_found_body, headers: json_header)
        stub_request(:get, alt_config_file_url).to_return(status: 404, body: not_found_body, headers: json_header)
      end

      it "deactivates the update config" do
        expect { job.perform_now }.to change { repo.reload.update_configs.first.active? }.from(true).to(false)
      end

      it "deactivates the repo" do
        expect { job.perform_now }.to change { repo.reload.active? }.from(true).to(false)
      end
    end

    context "when the repo is only using security updates, but a config file exists in GitHub" do
      include_context "a healthy remote repository"

      before do
        repo.update(config_file_path: nil)
        stub_request(:get, config_file_url).to_return(status: 200, body: config_file_body, headers: json_header)
      end

      it "is updated to use the configuration file" do
        expect { job.perform_now }.to change { repo.reload.using_config_file? }.from(false).to(true)
      end

      it "sets up a new config from the file" do
        expect { job.perform_now }.to change { repo.reload.update_configs.count }.from(1).to(2)
      end
    end
  end
end
