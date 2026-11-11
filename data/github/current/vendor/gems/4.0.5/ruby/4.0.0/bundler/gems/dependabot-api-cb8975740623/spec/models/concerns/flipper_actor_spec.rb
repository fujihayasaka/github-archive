# frozen_string_literal: true

require "rails_helper"

RSpec.describe FlipperActor do
  subject(:actor) { TestActor.new(id: 99) }

  let(:test_class) do
    Struct.new(:id) do
      include FlipperActor
    end
  end

  before do
    stub_const("TestActor", test_class)
  end

  describe "#flipper_id" do
    specify do
      expect(actor.flipper_id).to eq("TestActor:99")
    end
  end

  describe "#feature_enabled?" do
    context "when feature is enabled" do
      before do
        Dependabot.flipper["foo"].enable_actor(actor) # rubocop:disable Dependabot/NoLocalFeatureFlags
      end

      it "returns true" do
        expect(Dependabot.flipper["foo"].enabled?(actor)).to eq(true) # rubocop:disable Dependabot/NoLocalFeatureFlags
        expect(actor.feature_enabled?("foo")).to eq(true)
      end
    end

    context "when feature is not enabled" do
      it "returns false" do
        expect(Dependabot.flipper["bar"].enabled?(actor)).to eq(false) # rubocop:disable Dependabot/NoLocalFeatureFlags
        expect(actor.feature_enabled?("bar")).to eq(false)
      end
    end
  end

  describe "#enable_feature" do
    specify do
      # rubocop:disable Dependabot/NoLocalFeatureFlags
      expect { actor.enable_feature("foo") }.
        to change { Dependabot.flipper["foo"].enabled?(actor) }.
        # rubocop:enable Dependabot/NoLocalFeatureFlags
        to(true)
    end
  end

  describe "#disable_feature" do
    before do
      Dependabot.flipper["foo"].enable_actor(actor) # rubocop:disable Dependabot/NoLocalFeatureFlags
    end

    specify do
      # rubocop:disable Dependabot/NoLocalFeatureFlags
      expect { actor.disable_feature("foo") }.
        to change { Dependabot.flipper["foo"].enabled?(actor) }.
        # rubocop:enable Dependabot/NoLocalFeatureFlags
        to(false)
    end
  end

  it "increments feature flag call metric" do
    {
      feature_enabled?: "query",
      enable_feature: "enable",
      disable_feature: "disable",
    }.each do |method_name, operation_name|
      actor.public_send(method_name, "foo")

      tags = {
        "feature_flag.key" => "foo",
        "feature_flag.operation" => operation_name,
      }
      expect(MetricsClient).to have_received(:increment).with("feature_flag.call", tags: tags)
    end
  end
end
