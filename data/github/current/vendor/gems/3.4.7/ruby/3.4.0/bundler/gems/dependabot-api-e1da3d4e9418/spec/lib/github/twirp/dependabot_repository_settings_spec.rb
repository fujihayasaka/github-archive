# frozen_string_literal: true

require "rails_helper"
require "github_helpers"

RSpec.describe GitHub::Twirp::DependabotRepositorySettings, :vcr do
  let(:github_api_url) do
    "http://host.docker.internal:3000/api/v3/"
  end

  let(:twirp_client) do
    GitHub::Twirp::Client.new(
      github_api_url: github_api_url.to_s,
      hmac_key: "dependabotapihmac"
    )
  end

  let(:client) do
    described_class.new(
      client: twirp_client
    )
  end

  let(:repo) do
    FactoryBot.create(:repo, github_id: 4) # corresponds to monalisa/smile in gh/gh localdev
  end

  let(:missing_repo) do
    FactoryBot.create(:repo, github_id: 1001)
  end

  before do
    allow(Dependabot::Logger).to receive(:warn)
  end

  describe "#get_repository_settings" do
    it "retrieves the settings for the given repo from the monolith" do
      settings = client.get_repository_settings(repo)

      expect(settings.id).to be(4)
      expect(settings.dependabot_installed).to be false
      expect(settings.dependabot_config_file_enabled).to be true

      expect(MetricsClient).to have_received(:distribution).with(
        "twirp.github.dependabot_repository_settings.get_repository_settings",
        anything,
        tags: { response_code: :ok }
      )
    end

    it "raises an error if the repository does not exist" do
      expect { client.get_repository_settings(missing_repo) }.to raise_error(
        GitHub::Twirp::DependabotRepositorySettings::NotFound,
        "Repository ID '1001' not found."
      )

      expect(MetricsClient).to have_received(:distribution).with(
        "twirp.github.dependabot_repository_settings.get_repository_settings",
        anything,
        tags: { response_code: :not_found }
      )
    end
  end

  describe "set_paused_flag_on_repository" do
    it "sets the flag on the repository" do
      expect(client.set_paused_flag_on_repository(repo)).to be_truthy

      expect(MetricsClient).to have_received(:distribution).with(
        "twirp.github.dependabot_repository_settings.set_paused_flag_on_repository",
        anything,
        tags: { response_code: :ok }
      )
    end

    it "raises an error if the repository does not exist" do
      expect { client.set_paused_flag_on_repository(missing_repo) }.to raise_error(
        GitHub::Twirp::DependabotRepositorySettings::NotFound,
        "Repository ID '1001' not found."
      )

      expect(MetricsClient).to have_received(:distribution).with(
        "twirp.github.dependabot_repository_settings.set_paused_flag_on_repository",
        anything,
        tags: { response_code: :not_found }
      )
    end
  end

  describe "remove_paused_flag_on_repository" do
    it "sets the flag on the repository" do
      expect(client.remove_paused_flag_on_repository(repo)).to be_truthy

      expect(MetricsClient).to have_received(:distribution).with(
        "twirp.github.dependabot_repository_settings.remove_paused_flag_on_repository",
        anything,
        tags: { response_code: :ok }
      )
    end

    it "raises an error if the repository does not exist" do
      expect { client.remove_paused_flag_on_repository(missing_repo) }.to raise_error(
        GitHub::Twirp::DependabotRepositorySettings::Error,
        "not_found - Repository ID '1001' not found."
      )

      expect(MetricsClient).to have_received(:distribution).with(
        "twirp.github.dependabot_repository_settings.remove_paused_flag_on_repository",
        anything,
        tags: { response_code: :not_found }
      )
    end
  end

  describe "set_self_hosted_flag_on_repository" do
    it "sets the flag on the repository" do
      expect(client.set_self_hosted_flag_on_repository(repo)).to be_truthy

      expect(MetricsClient).to have_received(:distribution).with(
        "twirp.github.dependabot_repository_settings.set_self_hosted_flag_on_repository",
        anything,
        tags: { response_code: :ok }
      )
    end

    it "raises an error if the repository does not exist" do
      expect { client.set_self_hosted_flag_on_repository(missing_repo) }.to raise_error(
        GitHub::Twirp::DependabotRepositorySettings::NotFound,
        "Repository ID '1001' not found."
      )

      expect(MetricsClient).to have_received(:distribution).with(
        "twirp.github.dependabot_repository_settings.set_self_hosted_flag_on_repository",
        anything,
        tags: { response_code: :not_found }
      )
    end

    it "does not raise an error if actions are not enabled for the repository" do
      expect(client.set_self_hosted_flag_on_repository(repo)).to be_truthy

      expect(MetricsClient).to have_received(:distribution).with(
        "twirp.github.dependabot_repository_settings.set_self_hosted_flag_on_repository",
        anything,
        tags: { response_code: :ok }
      )

      expect(Dependabot::Logger).to have_received(:warn).with(
        msg: "Actions feature not enabled for the repo",
        "code.namespace": "GitHub::Twirp::DependabotRepositorySettings",
        "gh.repo.id": repo.github_id,
      )
    end
  end
end
