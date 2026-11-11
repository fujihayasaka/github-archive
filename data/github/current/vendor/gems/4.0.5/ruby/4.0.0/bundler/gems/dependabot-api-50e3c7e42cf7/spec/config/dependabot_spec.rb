# frozen_string_literal: true

require "rails_helper"

RSpec.describe Dependabot do
  describe ".enterprise?" do
    it "returns true when the enterprise ENV_VAR is truthy" do
      allow(Prius).to receive(:get).with(:enterprise).and_return(true)

      expect(described_class.enterprise?).to be true
    end

    it "returns false when the enterprise ENV_VAR is falsey" do
      allow(Prius).to receive(:get).with(:enterprise).and_return(false)

      expect(described_class.enterprise?).to be false
    end
  end

  describe ".proxima?" do
    it "returns true when the PROXIMA_STAMP ENV var is present" do
      allow(Prius).to receive(:get).with(:proxima_stamp).and_return(SecureRandom.uuid)

      expect(described_class.proxima?).to be true
    end

    it "returns false when the PROXIMA_STAMP ENV var is blank" do
      allow(Prius).to receive(:get).with(:proxima_stamp).and_return("")

      expect(described_class.proxima?).to be false
    end
  end

  describe ".redis" do
    it "uses authentication when REDIS_PASSWORD ENV var is present" do
      allow(Prius).to receive(:get).with(:redis_password).and_return("redis_password")

      redis = described_class.redis

      expect(redis._client.password).to be_present
    end

    it "doesn't authenticate when REDIS_PASSWORD ENV var is missing" do
      allow(Prius).to receive(:get).with(:redis_password).and_return("")

      redis = described_class.redis

      expect(redis._client.password).to be_nil
    end
  end
end
