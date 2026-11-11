# frozen_string_literal: true

require "rails_helper"
require_relative "shared_examples/application_processor"

RSpec.describe MultiTopicProcessor do
  include ActiveJob::TestHelper

  let(:processor) { described_class.new }

  let(:consumer) do
    Dependabot.hydro_consumer(processor.options)
  end

  let(:message) do
    instance_double(
      Hydro::Consumer::ConsumerMessage,
      value: decoded_payload,
      timestamp: Time.now.utc,
      offset: 0,
      partition: 0,
      topic: topic,
      headers: {}
    )
  end

  let(:expected_tags) do
    { consumer: "dependabot_api_enterprise" }
  end

  let(:installation_id) { 42 }
  let(:access_token_url) do
    "https://internal-api.service.iad.github.net/app/installations/#{installation_id}/access_tokens"
  end

  before do
    # Stub out the installation verification check to return successfully
    stub_request(:post, access_token_url).to_return(
      status: 200,
      body: erb_fixture("github_responses/installation_access_token.json"),
      headers: { "Content-Type" => "application/json" }
    )
    # Ensure configuration for these processors are loaded when running a single
    # test
    # rubocop:disable Lint/Void
    InstallationCreateProcessor
    VulnerabilityAlertProcessor
    RepositoryPushProcessor
    RepositoryPush::ConfigFileProcessor
    # rubocop:enable Lint/Void

    allow(consumer).to receive(:mark_message_as_processed)
    allow(MetricsClient).to receive(:increment)
  end

  def process_with_consumer
    processor.process_with_consumer(message, consumer)
  end

  describe "configuration", :enterprise do
    subject(:config) { described_class.options }

    it "is correctly configured" do
      expect(config[:group_id]).to eql("dependabot_api_enterprise")
      expect(config[:automatically_mark_as_processed]).to be false
    end

    it "maps the right handler to the right topic" do
      handlers = described_class.handlers_for("github.v1.IntegrationInstallationCreate")
      expect(handlers).to eq([InstallationCreateHandler])
    end

    it "keeps a list of topics to subscribe to" do
      expect(processor.topics).to include(
        /github\.v1\.IntegrationInstallationCreate\Z/,
        /github\.v1\.RepositoryVulnerabilityAlertCreate\Z/,
        /github\.v1\.RepositoryPush\Z/,
      )
    end

    it "includes multiple handlers for the RepositoryPush topic" do
      expect(described_class.handlers_for("github.v1.RepositoryPush")).to match_array(
        [RepositoryPushHandler, RepositoryPush::ConfigFileHandler]
      )
    end
  end

  describe "cloud", :cloud do
    it "does not subscribe to any topics" do
      expect(processor.topics).to be_empty
    end
  end

  context "IntegrationInstallationCreate", :enterprise do
    let(:topic) { "github.v1.IntegrationInstallationCreate" }
    let(:decoded_payload) do
      hydro_fixture(
        name: "create_on_user_for_all",
        schema: "github.v1.IntegrationInstallationCreate"
      )
    end

    it_behaves_like "an application processor" do
      let(:topic) { "github.v1.IntegrationInstallationCreate" }
    end

    context "with a valid message for an install on a user" do
      it "creates and activates the account" do
        expect { process_with_consumer }.to change(Account, :count).from(0).to(1)
        expect(Account.last.current_state).to eq("active")
      end
    end

    context "with a valid message for an unknown installation target id" do
      let(:dummy_account_activator) { instance_double(ActivateAccount, run: nil) }

      before do
        allow(Failbot).to receive(:report)
        allow(ActivateAccount).to receive(:new).
          and_return(dummy_account_activator)
        allow(dummy_account_activator).to receive(:run) do
          raise ActivateAccount::InstallationNotFound
        end
        allow(consumer).to receive(:mark_message_as_processed)
        allow(MetricsClient).to receive(:increment)
      end

      it "marks it as read, counts a dead letter without notifying failbot" do
        process_with_consumer

        expect(MetricsClient).to have_received(:increment).
          with("consumer.dead_letter", tags: expected_tags)
        expect(Failbot).not_to have_received(:report)
        expect(consumer).to have_received(:mark_message_as_processed).
          with(message)
      end
    end
  end

  context "RepositoryVulnerabilityAlertCreate: with a scan", :enterprise do
    let(:topic) { "github.v1.RepositoryVulnerabilityAlertCreate" }

    let(:decoded_payload) do
      hydro_fixture(
        name: "scan",
        schema: "github.v1.RepositoryVulnerabilityAlertCreate"
      )
    end

    let(:expected_tags) do
      {
        consumer: "vulnerability_alert_relay",
        dry_run: false,
        trigger: :SCAN,
        package_manager: "bundler",
      }
    end

    it "creates an update job and marks the message as read" do
      expect(UpdateJob.all).to be_empty

      perform_enqueued_jobs(only: [RepositoryDependencyUpdate::OnboardRepositoryJob, CreateSecurityUpdateJob]) do
        processor.process_with_consumer(message, consumer)
      end

      expect(consumer).to have_received(:mark_message_as_processed).with(message)
      expect(UpdateJob.all).not_to be_empty

      update_job = UpdateJob.last

      expect(update_job.github_request_id).to equal(451)
    end
  end
end
