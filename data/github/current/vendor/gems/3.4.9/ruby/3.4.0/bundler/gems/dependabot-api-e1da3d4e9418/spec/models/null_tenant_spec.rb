# frozen_string_literal: true

require "rails_helper"

RSpec.describe NullTenant do
  describe "#id" do
    it "returns zero" do
      expect(described_class.new.id).to be_zero
    end
  end

  describe "#github_id" do
    it "returns zero" do
      expect(described_class.new.github_id).to be_zero
    end
  end

  describe "#shortcode" do
    it "returns an empty string" do
      expect(described_class.new.shortcode).to eq("")
    end
  end

  describe "slug" do
    it "returns an empty string" do
      expect(described_class.new.slug).to eq("")
    end
  end
end
