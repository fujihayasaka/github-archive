# frozen_string_literal: true

require "rails_helper"
require_relative "shared_examples/application_processor"

RSpec.describe InstallationCreateProcessor do
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
    { consumer: "dependabot_api_installation_create" }
  end

  before do
    allow(consumer).to receive(:mark_message_as_processed)
    allow(MetricsClient).to receive(:increment)
  end

  def process_with_consumer
    processor.process_with_consumer(message, consumer)
  end

  describe "configuration" do
    subject(:config) { described_class.options }

    it "is correctly configured" do
      expect(config[:group_id]).to eql("dependabot_api_installation_create")
      expect(config[:subscribe_to]).
        to eql(/github\.v1\.IntegrationInstallationCreate\Z/)
      expect(config[:automatically_mark_as_processed]).to be false
    end
  end

  context "with a valid message for an install on a user" do
    let(:decoded_payload) do
      hydro_fixture(
        name: "create_on_user_for_all",
        schema: "github.v1.IntegrationInstallationCreate"
      )
    end

    before do
      stub_monolith_feature(
        :dependabot_global_app_onboarding,
        actor: FeatureFlags::Actor::User.new(decoded_payload.dig(:installation, :target_id)),
        enabled: false
      )
    end

    it_behaves_like "an application processor"

    it "creates and activates the account" do
      expect { process_with_consumer }.to change(Account, :count).from(0).to(1)
      expect(Account.last.current_state).to eq("active")
    end

    it "sets the account's event source to 'hydro'" do
      expect { process_with_consumer }.to change(Account, :count).from(0).to(1)
      expect(Account.last.event_source).to eq("hydro")
    end
  end

  context "with a valid message for an install on an organization" do
    let(:decoded_payload) do
      hydro_fixture(
        name: "create_on_org_for_selected",
        schema: "github.v1.IntegrationInstallationCreate"
      )
    end

    before do
      stub_monolith_feature(
        :dependabot_global_app_onboarding,
        actor: FeatureFlags::Actor::User.new(decoded_payload.dig(:installation, :target_id)),
        enabled: false
      )
    end

    it_behaves_like "an application processor"

    it "creates and activates the account" do
      expect { process_with_consumer }.to change(Account, :count).from(0).to(1)
      expect(Account.last.current_state).to eq("active")
    end

    it "sets up the selected repositories" do
      process_with_consumer

      account = Account.last

      expect(SetupRepoJob).to have_been_enqueued.with(account: account, github_id: 88632334)
    end
  end

  context "with logins that include shortcodes" do
    let(:decoded_payload) do
      hydro_fixture(
        name: "create_on_org_proxima",
        schema: "github.v1.IntegrationInstallationCreate"
      )
    end

    it "removes the shortcodes when creating the account in Proxima", :proxima do
      expect { process_with_consumer }.to change(Account, :count).from(0).to(1)
      expect(Account.last.github_login).to eq("dependabot")
    end

    it "stores the shortcode on the tenant when creating the account in Proxima", :proxima do
      expect { process_with_consumer }.to change(Account, :count).from(0).to(1)
      expect(Account.last.shortcode).to eq("github")
    end

    it "retains the shortcodes when creating the account outside of Proxima", :cloud, :enterprise do
      expect { process_with_consumer }.to change(Account, :count).from(0).to(1)
      expect(Account.last.github_login).to eq("dependabot_github")
    end
  end

  context "with a valid message for an install on a business" do
    let(:decoded_payload) do
      hydro_fixture(
        name: "create_on_business",
        schema: "github.v1.IntegrationInstallationCreate"
      )
    end

    before do
      stub_monolith_feature(
        :dependabot_global_app_onboarding,
        actor: FeatureFlags::Actor::User.new(decoded_payload.dig(:installation, :target_id)),
        enabled: false
      )
    end

    it_behaves_like "an application processor"

    it "does not create an account" do
      expect { process_with_consumer }.not_to change(Account, :count)
    end
  end

  context "with a valid message for an install of an unrelated integration" do
    let(:decoded_payload) do
      hydro_fixture(
        name: "create_on_unrelated_integration",
        schema: "github.v1.IntegrationInstallationCreate"
      )
    end

    before do
      stub_monolith_feature(
        :dependabot_global_app_onboarding,
        actor: FeatureFlags::Actor::User.new(decoded_payload.dig(:installation, :target_id)),
        enabled: false
      )
    end

    it_behaves_like "an application processor"

    it "does not create an account" do
      expect { process_with_consumer }.not_to change(Account, :count)
    end
  end

  context "with a valid message when global app onboarding is enabled" do
    let(:decoded_payload) do
      hydro_fixture(
        name: "create_on_org_for_selected",
        schema: "github.v1.IntegrationInstallationCreate"
      )
    end

    before do
      stub_monolith_feature(
        :dependabot_global_app_onboarding,
        actor: FeatureFlags::Actor::User.new(27347476),
      )
    end

    it_behaves_like "an application processor"

    it "does not create an account" do
      expect { process_with_consumer }.not_to change(Account, :count)
    end
  end
end
