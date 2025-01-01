require "rails_helper"
require "manifest_adapters"

describe "pubspec.yaml parsing" do
  def manifest(attributes = {})
    ::ManifestAdapters.parse(**{
      git_ref: "dbfa1c668d29e05c776a16d0a483cd8927613050",
      github_repository_id: 300,
      filename: "pubspec.yaml",
      path: "/",
      content: file_fixture("pubspec.yaml").read,
      pushed_at: Time.new(2022, 9, 1),
      fork: false,
      visibility_private: false
    }.merge(attributes))
  end

  it "parses metadata" do
    expect(manifest.malformed?).to be_falsey
    expect(manifest.dependencies).to_not be_nil
  end

  it "parses .yml files" do
    yml = manifest(filename: "pubspec.yml")

    expect(manifest.malformed?).to be_falsey
    expect(manifest.dependencies).to_not be_nil
  end

  it "parses runtime dependencies" do
    # device_info_plus dependency is specified in the "dependencies" section. It should be treated as a scope of runtime.
    device_info_plus_dep = manifest.dependencies.find { |dep| dep.package_name == "device_info_plus" }
    expect(device_info_plus_dep).to be_an_instance_of(ManifestAdapters::Manifest::Dependency)
    expect(device_info_plus_dep.package_name).to eq("device_info_plus")
    expect(device_info_plus_dep.requirements).to eq(">= 4.0.0, < 5.0.0")
    expect(device_info_plus_dep.raw_requirements).to eq("^4.0.0")
    expect(device_info_plus_dep.scope).to eq(Types::Scope[:runtime])
    expect(device_info_plus_dep.malformed?).to be_falsey

    # transmogrify dependency is specified in the "dependencies" section with a version key. It should be treated as a scope of runtime.
    transmogrify_dep = manifest.dependencies.find { |dep| dep.package_name == "transmogrify" }
    expect(transmogrify_dep).to be_an_instance_of(ManifestAdapters::Manifest::Dependency)
    expect(transmogrify_dep.package_name).to eq("transmogrify")
    expect(transmogrify_dep.requirements).to eq(">= 1.4.0, < 2.0.0")
    expect(transmogrify_dep.raw_requirements).to eq("^1.4.0")
    expect(transmogrify_dep.scope).to eq(Types::Scope[:runtime])
    expect(transmogrify_dep.malformed?).to be_falsey

    # hosted_dependency dependency is specified in the "dependencies" section but lacks a version as it is hosted instead. It should be ignored.
    hosted_dependency_dep = manifest.dependencies.select { |dep| dep.package_name == "hosted_dependency" }
    expect(hosted_dependency_dep.size).to eq(0)

    # git_dependency dependency is specified in the "dependencies" section but we lack a way to parse a version with high confidence. It should be ignored.
    git_dependency_dep = manifest.dependencies.select { |dep| dep.package_name == "git_dependency" }
    expect(git_dependency_dep.size).to eq(0)

    # The pubspec.yaml includes 5 dependencies of scope runtime.
    runtime_deps = manifest.dependencies.select { |dep| dep.scope == Types::Scope[:runtime] }
    expect(runtime_deps.size).to eq(5)
  end

  it "parses runtime dependencies whose version has been overridden" do
    # recase dependency is specified in the "dependency_overrides" section. It should be treated as a scope of runtime.
    recase_overriden_dep = manifest.dependencies.find { |dep| dep.package_name == "recase" }
    expect(recase_overriden_dep).to be_an_instance_of(ManifestAdapters::Manifest::Dependency)
    expect(recase_overriden_dep.package_name).to eq("recase")
    expect(recase_overriden_dep.requirements).to eq("= 5.2.1")
    expect(recase_overriden_dep.raw_requirements).to eq("5.2.1")
    expect(recase_overriden_dep.scope).to eq(Types::Scope[:runtime])
    expect(recase_overriden_dep.malformed?).to be_falsey
  end

  it "parses development dependencies" do
    # rexios_lints dependency is specified in the "dev_dependencies" section. It should be treated as a scope of development.
    rexios_lints_dep = manifest.dependencies.find { |dep| dep.package_name == "rexios_lints" }
    expect(rexios_lints_dep).to be_an_instance_of(ManifestAdapters::Manifest::Dependency)
    expect(rexios_lints_dep.package_name).to eq("rexios_lints")
    expect(rexios_lints_dep.requirements).to eq(">= 3.0.0, < 4.0.0")
    expect(rexios_lints_dep.raw_requirements).to eq("^3.0.0")
    expect(rexios_lints_dep.scope).to eq(Types::Scope[:development])
    expect(rexios_lints_dep.malformed?).to be_falsey

    # The pubspec.yaml includes 1 dependency of scope development.
    development_deps = manifest.dependencies.select { |dep| dep.scope == Types::Scope[:development] }
    expect(development_deps.size).to eq(1)
  end

  it "skips bad entries when processing invalid manifest dependencies" do
    bad_manifest_data = <<~YAML
    name: polar
    description: This is a Dart plugin wrapper for the Polar SDK on Android and iOS
    version: 2.2.0
    homepage: https://github.com/Rexios80/polar

    environment:
      sdk: ">=2.15.0 <3.0.0"
      flutter: ">=1.20.0"

    dependencies:
      flutter:
        sdk: flutter

      flutter_plugin_android_lifecycle: ^no23n45sense
      permission_handler: ^10.0.0
      device_info_plus: ^4.0.0
      recase: ^4.0.0

    dev_dependencies:
      flutter_test:
        sdk: flutter

      rexios_lints: ^3.0.0

    flutter:
      plugin:
        platforms:
          android:
            package: dev.rexios.polar
            pluginClass: PolarPlugin
          ios:
            pluginClass: PolarPlugin
    YAML

    got = manifest(content: bad_manifest_data)
    expect(got.malformed?).to be_falsey, "expected to succeed by skipping corrupt manifest dependency: #{bad_manifest_data}"
    expect(got.dependencies.length).to eq 4
    expect(got.dependencies.select(&:malformed?)).to be_empty
  end
end
