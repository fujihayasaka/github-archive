# frozen_string_literal: true

require "rails_helper"

RSpec.describe BlockedDependency do
  let(:redis) { Dependabot.redis }

  let(:language) { Languages::JAVASCRIPT }
  let(:package_name) { "event-stream" }
  let(:version) { "3.3.6" }
  let(:reason) { "malware - flatmap-stream injection" }
  let(:blocked_by) { "security-incident-response" }

  before { redis.flushdb }
  after { redis.flushdb }

  describe ".create!" do
    it "stores a serialized block under the dep_block: key" do
      described_class.create!(
        language: language,
        package_name: package_name,
        version: version,
        reason: reason,
        blocked_by: blocked_by,
      )

      data = JSON.parse(redis.get("dep_block:javascript:event-stream:3.3.6"))
      expect(data).to include(
        "language" => language,
        "package_name" => package_name,
        "version" => version,
        "reason" => reason,
        "blocked_by" => blocked_by,
      )
    end

    it "records a blocked_at ISO-8601 timestamp" do
      described_class.create!(language: language, package_name: package_name, version: version)

      data = JSON.parse(redis.get("dep_block:javascript:event-stream:3.3.6"))
      expect(data["blocked_at"]).to match(/\A\d{4}-\d{2}-\d{2}T/)
    end

    it "applies the default 1-week TTL" do
      described_class.create!(language: language, package_name: package_name, version: version)

      ttl = redis.ttl("dep_block:javascript:event-stream:3.3.6")
      expect(ttl).to be_between(1.week.to_i - 5, 1.week.to_i)
    end

    it "supports a custom TTL as an Integer" do
      described_class.create!(
        language: language, package_name: package_name, version: version, ttl: 3600,
      )

      expect(redis.ttl("dep_block:javascript:event-stream:3.3.6")).to be_between(3590, 3600)
    end

    it "supports a custom TTL as an ActiveSupport::Duration" do
      described_class.create!(
        language: language, package_name: package_name, version: version, ttl: 2.days,
      )

      expect(redis.ttl("dep_block:javascript:event-stream:3.3.6")).
        to be_between(2.days.to_i - 5, 2.days.to_i)
    end

    it "returns the stored Block" do
      block = described_class.create!(
        language: language, package_name: package_name, version: version, reason: reason,
      )

      expect(block).to be_a(described_class)
      expect(block.language).to eq(language)
      expect(block.package_name).to eq(package_name)
      expect(block.version).to eq(version)
      expect(block.reason).to eq(reason)
    end

    it "raises InvalidLanguageError for an unknown language" do
      expect do
        described_class.create!(
          language: "made_up", package_name: package_name, version: version,
        )
      end.to raise_error(BlockedDependency::InvalidLanguageError, /made_up/)
    end

    it "accepts a Dependabot ignore-style version range" do
      expect do
        described_class.create!(
          language: language, package_name: package_name, version: ">= 3.0, < 4.0",
        )
      end.not_to raise_error
    end

    it "raises InvalidVersionRequirementError for a malformed version requirement" do
      expect do
        described_class.create!(
          language: language, package_name: package_name, version: "not-a-version!!",
        )
      end.to raise_error(BlockedDependency::InvalidVersionRequirementError)
    end
  end

  describe ".exists?" do
    it "returns true when a version is blocked" do
      described_class.create!(language: language, package_name: package_name, version: version)

      expect(
        described_class.exists?(language: language, package_name: package_name, version: version),
      ).to be(true)
    end

    it "returns false when a version is not blocked" do
      expect(
        described_class.exists?(language: language, package_name: package_name, version: "9.9.9"),
      ).to be(false)
    end

    it "is version-specific" do
      described_class.create!(language: language, package_name: package_name, version: "3.3.6")

      expect(
        described_class.exists?(language: language, package_name: package_name, version: "3.3.5"),
      ).to be(false)
    end
  end

  describe ".find" do
    it "returns the deserialized Block" do
      described_class.create!(
        language: language,
        package_name: package_name,
        version: version,
        reason: reason,
        blocked_by: blocked_by,
      )

      block = described_class.find(
        language: language, package_name: package_name, version: version,
      )

      expect(block).to be_a(described_class)
      expect(block.reason).to eq(reason)
      expect(block.blocked_by).to eq(blocked_by)
    end

    it "returns nil when the version is not blocked" do
      expect(
        described_class.find(language: language, package_name: package_name, version: version),
      ).to be_nil
    end
  end

  describe ".destroy!" do
    it "removes the block and returns true" do
      described_class.create!(language: language, package_name: package_name, version: version)

      expect(
        described_class.destroy!(language: language, package_name: package_name, version: version),
      ).to be(true)
      expect(
        described_class.exists?(language: language, package_name: package_name, version: version),
      ).to be(false)
    end

    it "returns false when no block exists" do
      expect(
        described_class.destroy!(language: language, package_name: package_name, version: "9.9.9"),
      ).to be(false)
    end
  end

  describe ".ttl" do
    it "returns the remaining TTL in seconds" do
      described_class.create!(
        language: language, package_name: package_name, version: version, ttl: 3600,
      )

      expect(
        described_class.ttl(language: language, package_name: package_name, version: version),
      ).to be_between(3590, 3600)
    end

    it "returns nil when the version is not blocked" do
      expect(
        described_class.ttl(language: language, package_name: package_name, version: "9.9.9"),
      ).to be_nil
    end
  end

  describe "automatic expiry" do
    it "no longer reports a version as blocked once Redis has expired it" do
      described_class.create!(language: language, package_name: package_name, version: version)
      # simulate TTL expiry without sleeping
      redis.expire("dep_block:javascript:event-stream:3.3.6", 0)

      expect(
        described_class.exists?(language: language, package_name: package_name, version: version),
      ).to be(false)
      expect(
        described_class.find(language: language, package_name: package_name, version: version),
      ).to be_nil
    end
  end

  describe ".where" do
    it "returns all blocked versions for a single package" do
      described_class.create!(language: language, package_name: package_name, version: "3.3.6")
      described_class.create!(language: language, package_name: package_name, version: "3.3.5")
      described_class.create!(language: language, package_name: "other", version: "1.0.0")

      blocks = described_class.where(language: language, package_name: package_name)
      expect(blocks.map(&:version)).to contain_exactly("3.3.6", "3.3.5")
    end

    it "returns an empty array when nothing is blocked for the package" do
      expect(
        described_class.where(language: language, package_name: package_name),
      ).to eq([])
    end
  end

  describe ".all" do
    it "returns every block currently stored" do
      described_class.create!(language: Languages::JAVASCRIPT, package_name: "event-stream", version: "3.3.6")
      described_class.create!(language: Languages::RUBY, package_name: "rest-client", version: "1.6.13")

      blocks = described_class.all
      expect(blocks.size).to eq(2)
      languages = blocks.map(&:language).sort
      expect(languages).to eq([Languages::JAVASCRIPT, Languages::RUBY].sort)
    end
  end

  describe "key format" do
    it "uses the dep_block:<language>:<package_name>:<version> pattern" do
      expect(described_class.key_for(Languages::JAVASCRIPT, "event-stream", "3.3.6")).
        to eq("dep_block:javascript:event-stream:3.3.6")
    end
  end
end
