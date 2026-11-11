# frozen_string_literal: true

require "rails_helper"

RSpec.describe Repo, type: :model do
  subject(:repo) { FactoryBot.build_stubbed(:repo) }

  describe "validations" do
    it { is_expected.to be_valid }
  end

  describe "callbacks" do
    subject(:repo) { FactoryBot.create(:repo) }

    context "after updating the default_branch" do
      it "enqueues a ResyncRepoConfigFileJob" do
        expect { repo.update!(default_branch: "develop") }.
          to have_enqueued_job(ResyncRepoConfigFileJob).
          with(
            account: repo.account,
            repo_name: repo.name,
            repo_github_id: repo.github_id,
          )
      end

      context "after an unrelated change" do
        it "does not enqueue an ResyncRepoConfigFileJob" do
          expect { repo.update!(name: "something-else") }.
            not_to have_enqueued_job(ResyncRepoConfigFileJob)
        end
      end

      context "with a PR" do
        subject(:repo) { pull_request.repo }

        let!(:pull_request) { FactoryBot.create(:pull_request) }

        it "enqueues an UpdatePullRequestBaseBranchJob for the PR" do
          expect { repo.update!(default_branch: "develop") }.
            to have_enqueued_job(UpdatePullRequestBaseBranchJob).
            with(pull_request: pull_request)
        end

        context "that is closed" do
          let!(:pull_request) { FactoryBot.create(:pull_request, :closed) }

          it "does not enqueue an UpdatePullRequestBaseBranchJob for the PR" do
            expect { repo.update!(default_branch: "develop") }.
              not_to have_enqueued_job(UpdatePullRequestBaseBranchJob)
          end
        end

        context "that belongs to an update config with a target branch" do
          before { pull_request.update_config.update!(target_branch: "custom") }

          it "does not enqueue an UpdatePullRequestBaseBranchJob for the PR" do
            expect { repo.update!(default_branch: "develop") }.
              not_to have_enqueued_job(UpdatePullRequestBaseBranchJob)
          end
        end

        context "after an unrelated change" do
          it "does not enqueue an UpdatePullRequestBaseBranchJob" do
            expect { repo.update!(name: "something-else") }.
              not_to have_enqueued_job(UpdatePullRequestBaseBranchJob)
          end
        end

        context "the repository is currently paused", feature: :inactivity_pausing do
          subject(:repo) { pull_request.repo }

          let!(:pull_request) { FactoryBot.create(:pull_request) }

          before do
            repo.update!(paused_at: 1.minute.ago)
          end

          it "does not enqueue an UpdatePullRequestBaseBranchJob for the PR" do
            expect { repo.update!(default_branch: "develop") }.
              not_to have_enqueued_job(UpdatePullRequestBaseBranchJob)
          end
        end
      end
    end
  end

  describe "#full_name" do
    subject { repo.full_name }

    let(:repo) { FactoryBot.build_stubbed(:repo, :bump_test) }

    it { is_expected.to eq("dependabot/bump-test") }
  end

  describe "#github_url" do
    subject { repo.github_url }

    let(:repo) { FactoryBot.build_stubbed(:repo, :bump_test) }

    it { is_expected.to eq("https://github.com/dependabot/bump-test") }
  end

  describe "#config_feature_enabled?" do
    subject(:feature_enabled?) { repo.config_feature_enabled?(:mock_feature) }

    before do
      repo.disable_feature(:mock_feature)
      repo.account.disable_feature(:mock_feature)
    end

    context "disabled" do
      it { is_expected.to eq(false) }
    end

    context "enabled on repository" do
      before { repo.enable_feature(:mock_feature) }

      it { is_expected.to eq(true) }
    end

    context "enabled on account" do
      before { repo.account.enable_feature(:mock_feature) }

      it { is_expected.to eq(true) }
    end
  end

  describe "#settings" do
    it "returns a RepositorySettings object" do
      repo = build_stubbed(:repo)

      expect(repo.settings).to be_a(RepositorySettings)
    end
  end

  describe "default_update_schedule_time_of_day" do
    it "is a time" do
      DateTime.strptime(repo.default_update_schedule_time_of_day, "%H:%M")
    end

    def std_dev(histogram)
      mean = histogram.values.sum / histogram.size
      variance = histogram.values.reduce(0) { |a, e| a + (e - mean)**2 } / histogram.size
      Math.sqrt(variance)
    end

    it "distributes evenly" do
      repos = 5000
      histogram = Hash.new(0)
      (1..repos).each do |i|
        repo.id = i
        histogram[repo.default_update_schedule_time_of_day] += 1
      end

      expect(histogram.size).to eq(24 * 6)
      expect(std_dev(histogram)).to be < 6
    end
  end

  describe "#audit_log" do
    subject(:repo) { FactoryBot.create(:repo, config_file_path: ".github/dependabot.yml") }

    let(:expected_tags) do
      {
        context: "repository",
        account_id: repo.account.id,
        "gh.owner.id": repo.account.github_id,
        repository_id: repo.id,
        "gh.repo.id": repo.github_id,
        "gh.repo.visibility": "private",
        repository_using_config_file: true,
        nwo: repo.nwo,
        will_pause_at: repo.will_pause_at,
        paused_at: repo.paused_at,
      }
    end

    before do
      allow(Dependabot::Logger).to receive(:info)
      allow(Dependabot::Logger).to receive(:log_context).and_call_original
      allow(Activity::PauseManager).to receive(:handle_activity_log_event)
    end

    it "writes a structured info log of the event to the repository topic" do
      repo.event_stream.record_event("event-a", tags: { foo: "bar" })

      expect(Dependabot::Logger).to have_received(:info).with(
        {
          activity_log_event: "repository.event-a",
          foo: "bar",
        }
      )
    end

    it "add details of the repository and account to the context" do
      repo.event_stream.record_event("event-a", tags: { foo: "bar" })

      expect(Dependabot::Logger).to have_received(:log_context).with(expected_tags)
    end

    it "notifies the Activity::PauseManager of the event" do
      repo.event_stream.record_event("event-a", tags: { foo: "bar" })

      expect(Activity::PauseManager).to have_received(:handle_activity_log_event).with(
        "repository.event-a",
        expected_tags.merge({ foo: "bar" })
      )
    end
  end

  describe "#audit_log_message" do
    let(:repo) { FactoryBot.create(:repo) }
    let(:org_repo) do
      account = FactoryBot.build(:account, :org, :active)
      FactoryBot.create(:repo, account: account)
    end
    let(:expected_audit_log_message) do
      {
        action: "dependabot_updates.repository_paused",
        document: build_expected_document_payload(repo).to_json,
        event_time: Time.now.utc.to_i,
        document_id: SecureRandom.urlsafe_base64(16),
        audit_log: :GITHUB,
      }
    end

    def build_expected_document_payload(repository)
      expected_payload = {
        action: "dependabot_updates.repository_paused",
        actor: Dependabot::Application.integration_login,
        actor_id: Dependabot::Application.github_dependabot_user_id,
        repo: repository.name,
        repo_id: repository.id,
        '@timestamp': Time.now.utc.to_i,
        _document_id: SecureRandom.urlsafe_base64(16),
      }
      if repository.account.account_type == "user"
        expected_payload[:user_id] = repository.account.github_id
        expected_payload[:user] = repository.account.github_login
      else
        expected_payload[:org_id] = repository.account.github_id
        expected_payload[:org] = repository.account.github_login
      end
      expected_payload
    end

    it "builds an audit log message" do
      payload = repo.audit_log_message("dependabot_updates.repository_paused")

      expect(payload[:action]).to eq(expected_audit_log_message[:action])
      expect(payload[:document]).to be_present
      expect(payload[:event_time]).to be_within(1.second).of expected_audit_log_message[:event_time]
      expect(payload[:document_id]).to be_present
      expect(payload[:audit_log]).to eq(expected_audit_log_message[:audit_log])
    end

    it "adds details to the document for a user account type" do
      expected_payload = build_expected_document_payload(repo)
      payload = repo.audit_log_message("dependabot_updates.repository_paused")
      document_payload = JSON.parse(payload[:document])

      expect(document_payload["action"]).to eq(expected_payload[:action])
      expect(document_payload["actor"]).to eq(expected_payload[:actor])
      expect(document_payload["actor_id"]).to eq(expected_payload[:actor_id])
      expect(document_payload["repo"]).to eq(expected_payload[:repo])
      expect(document_payload["repo_id"]).to eq(expected_payload[:repo_id])
      expect(document_payload["user_id"]).to eq(expected_payload[:user_id])
      expect(document_payload["user"]).to eq(expected_payload[:user])
      expect(document_payload["_document_id"]).to be_present
      expect(document_payload["@timestamp"]).to be_within(1.second).of expected_payload[:@timestamp]
    end

    it "adds details to the document for an org account type" do
      expected_payload = build_expected_document_payload(org_repo)
      payload = org_repo.audit_log_message("dependabot_updates.repository_paused")
      document_payload = JSON.parse(payload[:document])

      expect(document_payload["action"]).to eq(expected_payload[:action])
      expect(document_payload["actor"]).to eq(expected_payload[:actor])
      expect(document_payload["actor_id"]).to eq(expected_payload[:actor_id])
      expect(document_payload["org"]).to eq(expected_payload[:org])
      expect(document_payload["org_id"]).to eq(expected_payload[:org_id])
      expect(document_payload["repo"]).to eq(expected_payload[:repo])
      expect(document_payload["repo_id"]).to eq(expected_payload[:repo_id])
      expect(document_payload["_document_id"]).to be_present
      expect(document_payload["@timestamp"]).to be_within(1.second).of expected_payload[:@timestamp]
    end
  end
end
