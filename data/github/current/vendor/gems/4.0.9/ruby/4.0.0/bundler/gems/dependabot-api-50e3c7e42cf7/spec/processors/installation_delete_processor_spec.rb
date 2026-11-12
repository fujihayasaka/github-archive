# frozen_string_literal: true

require "rails_helper"
require_relative "shared_examples/application_processor"

RSpec.describe InstallationDeleteProcessor do
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
      headers: { "X-GitHub-Tenant-ID" => "1234", "X-GitHub-Tenant" => "lugman-inc" },
    )
  end

  let(:expected_tags) do
    { consumer: "dependabot_api_installation_delete" }
  end

  def process_with_consumer
    processor.process_with_consumer(message, consumer)
  end

  before do
    allow(consumer).to receive(:mark_message_as_processed)
    allow(MetricsClient).to receive(:increment)
  end

  describe "configuration" do
    subject(:config) { described_class.options }

    it "is correctly configured" do
      expect(config[:group_id]).to eql("dependabot_api_installation_delete")
      expect(config[:subscribe_to]).
        to eql(/github\.v1\.IntegrationInstallationDelete\Z/)
      expect(config[:automatically_mark_as_processed]).to be false
    end
  end

  context "with a valid message for an install on a user" do
    let(:decoded_payload) do
      hydro_fixture(
        name: "delete_from_user",
        schema: "github.v1.IntegrationInstallationDelete"
      )
    end

    let!(:account) do
      account = FindOrCreateAccount.new(
        github_account: {
          id: decoded_payload[:installation][:target_id],
          login: decoded_payload[:installation][:target_name],
          type: decoded_payload[:installation][:target_type].to_s.capitalize,
          tenant_id: message.headers["X-GitHub-Tenant-ID"],
          tenant_slug: message.headers["X-GitHub-Tenant"],
        }.with_indifferent_access
      ).run
      ActivateAccount.new(
        account: account,
        sender: decoded_payload[:sender].with_indifferent_access,
        installation_id: 21399,
      ).run
    end

    let(:expected_account_tags) do
      { event_source: "webhook.installation_deleted", repos: anything }
    end

    it_behaves_like "an application processor"

    it "deactivates the account" do
      expect(account.reload.current_state).to eq("active")

      expect(MetricsClient).to receive(:increment).
        with("account_transition.inactive",
             tags: expected_account_tags)

      process_with_consumer

      expect(account.reload.current_state).to eq("inactive")
    end
  end

  context "with a valid message for an install on an organization" do
    let(:decoded_payload) do
      hydro_fixture(
        name: "delete_from_org",
        schema: "github.v1.IntegrationInstallationDelete"
      )
    end

    let!(:account) do
      account = FindOrCreateAccount.new(
        github_account: {
          id: decoded_payload[:installation][:target_id],
          login: decoded_payload[:installation][:target_name],
          type: decoded_payload[:installation][:target_type].to_s.capitalize,
          tenant_id: message.headers["X-GitHub-Tenant-ID"],
          tenant_slug: message.headers["X-GitHub-Tenant"],
        }.with_indifferent_access
      ).run
      ActivateAccount.new(
        account: account,
        sender: decoded_payload[:sender].with_indifferent_access,
        installation_id: 21399,
      ).run
    end

    let(:expected_account_tags) do
      { event_source: "webhook.installation_deleted", repos: anything }
    end

    it_behaves_like "an application processor"

    it "deactivates the account" do
      expect(account.reload.current_state).to eq("active")

      expect(MetricsClient).to receive(:increment).
        with("account_transition.inactive",
             tags: expected_account_tags)

      process_with_consumer

      expect(account.reload.current_state).to eq("inactive")
    end
  end

  context "with a valid message for an install on a business" do
    let(:decoded_payload) do
      hydro_fixture(
        name: "delete_from_business",
        schema: "github.v1.IntegrationInstallationDelete"
      )
    end

    let!(:account) do
      account = FindOrCreateAccount.new(
        github_account: {
          id: decoded_payload[:installation][:target_id],
          login: decoded_payload[:installation][:target_name],
          type: "User",
          tenant_id: message.headers["X-GitHub-Tenant-ID"],
          tenant_slug: message.headers["X-GitHub-Tenant"],
        }.with_indifferent_access
      ).run
      ActivateAccount.new(
        account: account,
        sender: decoded_payload[:sender].with_indifferent_access,
        installation_id: 21399,
      ).run
    end

    it_behaves_like "an application processor"

    it "does not deactivate an account with a coincidental name/id" do
      expect { process_with_consumer }.
        not_to change { account.reload.current_state }
    end
  end

  context "with a valid message for an install of an unrelated integration" do
    let(:decoded_payload) do
      hydro_fixture(
        name: "delete_from_unrelated_integration",
        schema: "github.v1.IntegrationInstallationDelete"
      )
    end

    let!(:account) do
      account = FindOrCreateAccount.new(
        github_account: {
          id: decoded_payload[:installation][:target_id],
          login: decoded_payload[:installation][:target_name],
          type: decoded_payload[:installation][:target_type].to_s.capitalize,
          tenant_id: message.headers["X-GitHub-Tenant-ID"],
          tenant_slug: message.headers["X-GitHub-Tenant"],
        }.with_indifferent_access
      ).run
      ActivateAccount.new(
        account: account,
        sender: decoded_payload[:sender].with_indifferent_access,
        installation_id: 21399,
      ).run
    end

    it_behaves_like "an application processor"

    it "does not deactivate a Dependabot account for the target" do
      expect { process_with_consumer }.
        not_to change { account.reload.current_state }
    end
  end

  context "with a valid message for an unknown installation target id" do
    let(:decoded_payload) do
      hydro_fixture(
        name: "delete_from_org",
        schema: "github.v1.IntegrationInstallationDelete"
      )
    end

    it "marks it as read, counts a dead letter without notifying failbot" do
      expect(MetricsClient).to receive(:increment).
        with("consumer.dead_letter", tags: expected_tags)

      expect(Failbot).not_to receive(:report)
      expect(consumer).to receive(:mark_message_as_processed).
        with(message)

      process_with_consumer
    end
  end

  context "with a valid message for an installation id that is not the accounts current installation id" do
    let(:decoded_payload) do
      hydro_fixture(
        name: "delete_from_user",
        schema: "github.v1.IntegrationInstallationDelete"
      )
    end

    let(:account) do
      account = FindOrCreateAccount.new(
        github_account: {
          id: decoded_payload[:installation][:target_id],
          login: decoded_payload[:installation][:target_name],
          type: decoded_payload[:installation][:target_type].to_s.capitalize,
          tenant_id: message.headers["X-GitHub-Tenant-ID"],
          tenant_slug: message.headers["X-GitHub-Tenant"],
        }.with_indifferent_access
      ).run
      ActivateAccount.new(
        account: account,
        sender: decoded_payload[:sender].with_indifferent_access,
        installation_id: decoded_payload[:installation][:id] + 1,
      ).run
    end

    it "does not deactivate a Dependabot account for the target" do
      expect { process_with_consumer }.
        not_to change { account.reload.current_state }
    end
  end

  context "with a valid message for a global token feature flagged target id" do
    let(:decoded_payload) do
      hydro_fixture(
        name: "delete_from_org",
        schema: "github.v1.IntegrationInstallationDelete"
      )
    end

    let!(:account) do
      account = FindOrCreateAccount.new(
        github_account: {
          id: decoded_payload[:installation][:target_id],
          login: decoded_payload[:installation][:target_name],
          type: decoded_payload[:installation][:target_type].to_s.capitalize,
          tenant_id: message.headers["X-GitHub-Tenant-ID"],
          tenant_slug: message.headers["X-GitHub-Tenant"],
        }.with_indifferent_access
      ).run
      account.enable_feature(:global_tokens)
      ActivateAccount.new(
        account: account,
        sender: decoded_payload[:sender].with_indifferent_access,
        installation_id: 21399,
      ).run
    end

    it "does not deactivate a Dependabot account for the target" do
      expect { process_with_consumer }.
        not_to change { account.reload.current_state }
    end
  end

  context "with a valid message for an global app onboarded target id" do
    let(:decoded_payload) do
      hydro_fixture(
        name: "delete_from_org",
        schema: "github.v1.IntegrationInstallationDelete"
      )
    end

    let!(:account) do
      account = FindOrCreateAccount.new(
        github_account: {
          id: decoded_payload[:installation][:target_id],
          login: decoded_payload[:installation][:target_name],
          type: decoded_payload[:installation][:target_type].to_s.capitalize,
          tenant_id: message.headers["X-GitHub-Tenant-ID"],
          tenant_slug: message.headers["X-GitHub-Tenant"],
        }.with_indifferent_access
      ).run
      ActivateAccount.new(
        account: account,
        sender: decoded_payload[:sender].with_indifferent_access,
        installation_id: Account::GLOBAL_APP_INSTALLATION_ID,
      ).run
    end

    it "does not deactivate a Dependabot account for the target" do
      expect { process_with_consumer }.
        not_to change { account.reload.current_state }
    end
  end

  context "with a valid message for a global app feature flagged organization" do
    let(:decoded_payload) do
      hydro_fixture(
        name: "delete_from_org",
        schema: "github.v1.IntegrationInstallationDelete"
      )
    end

    let!(:account) do
      account = FindOrCreateAccount.new(
        github_account: {
          id: decoded_payload[:installation][:target_id],
          login: decoded_payload[:installation][:target_name],
          type: decoded_payload[:installation][:target_type].to_s.capitalize,
          tenant_id: message.headers["X-GitHub-Tenant-ID"],
          tenant_slug: message.headers["X-GitHub-Tenant"],
        }.with_indifferent_access
      ).run
      account.enable_feature(:global_tokens)
      ActivateAccount.new(
        account: account,
        sender: decoded_payload[:sender].with_indifferent_access,
        installation_id: 21399,
      ).run
    end

    let(:expected_account_tags) do
      { event_source: "webhook.installation_deleted", repos: anything }
    end

    it_behaves_like "an application processor"

    it "does not deactivate a Dependabot account for the target" do
      expect { process_with_consumer }.
        not_to change { account.reload.current_state }
    end
  end

  context "with a valid message that has no sender information" do
    let(:decoded_payload) do
      hydro_fixture(
        name: "delete_without_sender",
        schema: "github.v1.IntegrationInstallationDelete"
      )
    end

    let!(:account) do
      account = FindOrCreateAccount.new(
        github_account: {
          id: decoded_payload[:installation][:target_id],
          login: decoded_payload[:installation][:target_name],
          type: decoded_payload[:installation][:target_type].to_s.capitalize,
          tenant_id: message.headers["X-GitHub-Tenant-ID"],
          tenant_slug: message.headers["X-GitHub-Tenant"],
        }.with_indifferent_access
      ).run
      ActivateAccount.new(
        account: account,
        sender: {},
        installation_id: 21399,
      ).run
    end

    let(:expected_account_tags) do
      { event_source: "webhook.installation_deleted", repos: anything }
    end

    it_behaves_like "an application processor"

    it "deactivates the account" do
      expect(account.reload.current_state).to eq("active")

      expect(MetricsClient).to receive(:increment).
        with("account_transition.inactive",
             tags: expected_account_tags)

      process_with_consumer

      expect(account.reload.current_state).to eq("inactive")
    end
  end
end
