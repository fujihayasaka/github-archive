# frozen_string_literal: true
require "rails_helper"

def manifest_adapter_parse_file_fixture(fixture_name)
  ::ManifestAdapters.parse(
    git_ref: "78716382bd3de2dbf141643bbe40f93185b5d4c6",
    github_repository_id: 55,
    filename: fixture_name,
    path: "",
    content: file_fixture(fixture_name).read,
    pushed_at: Time.new(2019, 11, 1),
    fork: false,
    visibility_private: false,
  )
end

describe ManifestAdapters::Nuget::Parsers::Project do

  it "recognizes name when specified as metadata on PackageId" do
    parsed_manifest = manifest_adapter_parse_file_fixture("has_package_id.csproj")

    expect(parsed_manifest.dependent_name).to_not be_empty
    expect(parsed_manifest.dependent_name).to eq("Microsoft.AspNetCore.Antiforgery")
  end

  it "uses filename for name when not specified as metadata" do
    parsed_manifest = manifest_adapter_parse_file_fixture("Microsoft.AspNetCore.Routing.csproj")

    expect(parsed_manifest.dependent_name).to_not be_empty
    expect(parsed_manifest.dependent_name).to eq("Microsoft.AspNetCore.Routing")
  end

  it "recognizes versions as attributes" do
    parsed_manifest = manifest_adapter_parse_file_fixture("version_attributes.csproj")

    expect(parsed_manifest.dependencies).to_not be_empty
    expect(parsed_manifest.dependencies.count).to eq(3)
    parsed_manifest.dependencies.each do |dependency|
      expect(dependency.requirements).to_not be_nil
    end
  end

  # https://github.com/github/dependency-graph-api/issues/1350
  it "recognizes versions as elements" do
    parsed_manifest = manifest_adapter_parse_file_fixture("version_elements.csproj")

    expect(parsed_manifest.dependencies).to_not be_empty
    expect(parsed_manifest.dependencies.count).to eq(3)
    parsed_manifest.dependencies.each do |dependency|
      expect(dependency.requirements).to_not be_nil
    end
  end

  it "returns dependencies without versions with >= 0" do
    parsed_manifest = manifest_adapter_parse_file_fixture("no_versions.csproj")

    expect(parsed_manifest.dependencies).to_not be_empty
    expect(parsed_manifest.dependencies.count).to eq(3)
    parsed_manifest.dependencies.each do |dependency|
      expect(dependency.requirements).to eq(">= 0")
    end
  end
end
