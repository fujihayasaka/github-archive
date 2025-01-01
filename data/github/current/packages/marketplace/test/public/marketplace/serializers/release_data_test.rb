# typed: true
# frozen_string_literal: true

require "test_helper"

class Marketplace::Serializers::ReleaseDataTest < GitHub::TestCase
  context "#call" do
    context "selectedRelease" do
      context "when selected_release is nil" do
        test "returns nil" do
          result = Marketplace::Serializers::ReleaseData.new(
            selected_release: nil, latest_release: build_stubbed(:release), releases: Release.none
          ).call

          assert_nil result[:selectedRelease]
        end
      end

      context "when selected_release is not nil" do
        test "returns the serialized selected release" do
          selected_release = build_stubbed(:release, tag_name: "v1.0.0", name: "Release 1.0.0", prerelease: true)
          result = Marketplace::Serializers::ReleaseData.new(
            selected_release: selected_release, latest_release: build_stubbed(:release), releases: Release.none
          ).call

          assert_equal({ tagName: "v1.0.0", name: "Release 1.0.0", isPrerelease: true }, result[:selectedRelease])
        end
      end
    end

    context "latestRelease" do
      test "returns the serialized latest release" do
        latest_release = build_stubbed(:release, tag_name: "v1.0.0", name: "Release 1.0.0", prerelease: true)
        result = Marketplace::Serializers::ReleaseData.new(
          selected_release: nil, latest_release: latest_release, releases: Release.none
        ).call

        assert_equal({ tagName: "v1.0.0", name: "Release 1.0.0", isPrerelease: true }, result[:latestRelease])
      end
    end

    context "releases" do
      context "when there are no releases" do
        test "returns an empty array" do
          result = Marketplace::Serializers::ReleaseData.new(
            selected_release: nil, latest_release: build_stubbed(:release), releases: Release.none
          ).call

          assert_equal [], result[:releases]
        end
      end

      context "when there are releases" do
        test "returns the serialized releases" do
          create(:release, :skip_validation, tag_name: "v1.0.0", name: "Release 1.0.0", prerelease: true)
          create(:release, :skip_validation, tag_name: "v1.1.0", name: "Release 1.1.0", prerelease: false)

          result = Marketplace::Serializers::ReleaseData.new(
            selected_release: nil, latest_release: build_stubbed(:release), releases: Release.all
          ).call

          assert_equal [
            { tagName: "v1.0.0", name: "Release 1.0.0", isPrerelease: true },
            { tagName: "v1.1.0", name: "Release 1.1.0", isPrerelease: false }
          ].sort_by { |release| release[:tagName] }, result[:releases].sort_by { |release| release[:tagName] }
        end
      end
    end
  end
end
