# frozen_string_literal: true

require "rails_helper"

RSpec.describe UpdateDefaultLabelsJob, type: :job do
  include ActiveJob::TestHelper

  subject(:job) { described_class.new(repo: repo) }

  let!(:account) { FactoryBot.create(:account, :dependabot, :active) }
  let(:repo) { FactoryBot.create(:repo, :bump_test) }
  let(:json_header) { { "Content-Type" => "application/json" } }
  let(:github_url) { Dependabot::Application.target_github_internal_api_endpoint }
  let(:repo_labels_url) do
    github_url + "repositories/88632334/labels?per_page=100"
  end

  before do
    allow(GitHubHelpers).to receive(:installation_access_token_for)
    stub_request(:get, repo_labels_url).
      to_return(status: 200, body: repo_labels, headers: json_header)
  end

  context "with a single update config" do
    let(:repo_labels) do
      fixture("github_responses/issue_labels_custom.json")
    end

    let!(:update_config) do
      FactoryBot.create(
        :update_config, :active,
        repo: repo,
        default_labels: ["outdated"],
      )
    end

    it "updates the default label to 'dependencies'" do
      expect { job.perform_now }.
        to change { update_config.reload.default_labels }.
        from(["outdated"]).to(["dependencies"])
    end

    context "when passed the available labels" do
      subject(:job) do
        described_class.new(repo: repo, available_labels: ["Dependency"])
      end

      it "uses them and does not hit GitHub" do
        expect { job.perform_now }.
          to change { update_config.reload.default_labels }.
          from(["outdated"]).to(["Dependency"])
        expect(WebMock).not_to have_requested(:get, repo_labels_url)
      end
    end

    context "for a repo that can't be fetched" do
      before { stub_request(:get, repo_labels_url).to_return(status: 404) }

      it "resyncs the repo" do
        result = SynchronizeRepoState::SynchronizeRepoStateResult.error(
          reason: SynchronizeRepoState::ACCOUNT_OUT_OF_SYNC
        )
        dummy_repo_synchronizer = double(run: result)
        expect(SynchronizeRepoState).
          to receive(:new).with(repo: repo,
                                event_source: "job.update_default_labels").
          and_return(dummy_repo_synchronizer)
        expect(dummy_repo_synchronizer).to receive(:run)
        job.perform_now
      end
    end
  end

  context "with multiple update configs" do
    let(:repo_labels) do
      fixture("github_responses/issue_labels_custom.json")
    end

    let!(:update_config) do
      FactoryBot.create(
        :update_config, :active,
        repo: repo,
        default_labels: ["outdated"],
      )
    end

    let!(:other_update_config) do
      FactoryBot.create(
        :update_config, :active,
        repo: repo,
        directory: "/other",
        default_labels: ["outdated"],
        package_manager: package_manager,
      )
    end

    context "with the same package_manager" do
      let(:package_manager) { "bundler" }

      it "updates the default label to 'dependencies'" do
        expect { job.perform_now }.
          to change { update_config.reload.default_labels }.
          from(["outdated"]).to(["dependencies"]).
          and change { other_update_config.reload.default_labels }.
          from(["outdated"]).to(["dependencies"])
      end
    end

    context "with a different package_manager" do
      let(:package_manager) { "npm_and_yarn" }

      it "updates the default label to include a language label" do
        expect { job.perform_now }.
          to change { update_config.reload.default_labels }.
          from(["outdated"]).to(%w(dependencies ruby)).
          and change { other_update_config.reload.default_labels }.
          from(["outdated"]).to(%w(dependencies javascript))
      end

      context "and custom labels" do
        let(:repo_labels) do
          fixture("github_responses/repo_labels_custom.json")
        end

        it "updates the default label to include a language label" do
          expect { job.perform_now }.
            to change { update_config.reload.default_labels }.
            from(["outdated"]).to(%w(Dependency Ruby)).
            and change { other_update_config.reload.default_labels }.
            from(["outdated"]).to(%w(Dependency javascript))
        end
      end
    end
  end
end
