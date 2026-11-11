# frozen_string_literal: true

require "rails_helper"

RSpec.describe UpdateGraph::OnboardRepositoryJob do
  include ActiveJob::TestHelper

  let(:fixture_name) { "update_graph" }

  let(:hydro_payload) do
    hydro_fixture(
      name: fixture_name,
      schema: "dependency_graph.v0.UpdateGraphEvent",
    )
  end

  let(:headers) do
    if Dependabot.proxima?
      { "X-GitHub-Tenant-ID" => "123", "X-GitHub-Tenant" => "github" }
    else
      {}
    end
  end

  let(:message) do
    instance_double(
      Hydro::Consumer::ConsumerMessage,
      value: hydro_payload,
      timestamp: Time.now.utc,
      headers: headers,
    )
  end

  let(:owner) { HydroHandlers::GitHub::User.from_message(message) }
  let(:repository) { HydroHandlers::GitHub::Repository.from_message(message, owner: owner) }
  let(:graph_changes) { HydroHandlers::DependencyGraph::GraphChanges.from_message(message) }

  let(:job) do
    described_class.new(
      owner: owner,
      repository: repository,
      graph_changes: graph_changes
    )
  end

  let(:twirp_client_connection) { instance_double(Faraday::Connection) }
  let(:app_install_client) { instance_double(GitHub::Twirp::AppInstall) }

  before do
    allow(Dependabot::Application).to receive(:github_twirp_client).and_return(
      instance_double(GitHub::Twirp::Client, connection: twirp_client_connection)
    )
    allow(GitHub::Twirp::AppInstall).to receive(:new).and_return(app_install_client)
  end

  context "when the repository install succeeds" do
    before do
      allow(app_install_client).to receive(:create_repository_install).and_return(
        GitHub::Twirp::AppInstall::RepositoryInstallResponse.new(
          repository_id: repository.id,
          state: :INSTALL_STATE_CREATED,
          installation_id: 9999,
        )
      )
    end

    it "invokes UpdateGraphEventHandler#create_graph_update_job" do
      mock_handler = instance_double(UpdateGraphEventHandler)

      # Expect the owner to be recreated with the installation_id
      allow(UpdateGraphEventHandler).to receive(:new) do |args|
        expect(args[:owner].id).to eq(owner.id)
        expect(args[:owner].installation_id).to eq(9999)
        expect(args[:repository]).to eq(repository)
        expect(args[:graph_changes]).to eq(graph_changes)
        mock_handler
      end
      expect(mock_handler).to receive(:create_graph_update_job)

      job.perform_now
    end

    it "calls create_repository_install on the AppInstall client" do
      allow(UpdateGraphEventHandler).to receive(:new).and_return(
        instance_double(UpdateGraphEventHandler, create_graph_update_job: nil)
      )

      job.perform_now

      expect(app_install_client).to have_received(:create_repository_install).with(
        repository_id: repository.id
      )
    end

    it "logs the install request" do
      allow(UpdateGraphEventHandler).to receive(:new).and_return(
        instance_double(UpdateGraphEventHandler, create_graph_update_job: nil)
      )
      expect(Dependabot::Logger).to receive(:info).with(
        hash_including(
          msg: "Repository install requested",
          "gh.repo.id": repository.id,
          state: :INSTALL_STATE_CREATED,
          "gh.installation.id": 9999
        )
      )

      job.perform_now
    end
  end

  context "when the repository install succeeds but installation_id is zero" do
    before do
      allow(app_install_client).to receive(:create_repository_install).and_return(
        GitHub::Twirp::AppInstall::RepositoryInstallResponse.new(
          repository_id: repository.id,
          state: :INSTALL_STATE_CREATED,
          installation_id: 0,
        )
      )
    end

    it "raises InstallFailed error" do
      expect { job.perform_now }.to raise_error(
        described_class::InstallFailed,
        /installation_id is blank or zero/
      )
    end
  end

  context "when the repository install succeeds but installation_id is blank" do
    before do
      allow(app_install_client).to receive(:create_repository_install).and_return(
        GitHub::Twirp::AppInstall::RepositoryInstallResponse.new(
          repository_id: repository.id,
          state: :INSTALL_STATE_CREATED,
          installation_id: nil,
        )
      )
    end

    it "raises InstallFailed error" do
      expect { job.perform_now }.to raise_error(
        described_class::InstallFailed,
        /installation_id is blank or zero/
      )
    end
  end

  context "when the repository install already exists" do
    before do
      allow(app_install_client).to receive(:create_repository_install).and_return(
        GitHub::Twirp::AppInstall::RepositoryInstallResponse.new(
          repository_id: repository.id,
          state: :INSTALL_STATE_EXISTS,
          installation_id: 9999,
        )
      )
    end

    it "invokes UpdateGraphEventHandler#create_graph_update_job" do
      mock_handler = instance_double(UpdateGraphEventHandler)

      # Expect the owner to be recreated with the installation_id
      allow(UpdateGraphEventHandler).to receive(:new) do |args|
        expect(args[:owner].id).to eq(owner.id)
        expect(args[:owner].installation_id).to eq(9999)
        expect(args[:repository]).to eq(repository)
        expect(args[:graph_changes]).to eq(graph_changes)
        mock_handler
      end
      expect(mock_handler).to receive(:create_graph_update_job)

      job.perform_now
    end
  end

  context "when the repository install state is invalid" do
    before do
      allow(app_install_client).to receive(:create_repository_install).and_return(
        GitHub::Twirp::AppInstall::RepositoryInstallResponse.new(
          repository_id: repository.id,
          state: :INSTALL_STATE_INVALID,
        )
      )
    end

    it "raises InstallFailed error" do
      expect { job.perform_now }.to raise_error(
        described_class::InstallFailed,
        "Repository install failed with state: INSTALL_STATE_INVALID"
      )
    end
  end

  context "when the repository install is refused (deleted)" do
    before do
      allow(app_install_client).to receive(:create_repository_install).and_return(
        GitHub::Twirp::AppInstall::RepositoryInstallResponse.new(
          repository_id: repository.id,
          state: :INSTALL_STATE_REFUSED_DELETED,
        )
      )
    end

    it "does not invoke UpdateGraphEventHandler#create_graph_update_job" do
      mock_handler = instance_double(UpdateGraphEventHandler)
      allow(UpdateGraphEventHandler).to receive(:new).and_return(mock_handler)
      expect(mock_handler).not_to receive(:create_graph_update_job)

      job.perform_now
    end

    it "does not raise an error" do
      expect { job.perform_now }.not_to raise_error
    end
  end

  context "when the repository install is refused (archived)" do
    before do
      allow(app_install_client).to receive(:create_repository_install).and_return(
        GitHub::Twirp::AppInstall::RepositoryInstallResponse.new(
          repository_id: repository.id,
          state: :INSTALL_STATE_REFUSED_ARCHIVED,
        )
      )
    end

    it "does not invoke UpdateGraphEventHandler#create_graph_update_job" do
      mock_handler = instance_double(UpdateGraphEventHandler)
      allow(UpdateGraphEventHandler).to receive(:new).and_return(mock_handler)
      expect(mock_handler).not_to receive(:create_graph_update_job)

      job.perform_now
    end

    it "does not raise an error" do
      expect { job.perform_now }.not_to raise_error
    end
  end

  context "when the repository install is refused (spammy)" do
    before do
      allow(app_install_client).to receive(:create_repository_install).and_return(
        GitHub::Twirp::AppInstall::RepositoryInstallResponse.new(
          repository_id: repository.id,
          state: :INSTALL_STATE_REFUSED_SPAMMY,
        )
      )
    end

    it "does not invoke UpdateGraphEventHandler#create_graph_update_job" do
      mock_handler = instance_double(UpdateGraphEventHandler)
      allow(UpdateGraphEventHandler).to receive(:new).and_return(mock_handler)
      expect(mock_handler).not_to receive(:create_graph_update_job)

      job.perform_now
    end

    it "does not raise an error" do
      expect { job.perform_now }.not_to raise_error
    end
  end

  context "when the AppInstall client raises an error" do
    before do
      allow(app_install_client).to receive(:create_repository_install).and_raise(
        GitHub::Twirp::AppInstall::Error, "Twirp error"
      )
    end

    it "retries the job" do
      expect do
        job.perform_now
      rescue StandardError
        nil
      end.to have_enqueued_job(described_class)
    end

    it "raises the error when retries are exhausted" do
      perform_enqueued_jobs do
        expect { job.perform_now }.to raise_error(GitHub::Twirp::AppInstall::Error)
      end
    end
  end

  context "in proxima environment", :proxima do
    let(:headers) do
      { "X-GitHub-Tenant-ID" => "123", "X-GitHub-Tenant" => "github" }
    end

    before do
      allow(app_install_client).to receive(:create_repository_install).and_return(
        GitHub::Twirp::AppInstall::RepositoryInstallResponse.new(
          repository_id: repository.id,
          state: :INSTALL_STATE_CREATED,
          installation_id: 9999,
        )
      )
      allow(UpdateGraphEventHandler).to receive(:new).and_return(
        instance_double(UpdateGraphEventHandler, create_graph_update_job: nil)
      )
    end

    it "passes the tenant to the AppInstall client" do
      expect(GitHub::Twirp::AppInstall).to receive(:new) do |args|
        # verify the tenant is correct
        expect(args[:tenant].github_id).to be(123)
        expect(args[:tenant].slug).to eql("github")

        # return the client stub as expected
        app_install_client
      end

      job.perform_now
    end
  end

  context "in non-proxima environment", :cloud do
    before do
      allow(app_install_client).to receive(:create_repository_install).and_return(
        GitHub::Twirp::AppInstall::RepositoryInstallResponse.new(
          repository_id: repository.id,
          state: :INSTALL_STATE_CREATED,
          installation_id: 9999,
        )
      )
      allow(UpdateGraphEventHandler).to receive(:new).and_return(
        instance_double(UpdateGraphEventHandler, create_graph_update_job: nil)
      )
    end

    it "passes NullTenant to the AppInstall client" do
      job.perform_now

      expect(GitHub::Twirp::AppInstall).to have_received(:new).with(
        hash_including(
          tenant: an_instance_of(NullTenant)
        )
      )
    end
  end

  describe "account and repository upserts" do
    let(:headers) do
      if Dependabot.proxima?
        { "X-GitHub-Tenant-ID" => "123", "X-GitHub-Tenant" => "github" }
      else
        {}
      end
    end

    before do
      allow(app_install_client).to receive(:create_repository_install).and_return(
        GitHub::Twirp::AppInstall::RepositoryInstallResponse.new(
          repository_id: repository.id,
          state: :INSTALL_STATE_CREATED,
          installation_id: 7777,
        )
      )
    end

    context "when neither the account or repository exist" do
      it "creates an account with the correct installation id" do
        expect { job.perform_now }.to change(Account, :count).by(1)

        account = Account.find_by(github_id: owner.id)
        expect(account).to be_present
        expect(account).to be_active
        expect(account.current_installation_id).to eq(7777)
      end

      it "creates a repository" do
        expect { job.perform_now }.to change(Repo, :count).by(1)

        repo = Repo.find_by(github_id: repository.id)
        expect(repo).to be_present
        expect(repo.name).to eq("hello-world")
      end

      it "enqueues a CreateGraphUpdateJob" do
        expect { job.perform_now }.to have_enqueued_job(CreateGraphUpdateJob)
      end
    end

    context "when the account exists, but the repository does not" do
      before do
        create(:account, :active, github_id: owner.id, github_login: owner.login,
                                  account_type: "org", installation_id: 5555)
      end

      it "updates the account's installation id to match the new installation" do
        expect { job.perform_now }.not_to change(Account, :count)

        expect(Account.find_by!(github_id: owner.id).current_installation_id).to be(7777)
      end

      it "creates a repository" do
        expect { job.perform_now }.to change(Repo, :count).by(1)

        repo = Repo.find_by(github_id: repository.id)
        expect(repo).to be_present
        expect(repo.name).to eq("hello-world")
        expect(repo.account.github_id).to eq(owner.id)
      end

      it "enqueues a CreateGraphUpdateJob" do
        expect { job.perform_now }.to have_enqueued_job(CreateGraphUpdateJob)
      end
    end

    context "when both the account and the repository exist" do
      before do
        account = create(:account, :active, github_id: owner.id, github_login: owner.login,
                                            account_type: "org", installation_id: 5555)
        create(:repo, account:, github_id: repository.id, name: "hello-world")
      end

      it "updates the account's installation id to match the new installation" do
        expect { job.perform_now }.not_to change(Account, :count)

        expect(Account.find_by!(github_id: owner.id).current_installation_id).to be(7777)
      end

      it "still attempts an installation" do
        job.perform_now

        expect(app_install_client).to have_received(:create_repository_install)
      end

      it "enqueues a CreateGraphUpdateJob" do
        expect { job.perform_now }.to have_enqueued_job(CreateGraphUpdateJob)
      end
    end
  end
end
