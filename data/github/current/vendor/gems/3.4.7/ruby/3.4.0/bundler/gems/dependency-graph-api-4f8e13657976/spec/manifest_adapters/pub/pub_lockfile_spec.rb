require "rails_helper"
require "manifest_adapters"

describe "pubspec.lock parsing" do
  def manifest(attributes = {})
    ::ManifestAdapters.parse(**{
      git_ref: "dbfa1c668d29e05c776a16d0a483cd8927613050",
      github_repository_id: 300,
      filename: "pubspec.lock",
      path: "pubspec.lock",
      content: file_fixture("pubspec.lock").read,
      pushed_at: Time.new(2022, 9, 1),
      fork: false,
      visibility_private: false
    }.merge(attributes))
  end

  it "parses metadata" do
    expect(manifest.malformed?).to be_falsey
    expect(manifest.dependencies).to_not be_nil
  end

  it "parses dependencies" do
    # Async dependency is a hosted, transitive dependency. It should be treated as a scope of runtime.
    async_dep = manifest.dependencies.find { |dep| dep.package_name == "async" }
    expect(async_dep).to be_an_instance_of(ManifestAdapters::Manifest::Dependency)
    expect(async_dep.package_name).to eq("async")
    expect(async_dep.requirements).to eq("= 2.9.0")
    expect(async_dep.raw_requirements).to eq("2.9.0")
    expect(async_dep.scope).to eq(Types::Scope[:runtime])
    expect(async_dep.malformed?).to be_falsey

    # device_info_plus dependency is a hosted, direct main dependency. It should be treated as a scope of runtime.
    device_info_plus_dep = manifest.dependencies.find { |dep| dep.package_name == "device_info_plus" }
    expect(device_info_plus_dep).to be_an_instance_of(ManifestAdapters::Manifest::Dependency)
    expect(device_info_plus_dep.package_name).to eq("device_info_plus")
    expect(device_info_plus_dep.requirements).to eq("= 4.1.2")
    expect(device_info_plus_dep.raw_requirements).to eq("4.1.2")
    expect(device_info_plus_dep.scope).to eq(Types::Scope[:runtime])
    expect(device_info_plus_dep.malformed?).to be_falsey

    # rexios_lints dependency is a hosted, direct dev dependency. It should be treated as a scope of development.
    rexios_lints_dep = manifest.dependencies.find { |dep| dep.package_name == "rexios_lints" }
    expect(rexios_lints_dep).to be_an_instance_of(ManifestAdapters::Manifest::Dependency)
    expect(rexios_lints_dep.package_name).to eq("rexios_lints")
    expect(rexios_lints_dep.requirements).to eq("= 3.0.0")
    expect(rexios_lints_dep.raw_requirements).to eq("3.0.0")
    expect(rexios_lints_dep.scope).to eq(Types::Scope[:development])
    expect(rexios_lints_dep.malformed?).to be_falsey

    # Only dependencies with scope hosted or git are allowed, sky_engine is of scope sdk.
    sky_engine_dep_found = manifest.dependencies.find { |dep| dep.package_name == "sky_engine" }
    expect(sky_engine_dep_found).to be_nil
  end

  it "handles invalid requirements" do
    content = <<~YAML
    packages:
      async:
        dependency: transitive
        description:
          named: async
          url: "https://pub.dartlang.org"
        source: hosted
        version: "2.9.0"
      boolean_selector:
        dependency: transitive
        description:
          named: boolean_selector
          url: "https://pub.dartlang.org"
        source: hosted
        version: "2.1.0"
    sdks:
      dart: ">=2.17.0 <3.0.0"
      flutter: ">=2.8.0"
    YAML

    # manifest.dependencies rejects all malformed dependencies on return
    expect(manifest(content: content).dependencies).to be_empty
  end

  it "handles parsing errors gracefully" do
    content = "blah: blah\n stuff: blah\n\n\nmorestuff: blah" # syntax that'll break Psych
    expect(manifest(content: content).malformed?).to be_truthy
  end

  it "handles incorrect actions syntax gracefully" do
    # malformed manifest because package names would parse as an array
    content_1 = <<~YAML
    packages:
      - async:
        dependency: transitive
        description:
          name: async
          url: "https://pub.dartlang.org"
        source: hosted
        version: "2.9.0"
      - boolean_selector:
        dependency: transitive
        description:
          name: boolean_selector
          url: "https://pub.dartlang.org"
        source: hosted
        version: "2.1.0"
    sdks:
      dart: ">=2.17.0 <3.0.0"
      flutter: ">=2.8.0"
    YAML

    parsed_content_1 = manifest(content: content_1)
    expect(parsed_content_1.dependencies).to be_empty
    expect(parsed_content_1.malformed?).to be_truthy

    # lack of indentation for package names
    content_2 = <<~YAML
    packages:
    async:
      dependency: transitive
      description:
        name: async
        url: "https://pub.dartlang.org"
      source: hosted
      version: "2.9.0"
    boolean_selector:
      dependency: transitive
      description:
        name: boolean_selector
        url: "https://pub.dartlang.org"
      source: hosted
      version: "2.1.0"
    sdks:
      dart: ">=2.17.0 <3.0.0"
      flutter: ">=2.8.0"
    YAML

    parsed_content_2 = manifest(content: content_2)
    expect(parsed_content_2.dependencies).to be_empty
  end
end
