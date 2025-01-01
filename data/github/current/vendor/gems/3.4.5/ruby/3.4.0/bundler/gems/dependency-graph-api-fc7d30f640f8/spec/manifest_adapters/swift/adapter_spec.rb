require "rails_helper"

describe ManifestAdapters::Swift::Adapter do
  it "recognizes only Package.resolved manifests" do
    expect(described_class.test(filename: "Package.resolved", path: nil)).to be_truthy
    expect(described_class.test(filename: "Package.resolved", path: "Packages/SomePackage")).to be_truthy

    # TODO: verify if the manifest name should be case insensitive
    expect(described_class.test(filename: "package.resolved", path: nil)).to be_falsey
  end
end
