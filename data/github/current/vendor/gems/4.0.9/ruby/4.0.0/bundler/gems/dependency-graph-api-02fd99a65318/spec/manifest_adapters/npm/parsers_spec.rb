require "rails_helper"

describe ManifestAdapters::Npm::Parsers do
  it "correctly identifies malformed dependencies" do
    expect(described_class.is_dependency_malformed(package_name: :invalid_name, requirements: "valid_requirement")).to be(true)
    expect(described_class.is_dependency_malformed(package_name: "valid_name", requirements: 1)).to be(true)
    expect(described_class.is_dependency_malformed(package_name: "  \t\n", requirements: "valid_requirement")).to be(true)
    expect(described_class.is_dependency_malformed(
      package_name: "prefix-#{'a'*ManifestAdapters::Npm::Parsers::MAX_NPM_PACKAGE_NAME_LENGTH}",
      requirements: "valid_requirement")
    ).to be(true)
    expect(described_class.is_dependency_malformed(package_name: "valid_name", requirements: "valid_requirement")).to be(false)
  end
end
