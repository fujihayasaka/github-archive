# frozen_string_literal: true

require "rails_helper"

RSpec.describe RepositorySettings do
  include MonolithSettingsHelper

  context "when a repo is not found in the monolith" do
    it "raises a RepoNotFound error" do
      repo = instance_double(Repo)
      settings = described_class.new(repo)

      allow(Dependabot::Application.dependabot_repository_settings_client).
        to receive(:get_repository_settings).
        and_raise(GitHub::Twirp::DependabotRepositorySettings::NotFound)

      # can be any method, as they rely on a call to the monolith
      expect { settings.grouped_security_updates_enabled? }.
        to raise_error(described_class::RepoNotFound)
    end
  end

  describe "#grouped_security_updates_enabled?" do
    it "returns true when the source of truth says security update grouping is enabled" do
      repo = instance_double(Repo)
      settings = described_class.new(repo)

      stub_monolith_settings(security_updates_grouping_enabled: true)

      expect(settings.grouped_security_updates_enabled?).to eq(true)
    end

    it "returns false when the source of truth says security update grouping is disabled" do
      repo = instance_double(Repo)
      settings = described_class.new(repo)

      stub_monolith_settings(security_updates_grouping_enabled: false)

      expect(settings.grouped_security_updates_enabled?).to eq(false)
    end
  end
end
