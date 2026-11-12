# frozen_string_literal: true

require "rails_helper"
require "ecosystems"

RSpec.describe Ecosystems do
  describe ".beta?" do
    let(:beta_ecosystems) do
      [
        PackageManagers::CONDA,
        PackageManagers::JULIA,
        PackageManagers::OPENTOFU,
      ]
    end
    let(:ga_ecosystems) { PackageManagers::ALL - beta_ecosystems }

    it "returns the correct value" do
      ga_ecosystems.each do |ecosystem|
        expect(described_class.beta?(ecosystem)).to be(false)
      end

      beta_ecosystems.each do |ecosystem|
        expect(described_class.beta?(ecosystem)).to be(true)
      end
    end

    it "checks if the package manager is in the BETA array" do
      stub_const("Ecosystems::BETA", ["beta_ecosystem"])

      expect(described_class.beta?("irrelevant")).to be(false)
      expect(described_class.beta?("beta_ecosystem")).to be(true)

      stub_const("Ecosystems::BETA", [])
      expect(described_class.beta?("irrelevant")).to be(false)
    end
  end
end
