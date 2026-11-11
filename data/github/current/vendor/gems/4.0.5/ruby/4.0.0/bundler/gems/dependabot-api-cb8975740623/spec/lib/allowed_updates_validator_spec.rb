# frozen_string_literal: true

require "rails_helper"
require "allowed_updates_validator"

module Test
  AllowedUpdatesValidatable = Struct.new(:allowed_updates) do
    include ActiveModel::Validations

    validates :allowed_updates, allowed_updates: true
  end
end

RSpec.describe AllowedUpdatesValidator, type: :model do
  subject { Test::AllowedUpdatesValidatable.new(allowed_updates) }

  let(:allowed_updates) { [{ "update_type" => "all" }] }

  it { is_expected.to be_valid }

  context "with symbol keys" do
    let(:allowed_updates) { [{ update_type: "all" }] }

    it { is_expected.to be_valid }
  end

  context "with an invalid key" do
    let(:allowed_updates) { [{ "update_type" => "all", "bad_key" => "a" }] }

    it { is_expected.not_to be_valid }
  end

  context "with an invalid array element" do
    let(:allowed_updates) { [{ "update_type" => "all" }, nil] }

    it { is_expected.not_to be_valid }
  end

  context "with a hash (not an array)" do
    let(:allowed_updates) { { "update_type" => "all" } }

    it { is_expected.not_to be_valid }
  end

  context "with an invalid update type" do
    let(:allowed_updates) { [{ "update_type" => "best" }] }

    it { is_expected.not_to be_valid }
  end

  context "with an empty array" do
    let(:allowed_updates) { [] }

    it { is_expected.not_to be_valid }
  end

  context "with an empty hash" do
    let(:allowed_updates) { [{ "update_type" => "all" }, {}] }

    it { is_expected.not_to be_valid }
  end

  context "with a valid dependency_type" do
    let(:allowed_updates) { [{ "dependency_type" => "indirect" }] }

    it { is_expected.to be_valid }
  end

  context "with a invalid dependency_type" do
    let(:allowed_updates) { [{ "dependency_type" => "none" }] }

    it { is_expected.not_to be_valid }
  end

  context "with a valid dependency_name" do
    let(:allowed_updates) { [{ "dependency_name" => "dependabot-core" }] }

    it { is_expected.to be_valid }
  end

  context "with a invalid dependency_name" do
    let(:allowed_updates) { [{ "dependency_name" => nil }] }

    it { is_expected.not_to be_valid }
  end

  context "with valid update_types" do
    let(:allowed_updates) do
      [{ "dependency_name" => "rails", "update_types" => %w(version-update:semver-minor version-update:semver-patch) }]
    end

    it { is_expected.to be_valid }
  end

  context "with invalid update_types values" do
    let(:allowed_updates) do
      [{ "dependency_name" => "rails", "update_types" => %w(version-update:semver-invalid) }]
    end

    it { is_expected.not_to be_valid }
  end

  context "with update_types that is not an array" do
    let(:allowed_updates) do
      [{ "dependency_name" => "rails", "update_types" => "version-update:semver-major" }]
    end

    it { is_expected.not_to be_valid }
  end

  context "with update_types as an empty array" do
    let(:allowed_updates) do
      [{ "dependency_name" => "rails", "update_types" => [] }]
    end

    it { is_expected.not_to be_valid }
  end

  context "with update_types exceeding maximum items" do
    let(:allowed_updates) do
      [{
        "dependency_name" => "rails",
        "update_types" => %w(
          version-update:semver-major
          version-update:semver-minor
          version-update:semver-patch
          version-update:semver-patch
        ),
      }]
    end

    it { is_expected.not_to be_valid }
  end
end
