# frozen_string_literal: true

require "rails_helper"
require_relative "../shared_examples/application_processor"

RSpec.describe RepositoryPush::ConfigFileProcessor do
  include ActiveJob::TestHelper

  let(:processor) { described_class.new }

  let(:consumer) do
    Dependabot.hydro_consumer(processor.options)
  end

  let(:tenant_id) { Dependabot.proxima? ? "1234" : nil }
  let(:tenant_slug) { Dependabot.proxima? ? "lugman-inc" : nil }

  let(:message) do
    instance_double(
      Hydro::Consumer::ConsumerMessage,
      value: decoded_payload,
      timestamp: Time.now.utc,
      offset: 0,
      partition: 0,
      topic: "mock",
      headers: headers,
    )
  end

  let(:decoded_payload) do
    hydro_fixture(name: fixture_name, schema: "github.v1.RepositoryPush")
  end
  let(:headers) { { "X-GitHub-Tenant-ID" => tenant_id, "X-GitHub-Tenant" => tenant_slug } }

  let(:expected_tags) do
    { consumer: "dependabot_api_repository_push_config_file" }
  end

  before do
    allow(consumer).to receive(:mark_message_as_processed)
    allow(MetricsClient).to receive(:increment)
    stub_monolith_feature(
      :dependabot_global_app_onboarding, actor: FeatureFlags::Actor::User.new(27347476), enabled: false
    )
  end

  shared_examples "a correctly instrumented config file event" do
    it "increments only the expected metrics" do
      processor.process_with_consumer(message, consumer)

      expected_metrics.each do |expected_metric|
        expect(MetricsClient).
          to have_received(:increment).with(expected_metric, tags: expected_push_tags).once
      end

      unexpected_metrics.each do |unexpected_metric|
        expect(MetricsClient).
          not_to have_received(:increment).with(unexpected_metric, tags: anything)
      end
    end
  end

  describe "configuration" do
    subject(:config) { described_class.new.options }

    it "is correctly configured" do
      expect(config[:group_id]).
        to eql("dependabot_api_repository_push_config_file")
      expect(config[:subscribe_to]).
        to eql(/github\.v1\.RepositoryPush\Z/)
      expect(config[:automatically_mark_as_processed]).to be false
      expect(config[:min_bytes]).to eq(20.kilobytes)
    end
  end

  context "a push to a Dependabot branch" do
    let!(:repo) { FactoryBot.create(:repo, :active, :bump_test) }
    let(:fixture_name) { "push_dependabot_branch" }

    it "does not process the message" do
      expect { processor.process_with_consumer(message, consumer) }.
        not_to have_enqueued_job(ResyncRepoConfigFileJob)
    end

    it "does not enqueue a config file validation" do
      expect { processor.process_with_consumer(message, consumer) }.
        not_to have_enqueued_job(ValidateConfigFileJob)
    end

    it "does not enqueue a repo setup" do
      expect { processor.process_with_consumer(message, consumer) }.
        not_to have_enqueued_job(SetupRepoJob)
    end

    it "still increments the push_checked metric" do
      processor.process_with_consumer(message, consumer)

      expect(MetricsClient).to have_received(:increment).with(
        "consumer.config_file.push_checked",
        tags: hash_including(config_file_changed: false),
      )
    end
  end

  context "a push to the default branch of a known repository" do
    let!(:repo) { FactoryBot.create(:repo, :active, :bump_test) }

    context "that modifies the dependabot configuration file" do
      let(:fixture_name) { "push_main_config_file" }

      let(:expected_push_tags) do
        {
          default_branch: true,
          changed_files_present: true,
          initial_commit: false,
          config_file_changed: true,
          account_exists: true,
          repository_exists: true,
        }
      end

      let(:expected_metrics) do
        [
          "consumer.config_file.push_checked",
          "consumer.config_file.change_detected",
          "consumer.config_file.sync_queued",
          "consumer.config_file.validation_queued",
        ]
      end

      let(:unexpected_metrics) do
        [
          "consumer.config_file.repo_setup_queued",
        ]
      end

      it_behaves_like "an application processor"

      it_behaves_like "a correctly instrumented config file event"

      it "enqueues a configuration file sync" do
        expect { processor.process_with_consumer(message, consumer) }.
          to have_enqueued_job(ResyncRepoConfigFileJob).
          with(
            account: repo.account,
            repo_name: repo.name,
            repo_github_id: repo.github_id,
            event_source: "hydro.config_file",
          )
      end

      it "enqueues a config file validation" do
        sha = decoded_payload[:after]
        expect { processor.process_with_consumer(message, consumer) }.
          to have_enqueued_job(ValidateConfigFileJob).
          with(account: repo.account, repo_github_id: repo.github_id, sha: sha)
      end
    end

    context "that does not modify the dependabot configuration file" do
      let(:fixture_name) { "push_main" }

      let(:expected_push_tags) do
        {
          default_branch: true,
          changed_files_present: true,
          initial_commit: false,
          config_file_changed: false,
          account_exists: true,
          repository_exists: true,
        }
      end

      let(:expected_metrics) do
        [
          "consumer.config_file.push_checked",
        ]
      end

      let(:unexpected_metrics) do
        [
          "consumer.config_file.sync_queued",
          "consumer.config_file.validation_queued",
          "consumer.config_file.repo_setup_queued",
        ]
      end

      it_behaves_like "an application processor"

      it_behaves_like "a correctly instrumented config file event"

      it "does not enqueue a configuration file sync" do
        expect { processor.process_with_consumer(message, consumer) }.
          not_to have_enqueued_job(ResyncRepoConfigFileJob)
      end

      context "when the repo has been transferred" do
        before { decoded_payload[:owner][:id] = 4321 }

        let!(:new_account) do
          FactoryBot.create(
            :account,
            github_id: decoded_payload[:owner][:id],
          )
        end

        it "does not update the repo's account" do
          expect { processor.process_with_consumer(message, consumer) }.
            not_to change { repo.reload.account }
        end
      end
    end

    context "that is an initial commit with no before sha or changed files" do
      let(:fixture_name) { "push_main_initial_commit" }

      let(:expected_push_tags) do
        {
          default_branch: true,
          changed_files_present: false,
          initial_commit: true,
          config_file_changed: false,
          account_exists: true,
          repository_exists: true,
        }
      end

      let(:expected_metrics) do
        [
          "consumer.config_file.push_checked",
          "consumer.config_file.sync_queued",
          "consumer.config_file.validation_queued",
        ]
      end

      let(:unexpected_metrics) do
        [
          "consumer.config_file.repo_setup_queued",
        ]
      end

      before { Dependabot.flipper[:process_malformed_push_messages].enable }

      it_behaves_like "an application processor"

      it_behaves_like "a correctly instrumented config file event"

      it "enqueues a configuration file sync" do
        expect { processor.process_with_consumer(message, consumer) }.
          to have_enqueued_job(ResyncRepoConfigFileJob)
      end

      it "enqueues a configuration file validation" do
        expect { processor.process_with_consumer(message, consumer) }.
          to have_enqueued_job(ValidateConfigFileJob)
      end
    end

    context "that is malformed with a before sha but no changed files" do
      let(:fixture_name) { "push_main_malformed" }

      let(:expected_push_tags) do
        {
          default_branch: true,
          changed_files_present: false,
          initial_commit: false,
          config_file_changed: false,
          account_exists: true,
          repository_exists: true,
        }
      end

      let(:expected_metrics) do
        [
          "consumer.config_file.push_checked",
        ]
      end

      let(:unexpected_metrics) do
        [
          "consumer.config_file.sync_queued",
          "consumer.config_file.validation_queued",
          "consumer.config_file.repo_setup_queued",
        ]
      end

      it_behaves_like "an application processor"

      it_behaves_like "a correctly instrumented config file event"

      it "does not enqueue a configuration file sync" do
        expect { processor.process_with_consumer(message, consumer) }.
          not_to have_enqueued_job(ResyncRepoConfigFileJob)
      end

      it "does not enqueue a configuration file validation" do
        expect { processor.process_with_consumer(message, consumer) }.
          not_to have_enqueued_job(ValidateConfigFileJob)
      end
    end
  end

  context "a push to a non-default branch of a known repository" do
    let!(:repo) { FactoryBot.create(:repo, :active, :bump_test) }

    let(:fixture_name) { "push_branch_config_file" }

    let(:expected_push_tags) do
      {
        default_branch: false,
        changed_files_present: true,
        initial_commit: false,
        config_file_changed: true,
        account_exists: true,
        repository_exists: true,
      }
    end

    let(:expected_metrics) do
      [
        "consumer.config_file.push_checked",
        "consumer.config_file.change_detected",
        "consumer.config_file.validation_queued",
      ]
    end

    let(:unexpected_metrics) do
      [
        "consumer.config_file.sync_queued",
        "consumer.config_file.repo_setup_queued",
      ]
    end

    it_behaves_like "an application processor"

    it_behaves_like "a correctly instrumented config file event"

    it "does not enqueue a configuration file sync" do
      expect { processor.process_with_consumer(message, consumer) }.
        not_to have_enqueued_job(ResyncRepoConfigFileJob)
    end

    it "does enqueue a config file validation" do
      sha = decoded_payload[:after]
      expect { processor.process_with_consumer(message, consumer) }.
        to have_enqueued_job(ValidateConfigFileJob).
        with(account: repo.account, repo_github_id: repo.github_id, sha: sha)
    end

    context "that is an initial commit with no before sha or changed files" do
      let(:fixture_name) { "push_branch_initial_commit" }

      let(:expected_push_tags) do
        {
          default_branch: false,
          changed_files_present: false,
          initial_commit: true,
          config_file_changed: false,
          account_exists: true,
          repository_exists: true,
        }
      end

      let(:expected_metrics) do
        [
          "consumer.config_file.push_checked",
        ]
      end

      let(:unexpected_metrics) do
        [
          "consumer.config_file.sync_queued",
          "consumer.config_file.validation_queued",
          "consumer.config_file.repo_setup_queued",
        ]
      end

      before { Dependabot.flipper[:process_malformed_push_messages].enable }

      it_behaves_like "an application processor"

      it_behaves_like "a correctly instrumented config file event"

      it "does not enqueue a configuration file sync" do
        expect { processor.process_with_consumer(message, consumer) }.
          not_to have_enqueued_job(ResyncRepoConfigFileJob)
      end

      it "does not enqueue a configuration file validation" do
        expect { processor.process_with_consumer(message, consumer) }.
          not_to have_enqueued_job(ValidateConfigFileJob)
      end
    end

    context "that is malformed with a before sha but no changed files" do
      let(:fixture_name) { "push_branch_malformed" }

      let(:expected_push_tags) do
        {
          default_branch: false,
          changed_files_present: false,
          initial_commit: false,
          config_file_changed: false,
          account_exists: true,
          repository_exists: true,
        }
      end

      let(:expected_metrics) do
        [
          "consumer.config_file.push_checked",
        ]
      end

      let(:unexpected_metrics) do
        [
          "consumer.config_file.sync_queued",
          "consumer.config_file.validation_queued",
          "consumer.config_file.repo_setup_queued",
        ]
      end

      it_behaves_like "an application processor"

      it_behaves_like "a correctly instrumented config file event"

      it "does not enqueue a configuration file sync" do
        expect { processor.process_with_consumer(message, consumer) }.
          not_to have_enqueued_job(ResyncRepoConfigFileJob)
      end

      it "does not enqueue a configuration file validation" do
        expect { processor.process_with_consumer(message, consumer) }.
          not_to have_enqueued_job(ValidateConfigFileJob)
      end
    end
  end

  context "a push to a repository that has transferred to a known account" do
    let!(:repo) { FactoryBot.create(:repo, :active, :bump_test) }

    let!(:new_account) do
      FactoryBot.create(:account)
    end

    before { decoded_payload[:owner][:id] = new_account.github_id }

    context "that modifies the dependabot configuration file on the default branch" do
      let(:fixture_name) { "push_main_config_file" }

      it "delegates the transfer to the repository setup job" do
        sha = decoded_payload[:after]
        expect { processor.process_with_consumer(message, consumer) }.
          to have_enqueued_job(SetupRepoJob).
          with(
            account: new_account,
            github_id: 88632334,
            sha: sha,
          )
      end

      it "does not enqueue a configuration file sync" do
        expect { processor.process_with_consumer(message, consumer) }.
          not_to have_enqueued_job(ResyncRepoConfigFileJob)
      end

      it "does not enqueue a config file validation" do
        expect { processor.process_with_consumer(message, consumer) }.
          not_to have_enqueued_job(ValidateConfigFileJob)
      end
    end

    context "that modifies the dependabot configuration file on a non-default branch" do
      let(:fixture_name) { "push_branch_config_file" }

      it "delegates the transfer to the repository setup job" do
        sha = decoded_payload[:after]
        expect { processor.process_with_consumer(message, consumer) }.
          to have_enqueued_job(SetupRepoJob).
          with(
            account: new_account,
            github_id: 88632334,
            sha: sha,
          )
      end

      it "does not enqueue a configuration file sync" do
        expect { processor.process_with_consumer(message, consumer) }.
          not_to have_enqueued_job(ResyncRepoConfigFileJob)
      end

      it "does not enqueue a config file validation" do
        expect { processor.process_with_consumer(message, consumer) }.
          not_to have_enqueued_job(ValidateConfigFileJob)
      end
    end

    context "that does not modify the dependabot configuration file" do
      let(:fixture_name) { "push_main" }

      it "does not enqueue a repository setup job" do
        expect { processor.process_with_consumer(message, consumer) }.
          not_to have_enqueued_job(SetupRepoJob)
      end

      it "does not enqueue a configuration file sync" do
        expect { processor.process_with_consumer(message, consumer) }.
          not_to have_enqueued_job(ResyncRepoConfigFileJob)
      end

      it "does not enqueue a config file validation" do
        expect { processor.process_with_consumer(message, consumer) }.
          not_to have_enqueued_job(ValidateConfigFileJob)
      end
    end
  end

  context "a push to a repository that has transferred to an unknown account" do
    let!(:repo) { FactoryBot.create(:repo, :active, :bump_test) }

    before { decoded_payload[:owner][:id] = 9999 }

    context "that modifies the dependabot configuration file on the default branch" do
      let(:fixture_name) { "push_main_config_file" }

      it "does not update repo" do
        expect { processor.process_with_consumer(message, consumer) }.
          not_to change { repo.reload.updated_at }
      end

      it "does not enqueue a configuration file sync" do
        expect { processor.process_with_consumer(message, consumer) }.
          not_to have_enqueued_job(ResyncRepoConfigFileJob)
      end

      it "does not enqueue a config file validation" do
        expect { processor.process_with_consumer(message, consumer) }.
          not_to have_enqueued_job(ValidateConfigFileJob)
      end
    end

    context "that modifies the dependabot configuration file on a non-default branch" do
      let(:fixture_name) { "push_branch_config_file" }

      it "does not update repo" do
        expect { processor.process_with_consumer(message, consumer) }.
          not_to change { repo.reload.updated_at }
      end

      it "does not enqueue a configuration file sync" do
        expect { processor.process_with_consumer(message, consumer) }.
          not_to have_enqueued_job(ResyncRepoConfigFileJob)
      end

      it "does not enqueue a config file validation" do
        expect { processor.process_with_consumer(message, consumer) }.
          not_to have_enqueued_job(ValidateConfigFileJob)
      end
    end

    context "that does not modify the dependabot configuration file" do
      let(:fixture_name) { "push_main" }

      it "does not update repo" do
        expect { processor.process_with_consumer(message, consumer) }.
          not_to change { repo.reload.updated_at }
      end

      it "does not enqueue a configuration file sync" do
        expect { processor.process_with_consumer(message, consumer) }.
          not_to have_enqueued_job(ResyncRepoConfigFileJob)
      end

      it "does not enqueue a config file validation" do
        expect { processor.process_with_consumer(message, consumer) }.
          not_to have_enqueued_job(ValidateConfigFileJob)
      end
    end
  end

  context "a push to the default branch of an unknown repository belonging to a known account" do
    let!(:account) { FactoryBot.create(:account, :active, :dependabot) }

    let(:fixture_name) { "push_main_config_file" }

    let(:expected_push_tags) do
      {
        default_branch: true,
        changed_files_present: true,
        initial_commit: false,
        config_file_changed: true,
        account_exists: true,
        repository_exists: false,
      }
    end

    let(:expected_metrics) do
      [
        "consumer.config_file.push_checked",
        "consumer.config_file.change_detected",
        "consumer.config_file.repo_setup_queued",
      ]
    end

    let(:unexpected_metrics) do
      [
        "consumer.config_file.sync_queued",
        "consumer.config_file.validation_queued",
      ]
    end

    it_behaves_like "an application processor"

    it_behaves_like "a correctly instrumented config file event"

    it "enqueues a repository setup job for the push" do
      sha = decoded_payload[:after]
      expect { processor.process_with_consumer(message, consumer) }.
        to have_enqueued_job(SetupRepoJob).
        with(
          account: account,
          github_id: 88632334,
          sha: sha,
        )
    end

    it "does not enqueue a configuration file sync" do
      expect { processor.process_with_consumer(message, consumer) }.
        not_to have_enqueued_job(ResyncRepoConfigFileJob)
    end

    it "does not enqueue a config file validation" do
      expect { processor.process_with_consumer(message, consumer) }.
        not_to have_enqueued_job(ValidateConfigFileJob)
    end

    context "that is an initial commit with no before sha or changed files" do
      let(:fixture_name) { "push_main_initial_commit" }

      let(:expected_push_tags) do
        {
          default_branch: true,
          changed_files_present: false,
          initial_commit: true,
          config_file_changed: false,
          account_exists: true,
          repository_exists: false,
        }
      end

      let(:expected_metrics) do
        [
          "consumer.config_file.push_checked",
        ]
      end

      let(:unexpected_metrics) do
        [
          "consumer.config_file.sync_queued",
          "consumer.config_file.validation_queued",
          "consumer.config_file.repo_setup_queued",
        ]
      end

      it_behaves_like "an application processor"

      it_behaves_like "a correctly instrumented config file event"
    end

    context "that is malformed with a before sha but no changed files" do
      let(:fixture_name) { "push_main_malformed" }

      let(:expected_push_tags) do
        {
          default_branch: true,
          changed_files_present: false,
          initial_commit: false,
          config_file_changed: false,
          account_exists: true,
          repository_exists: false,
        }
      end

      let(:expected_metrics) do
        [
          "consumer.config_file.push_checked",
        ]
      end

      let(:unexpected_metrics) do
        [
          "consumer.config_file.sync_queued",
          "consumer.config_file.validation_queued",
          "consumer.config_file.repo_setup_queued",
        ]
      end

      it_behaves_like "an application processor"

      it_behaves_like "a correctly instrumented config file event"
    end
  end

  context "a push to the default branch of a repository belonging to an unknown account" do
    let(:fixture_name) { "push_main_config_file" }

    let(:expected_push_tags) do
      {
        default_branch: true,
        changed_files_present: true,
        initial_commit: false,
        config_file_changed: true,
        account_exists: false,
        repository_exists: false,
      }
    end

    let(:expected_metrics) do
      [
        "consumer.config_file.push_checked",
        "consumer.config_file.change_detected",
        "consumer.config_file.remediate_account_and_repo_activation_queued",
      ]
    end

    let(:unexpected_metrics) do
      [
        "consumer.config_file.sync_queued",
        "consumer.config_file.validation_queued",
        "consumer.config_file.repo_setup_queued",
      ]
    end

    it_behaves_like "an application processor"

    it_behaves_like "a correctly instrumented config file event"

    it "does not enqueue a configuration file sync" do
      expect { processor.process_with_consumer(message, consumer) }.
        not_to have_enqueued_job(ResyncRepoConfigFileJob)
    end

    it "does not enqueue a config file validation" do
      expect { processor.process_with_consumer(message, consumer) }.
        not_to have_enqueued_job(ValidateConfigFileJob)
    end

    it "does not enqueue a repo setup" do
      expect { processor.process_with_consumer(message, consumer) }.
        not_to have_enqueued_job(SetupRepoJob)
    end

    it "does enqueue a account and repo remediation" do
      expect { processor.process_with_consumer(message, consumer) }.
        to have_enqueued_job(RemediateAccountAndRepoActivationJob)
    end

    context "that is an initial commit with no before sha or changed files" do
      let(:fixture_name) { "push_main_initial_commit" }

      let(:expected_push_tags) do
        {
          default_branch: true,
          changed_files_present: false,
          initial_commit: true,
          config_file_changed: false,
          account_exists: false,
          repository_exists: false,
        }
      end

      let(:expected_metrics) do
        [
          "consumer.config_file.push_checked",
        ]
      end

      let(:unexpected_metrics) do
        [
          "consumer.config_file.sync_queued",
          "consumer.config_file.validation_queued",
          "consumer.config_file.repo_setup_queued",
        ]
      end

      it_behaves_like "an application processor"

      it_behaves_like "a correctly instrumented config file event"
    end

    context "that is malformed with a before sha but no changed files" do
      let(:fixture_name) { "push_main_malformed" }

      let(:expected_push_tags) do
        {
          default_branch: true,
          changed_files_present: false,
          initial_commit: false,
          config_file_changed: false,
          account_exists: false,
          repository_exists: false,
        }
      end

      let(:expected_metrics) do
        [
          "consumer.config_file.push_checked",
        ]
      end

      let(:unexpected_metrics) do
        [
          "consumer.config_file.sync_queued",
          "consumer.config_file.validation_queued",
          "consumer.config_file.repo_setup_queued",
        ]
      end

      it_behaves_like "an application processor"

      it_behaves_like "a correctly instrumented config file event"
    end
  end

  context "a push to the default branch of a repository belonging to an unknown account with global app onboarding" do
    let(:fixture_name) { "push_main_config_file" }

    let(:expected_push_tags) do
      {
        default_branch: true,
        changed_files_present: true,
        initial_commit: false,
        config_file_changed: true,
        account_exists: false,
        repository_exists: false,
      }
    end

    let(:expected_metrics) do
      [
        "consumer.config_file.push_checked",
        "consumer.config_file.change_detected",
        "consumer.config_file.account_setup_queued",
      ]
    end

    let(:unexpected_metrics) do
      [
        "consumer.config_file.sync_queued",
        "consumer.config_file.validation_queued",
        "consumer.config_file.repo_setup_queued",
      ]
    end

    before do
      stub_monolith_feature(
        :dependabot_global_app_onboarding,
        actor: FeatureFlags::Actor::User.new(27347476),
      )
    end

    it_behaves_like "an application processor"

    it_behaves_like "a correctly instrumented config file event"

    it "does not enqueue a configuration file sync" do
      expect { processor.process_with_consumer(message, consumer) }.
        not_to have_enqueued_job(ResyncRepoConfigFileJob)
    end

    it "does not enqueue a config file validation" do
      expect { processor.process_with_consumer(message, consumer) }.
        not_to have_enqueued_job(ValidateConfigFileJob)
    end

    it "does not enqueue a repo setup" do
      expect { processor.process_with_consumer(message, consumer) }.
        not_to have_enqueued_job(SetupRepoJob)
    end

    it "does not enqueue a account and repo remediation" do
      expect { processor.process_with_consumer(message, consumer) }.
        not_to have_enqueued_job(RemediateAccountAndRepoActivationJob)
    end

    it "does enqueue a setup account and repo job" do
      expect { processor.process_with_consumer(message, consumer) }.
        to have_enqueued_job(SetupAccountAndRepoWithGlobalAppJob).
        with(
          account_github_id: 27347476,
          repo_github_id: 88632334,
          tenant_id: tenant_id,
          tenant_slug: tenant_slug,
          event_source: "hydro.config_file",
          sha: "96f4a1df9a76f3eb212ac6a8828d799abceb8141",
        )
    end

    context "that is an initial commit with no before sha or changed files" do
      let(:fixture_name) { "push_main_initial_commit" }

      let(:expected_push_tags) do
        {
          default_branch: true,
          changed_files_present: false,
          initial_commit: true,
          config_file_changed: false,
          account_exists: false,
          repository_exists: false,
        }
      end

      let(:expected_metrics) do
        [
          "consumer.config_file.push_checked",
        ]
      end

      let(:unexpected_metrics) do
        [
          "consumer.config_file.sync_queued",
          "consumer.config_file.validation_queued",
          "consumer.config_file.repo_setup_queued",
        ]
      end

      it_behaves_like "an application processor"

      it_behaves_like "a correctly instrumented config file event"
    end

    context "that is malformed with a before sha but no changed files" do
      let(:fixture_name) { "push_main_malformed" }

      let(:expected_push_tags) do
        {
          default_branch: true,
          changed_files_present: false,
          initial_commit: false,
          config_file_changed: false,
          account_exists: false,
          repository_exists: false,
        }
      end

      let(:expected_metrics) do
        [
          "consumer.config_file.push_checked",
        ]
      end

      let(:unexpected_metrics) do
        [
          "consumer.config_file.sync_queued",
          "consumer.config_file.validation_queued",
          "consumer.config_file.repo_setup_queued",
        ]
      end

      it_behaves_like "an application processor"

      it_behaves_like "a correctly instrumented config file event"
    end
  end

  describe "handling forks" do
    let(:twirp_settings_client) do
      instance_double(
        GitHub::Twirp::DependabotRepositorySettings,
        get_repository_settings: OpenStruct.new(dependabot_config_file_enabled: true)
      )
    end

    before do
      allow(Dependabot::Application).
        to receive(:dependabot_repository_settings_client).
        and_return(twirp_settings_client)
    end

    context "a push to the default branch of an unknown fork" do
      let(:fixture_name) { "push_fork_config_file" }

      it "does not call the monolith over twirp and no jobs are enqueued" do
        expect(twirp_settings_client).not_to receive(:get_repository_settings)

        processor.process_with_consumer(message, consumer)

        expect(ResyncRepoConfigFileJob).not_to have_been_enqueued
        expect(ValidateConfigFileJob).not_to have_been_enqueued
      end
    end

    context "a push to the default branch of an unknown fork belonging to a known account" do
      let!(:account) { FactoryBot.create(:account, :active, :dependabot) }

      let(:fixture_name) { "push_fork_config_file" }

      it "no jobs are enqueued if the config file is disabled in the monolith" do
        allow(twirp_settings_client).
          to receive(:get_repository_settings).
            with(OpenStruct.new(github_id: 88632334)) { OpenStruct.new(dependabot_config_file_enabled: false) }

        processor.process_with_consumer(message, consumer)

        expect(SetupRepoJob).not_to have_been_enqueued
        expect(ResyncRepoConfigFileJob).not_to have_been_enqueued
        expect(ValidateConfigFileJob).not_to have_been_enqueued
      end

      it "a SetupRepoJob is enqueued if the config file is enabled in the monolith" do
        allow(twirp_settings_client).
          to receive(:get_repository_settings).
            with(OpenStruct.new(github_id: 88632334)) { OpenStruct.new(dependabot_config_file_enabled: true) }

        processor.process_with_consumer(message, consumer)

        expect(SetupRepoJob).to have_been_enqueued.with(
          account: account,
          github_id: 88632334,
          sha: anything,
        )
        expect(ResyncRepoConfigFileJob).not_to have_been_enqueued
        expect(ValidateConfigFileJob).not_to have_been_enqueued
      end
    end

    context "a push to the default branch of a known fork without an existing config file" do
      let!(:repo) { FactoryBot.create(:repo, :active, :bump_test, config_file_path: nil) }

      context "that modifies the dependabot configuration file" do
        let(:fixture_name) { "push_fork_config_file" }

        # rubocop:disable RSpec/ExampleLength
        it "enqueues both config file sync and validation if it is enabled in the monolith" do
          allow(twirp_settings_client).
            to receive(:get_repository_settings).
              with(repo) { OpenStruct.new(dependabot_config_file_enabled: true) }

          processor.process_with_consumer(message, consumer)

          expect(ResyncRepoConfigFileJob).to have_been_enqueued.with(
            account: repo.account,
            repo_name: repo.name,
            repo_github_id: repo.github_id,
            event_source: "hydro.config_file",
          )

          sha = decoded_payload[:after]
          expect(ValidateConfigFileJob).to have_been_enqueued.with(
            account: repo.account,
            repo_github_id:
            repo.github_id, sha: sha
          )
        end
        # rubocop:enable RSpec/ExampleLength

        it "does not enqueue any jobs if it is not enabled in the monolith" do
          allow(twirp_settings_client).
            to receive(:get_repository_settings).
              with(repo) { OpenStruct.new(dependabot_config_file_enabled: false) }

          processor.process_with_consumer(message, consumer)

          expect(ResyncRepoConfigFileJob).not_to have_been_enqueued
          expect(ValidateConfigFileJob).not_to have_been_enqueued
        end
      end

      context "that does not modify the dependabot configuration file" do
        let(:fixture_name) { "push_fork" }

        it "does not call the monolith over twirp and no jobs are enqueued" do
          expect(twirp_settings_client).not_to receive(:get_repository_settings)

          processor.process_with_consumer(message, consumer)

          expect(ResyncRepoConfigFileJob).not_to have_been_enqueued
          expect(ValidateConfigFileJob).not_to have_been_enqueued
        end
      end
    end

    context "a push to the default branch of a known fork with an existing config file" do
      let!(:repo) { FactoryBot.create(:repo, :active, :bump_test, config_file_path: ".github/dependabot.yml") }

      context "that modifies the dependabot configuration file" do
        let(:fixture_name) { "push_fork_config_file" }

        it "enqueues both config file sync and validation without calling the monolith" do
          expect(twirp_settings_client).not_to receive(:get_repository_settings)

          processor.process_with_consumer(message, consumer)

          expect(ResyncRepoConfigFileJob).to have_been_enqueued.with(
            account: repo.account,
            repo_name: repo.name,
            repo_github_id: repo.github_id,
            event_source: "hydro.config_file",
          )

          sha = decoded_payload[:after]
          expect(ValidateConfigFileJob).to have_been_enqueued.with(
            account: repo.account,
            repo_github_id:
            repo.github_id, sha: sha
          )
        end
      end

      context "that does not modify the dependabot configuration file" do
        let(:fixture_name) { "push_fork" }

        it "does not call the monolith over twirp and no jobs are enqueued" do
          expect(twirp_settings_client).not_to receive(:get_repository_settings)

          processor.process_with_consumer(message, consumer)

          expect(ResyncRepoConfigFileJob).not_to have_been_enqueued
          expect(ValidateConfigFileJob).not_to have_been_enqueued
        end
      end
    end

    context "a push to a non-default branch of a known fork that does not have an existing config file" do
      let!(:repo) { FactoryBot.create(:repo, :active, :bump_test, config_file_path: nil) }

      context "that modifies the dependabot configuration file" do
        let(:fixture_name) { "push_fork_branch_config_file" }

        it "enqueues just a validation job if it is enabled in the monolith" do
          allow(twirp_settings_client).
            to receive(:get_repository_settings).
              with(repo) { OpenStruct.new(dependabot_config_file_enabled: true) }

          processor.process_with_consumer(message, consumer)

          expect(ResyncRepoConfigFileJob).not_to have_been_enqueued

          sha = decoded_payload[:after]
          expect(ValidateConfigFileJob).to have_been_enqueued.with(
            account: repo.account,
            repo_github_id:
            repo.github_id, sha: sha
          )
        end

        it "does not enqueue anything if it is disabled in the monolith" do
          allow(twirp_settings_client).
            to receive(:get_repository_settings).
              with(repo) { OpenStruct.new(dependabot_config_file_enabled: false) }

          processor.process_with_consumer(message, consumer)

          expect(ResyncRepoConfigFileJob).not_to have_been_enqueued
          expect(ValidateConfigFileJob).not_to have_been_enqueued
        end
      end

      context "that does not modify the dependabot configuration file" do
        let(:fixture_name) { "push_fork_branch" }

        it "does not call the monolith over twirp and no jobs are enqueued" do
          expect(twirp_settings_client).not_to receive(:get_repository_settings)

          processor.process_with_consumer(message, consumer)

          expect(ResyncRepoConfigFileJob).not_to have_been_enqueued
          expect(ValidateConfigFileJob).not_to have_been_enqueued
        end
      end
    end

    context "a push to a non-default branch of a known fork that has an existing config file" do
      let!(:repo) { FactoryBot.create(:repo, :active, :bump_test, config_file_path: ".github/dependabot.yml") }

      context "that modifies the dependabot configuration file" do
        let(:fixture_name) { "push_fork_branch_config_file" }

        it "enqueues just a validation job without calling the monolith" do
          expect(twirp_settings_client).not_to receive(:get_repository_settings)

          processor.process_with_consumer(message, consumer)

          expect(ResyncRepoConfigFileJob).not_to have_been_enqueued
          sha = decoded_payload[:after]
          expect(ValidateConfigFileJob).to have_been_enqueued.with(
            account: repo.account,
            repo_github_id:
            repo.github_id, sha: sha
          )
        end
      end

      context "that does not modify the dependabot configuration file" do
        let(:fixture_name) { "push_fork_branch" }

        it "does not call the monolith over twirp and no jobs are enqueued" do
          expect(twirp_settings_client).not_to receive(:get_repository_settings)

          processor.process_with_consumer(message, consumer)

          expect(ResyncRepoConfigFileJob).not_to have_been_enqueued
          expect(ValidateConfigFileJob).not_to have_been_enqueued
        end
      end
    end
  end
end
