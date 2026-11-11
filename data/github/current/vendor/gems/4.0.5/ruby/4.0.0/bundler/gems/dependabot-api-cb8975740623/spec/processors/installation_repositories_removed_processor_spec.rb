# frozen_string_literal: true

require "rails_helper"
require_relative "shared_examples/application_processor"

RSpec.describe InstallationRepositoriesRemovedProcessor do
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
      topic: "mock",
      headers: {},
    )
  end

  let(:decoded_payload) do
    hydro_fixture(
      name: "default",
      schema: "github.v1.IntegrationInstallationRepositoriesRemoved"
    )
  end

  let(:expected_tags) do
    { consumer: "dependabot_api_installation_repositories_removed" }
  end

  before do
    header = { "Content-Type" => "application/json" }
    github_url = "https://api.github.com/"
    url = github_url + "app/installations/25222"
    github_installation = fixture("github_responses/installation.json")

    stub_request(:get, url).
      to_return(status: 200, body: github_installation, headers: header)

    allow(consumer).to receive(:mark_message_as_processed)
    allow(MetricsClient).to receive(:increment)
  end

  describe "configuration" do
    subject(:config) { described_class.options }

    it "is correctly configured" do
      expect(config[:group_id]).
        to eql("dependabot_api_installation_repositories_removed")
      expect(config[:subscribe_to]).
        to eql(/github\.v1\.IntegrationInstallationRepositoriesRemoved\Z/)
      expect(config[:automatically_mark_as_processed]).to be false
    end
  end

  context "with a message for an existing, active installation id" do
    let(:account) do
      FactoryBot.create(:account, :dependabot)
    end

    before do
      account.transition_to!(:active, installation_id: 25222)
    end

    it_behaves_like "an application processor"

    it "delegates to DeactivateRepoJob" do
      expect(DeactivateRepoJob).
        to receive(:perform_later).
        with(
          repo_github_id: 88632334,
          user: { "login" => "greysteil", "id" => 1144873 }
        )

      processor.process_with_consumer(message, consumer)
    end

    context "messages does not have sender data" do
      let(:decoded_payload) do
        hydro_fixture(
          name: "no_sender",
          schema: "github.v1.IntegrationInstallationRepositoriesRemoved"
        )
      end

      it "delegates to DeactivateRepoJob using an unknown user placeholder" do
        expect(DeactivateRepoJob).
          to receive(:perform_later).
          with(
            repo_github_id: 88632334,
            user: { "login" => "unknown", "id" => 0 }
          )

        processor.process_with_consumer(message, consumer)
      end
    end
  end

  context "with a message for an unknown installation id" do
    it_behaves_like "an application processor"

    context "when the installation id has been used on a different account" do
      # We appear to get a small number of messages that mismatch install id
      # and account name.
      #
      # The root cause could be transfers or renames not being relayed correctly
      # but it is likely benign as ingesting and UpdateJob will always upsert
      # the correct state.
      #
      # We should treat these cases as dead letters for now.
      before do
        FactoryBot.create(:account).tap do |account|
          account.transition_to!(:active, installation_id: 25222)
        end
      end

      it "marks it as read, counts a dead letter without notifying failbot" do
        expect(MetricsClient).to receive(:increment).
          with("consumer.dead_letter", tags: expected_tags)

        expect(Failbot).not_to receive(:report)
        expect(consumer).to receive(:mark_message_as_processed).
          with(message)

        processor.process_with_consumer(message, consumer)
      end
    end
  end

  context "with a message for an installation id that has been deactivated" do
    let(:account) do
      FactoryBot.create(:account, :dependabot)
    end

    before do
      account.transition_to!(:active, installation_id: 25222)
      account.transition_to!(:inactive, installation_id: 25222)
    end

    it_behaves_like "an application processor"

    it "doesn't attempt to deactivate any old update configs" do
      expect(DeactivateRepoJob).
        not_to receive(:perform_later)
      processor.process_with_consumer(message, consumer)
    end
  end

  context "with a user account that was upgraded to an org" do
    let(:account) do
      FactoryBot.create(:account, :dependabot, :user)
    end

    before do
      account.transition_to!(:active, installation_id: 25222)
    end

    it "updates the account type" do
      expect { processor.process_with_consumer(message, consumer) }.
        to change { account.reload.account_type }.from("user").to("org")
    end
  end

  context "with a message for a global app onboarded account" do
    let(:account) do
      FactoryBot.create(:account, :dependabot)
    end

    before do
      account.transition_to!(:active, installation_id: Account::GLOBAL_APP_INSTALLATION_ID)
    end

    it_behaves_like "an application processor"

    it "doesn't attempt to deactivate any old update configs" do
      expect(DeactivateRepoJob).
        not_to receive(:perform_later)
      processor.process_with_consumer(message, consumer)
    end
  end

  context "with a message for a global app feature flagged account" do
    let(:account) do
      FactoryBot.create(:account, :dependabot)
    end

    before do
      account.transition_to!(:active, installation_id: 25222)
      account.enable_feature(:global_tokens) # rubocop:disable Dependabot/NoLocalFeatureFlags
    end

    it_behaves_like "an application processor"

    it "doesn't attempt to deactivate any old update configs" do
      expect(DeactivateRepoJob).
        not_to receive(:perform_later)
      processor.process_with_consumer(message, consumer)
    end
  end
end
