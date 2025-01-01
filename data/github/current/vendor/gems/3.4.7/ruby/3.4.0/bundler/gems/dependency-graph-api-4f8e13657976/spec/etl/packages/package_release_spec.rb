require "rails_helper"

describe Packages::PackageRelease do
  describe "validations" do
    it "is require a valid package managers" do
      valid = described_class.new(
        package_manager: :rubygems,
        package_name: "rails",
        version: "3.0.0",
      )
      expect(valid).to be_valid

      invalid = described_class.new(
        package_manager: :not_real,
        package_name: "rails",
        version: "3.0.0",
      )
      expect(invalid).to_not be_valid
    end
  end
end

describe Packages::PackageReleaseSerializer do
  it "serializes/deserializes non-scalar attributes" do
    release = Packages::PackageRelease.new(
      package_manager: :rubygems,
      package_name: "some_package_name",
      version: "0.0.1",
      built_at: Time.iso8601("2019-11-15T00:00:11Z"),
      published_at: Time.iso8601("2019-11-15T00:00:22Z"),
      unpublished_at: Time.iso8601("2019-11-15T00:00:33Z"),
    )

    serialized_release = described_class.serialize(release)
    deserialized_release = described_class.deserialize(serialized_release)

    expect(deserialized_release.package_manager).to be_a(Types::PackageManager)
    expect(deserialized_release.built_at).to be_a(Time)
    expect(deserialized_release.published_at).to be_a(Time)
    expect(deserialized_release.unpublished_at).to be_a(Time)

    expect(deserialized_release.package_manager).to eq(Types::PackageManager[:rubygems])
    expect(deserialized_release.built_at).to eq(Time.iso8601("2019-11-15T00:00:11Z"))
    expect(deserialized_release.published_at).to eq(Time.iso8601("2019-11-15T00:00:22Z"))
    expect(deserialized_release.unpublished_at).to eq(Time.iso8601("2019-11-15T00:00:33Z"))
  end

  it "safely serializes/deserializes nil values for non-scalar attributes" do
    release = Packages::PackageRelease.new(
      package_manager: nil,
      package_name: "some_package_name",
      version: "0.0.1",
      built_at: nil,
      published_at: nil,
      unpublished_at: nil,
    )

    serialized_release = described_class.serialize(release)
    deserialized_release = described_class.deserialize(serialized_release)

    expect(deserialized_release.package_manager).to be_nil
    expect(deserialized_release.built_at).to be_nil
    expect(deserialized_release.published_at).to be_nil
    expect(deserialized_release.unpublished_at).to be_nil
  end
end
