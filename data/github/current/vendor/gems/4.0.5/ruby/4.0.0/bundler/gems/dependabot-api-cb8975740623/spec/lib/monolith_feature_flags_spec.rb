# frozen_string_literal: true

require "rails_helper"
require "support/monolith_feature_flag_helper"

RSpec.describe MonolithFeatureFlags do
  let(:account) do
    create(:account, github_id: 200)
  end

  let(:repo) do
    create(:repo, account: account, github_id: 500)
  end

  def monolith_feature_enabled?(**kwargs)
    Dependabot::Application.monolith_feature_enabled?(**kwargs)
  end

  describe "for a repo" do
    before do
      stub_monolith_feature(:my_awesome_feature, actor: repo.monolith_actor, enabled: true)
    end

    it "calls the remote feature flag and returns true for the repo" do
      expect(monolith_features_client).to receive(:feature_enabled?).
        with(feature: :my_awesome_feature, actor: repo.monolith_actor, use_cache: true)

      expect(monolith_feature_enabled?(actor: repo, feature: :my_awesome_feature)).to be true
    end

    it "instruments the call correctly for the repo" do
      expect(MetricsClient).to receive(:distribution).with(
        "monolith_feature_flag_duration_seconds",
        anything,
        tags: {
          feature: :my_awesome_feature,
          actor_class: "repo",
          feature_enabled: true,
          response: :ok,
        }
      )

      monolith_feature_enabled?(actor: repo, feature: :my_awesome_feature)
    end
  end

  describe "for an account" do
    before do
      stub_monolith_feature(:my_awesome_feature, actor: account.monolith_actor, enabled: true)
    end

    it "calls the remote feature flag and returns true for the account" do
      expect(monolith_features_client).to receive(:feature_enabled?).
        with(feature: :my_awesome_feature, actor: account.monolith_actor, use_cache: true)

      expect(monolith_feature_enabled?(actor: account, feature: :my_awesome_feature)).to be true
    end

    it "instruments the call correctly for the account" do
      expect(MetricsClient).to receive(:distribution).with(
        "monolith_feature_flag_duration_seconds",
        anything,
        tags: {
          feature: :my_awesome_feature,
          actor_class: "account",
          feature_enabled: true,
          response: :ok,
        }
      )

      monolith_feature_enabled?(actor: account, feature: :my_awesome_feature)
    end
  end

  describe "for a global feature check" do
    before do
      stub_monolith_feature(:my_awesome_feature, actor: nil, enabled: true)
    end

    it "calls the remote feature flag and returns true" do
      expect(monolith_features_client).to receive(:feature_enabled?).
        with(feature: :my_awesome_feature, actor: nil, use_cache: true)

      expect(monolith_feature_enabled?(actor: nil, feature: :my_awesome_feature)).to be true
    end

    it "instruments the call correctly" do
      expect(MetricsClient).to receive(:distribution).with(
        "monolith_feature_flag_duration_seconds",
        anything,
        tags: {
          feature: :my_awesome_feature,
          actor_class: "global",
          feature_enabled: true,
          response: :ok,
        }
      )

      monolith_feature_enabled?(actor: nil, feature: :my_awesome_feature)
    end
  end

  describe "when the monolith throws an exception" do
    before do
      stub_monolith_error(:my_awesome_feature, actor: repo.monolith_actor)
    end

    it "returns false for the check" do
      expect(monolith_feature_enabled?(actor: repo, feature: :my_awesome_feature)).to be false
    end

    it "notices the error" do
      expect(Dependabot::Exceptions).to receive(:report!).with(an_instance_of(FeatureFlags::Client::Error))

      monolith_feature_enabled?(actor: repo, feature: :my_awesome_feature)
    end

    it "instruments the check" do
      expect(MetricsClient).to receive(:distribution).with(
        "monolith_feature_flag_duration_seconds",
        anything,
        tags: {
          feature: :my_awesome_feature,
          actor_class: "repo",
          feature_enabled: false,
          response: :error,
        }
      )

      monolith_feature_enabled?(actor: repo, feature: :my_awesome_feature)
    end
  end

  describe "when the monolith throws an exception and fail_state is true" do
    before do
      stub_monolith_error(:my_awesome_feature, actor: repo.monolith_actor)
    end

    it "returns true for the check" do
      expect(monolith_feature_enabled?(actor: repo, feature: :my_awesome_feature, fail_state: true)).
        to be true
    end

    it "instruments the check" do
      expect(MetricsClient).to receive(:distribution).with(
        "monolith_feature_flag_duration_seconds",
        anything,
        tags: {
          feature: :my_awesome_feature,
          actor_class: "repo",
          feature_enabled: true,
          response: :error,
        }
      )

      monolith_feature_enabled?(actor: repo, feature: :my_awesome_feature, fail_state: true)
    end
  end

  describe "when the monolith throws an exception and fail_state is :error" do
    before do
      stub_monolith_error(:my_awesome_feature, actor: repo.monolith_actor)
    end

    it "returns true for the check" do
      expect { monolith_feature_enabled?(actor: repo, feature: :my_awesome_feature, fail_state: :error) }.
        to raise_error(FeatureFlags::Client::Error)
    end

    it "instruments the check" do
      expect(MetricsClient).to receive(:distribution).with(
        "monolith_feature_flag_duration_seconds",
        anything,
        tags: {
          feature: :my_awesome_feature,
          actor_class: "repo",
          feature_enabled: false,
          response: :error,
        }
      )

      begin
        monolith_feature_enabled?(actor: repo, feature: :my_awesome_feature, fail_state: :error)
      rescue FeatureFlags::Client::Error
        # nothing to do
      end
    end
  end
end
