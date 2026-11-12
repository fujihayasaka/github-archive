# frozen_string_literal: true

require "rails_helper"

# Stubs out the monolith's FeatureFlag client to always return false by default.
#
RSpec.shared_context "monolith feature flag helpers" do
  let(:monolith_features_client) do
    instance_double(FeatureFlags::Client, feature_enabled?: false)
  end

  before do
    allow(FeatureFlags).to receive(:feature_flags_client) { monolith_features_client }
  end

  def stub_monolith_feature(feature, actor: nil, use_cache: true, enabled: true)
    allow(monolith_features_client).
      to receive(:feature_enabled?).
      with(feature: feature, actor: be_feature_actor(actor), use_cache: use_cache).
      and_return(enabled)
  end

  def stub_monolith_error(feature, actor: nil, use_cache: true)
    allow(monolith_features_client).
      to receive(:feature_enabled?).
      with(feature: feature, actor: be_feature_actor(actor), use_cache: use_cache).
      and_raise(FeatureFlags::Client::Error, "lp0 on fire")
  end
end

# FeatureFlags::Actor does not implement equality
RSpec::Matchers.define :be_feature_actor do |expected|
  description do
    "actor is #{expected&.twirp_actor_id}"
  end

  match do |actual|
    expected&.twirp_actor_id == actual&.twirp_actor_id
  end
end

RSpec.configure do |config|
  config.include_context "monolith feature flag helpers"
end
