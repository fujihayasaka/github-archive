require "rails_helper"
require "manifest_adapters"

describe "uv.lock parsing" do
  def manifest(attributes = {})
    ::ManifestAdapters.parse(**{
      git_ref: "78716382bd3de2dbf141643bbe40f93185b5d4c6",
      github_repository_id: 105,
      filename: "uv.lock",
      path: "",
      content: file_fixture("uv.lock").read,
      pushed_at: Time.new(2021, 1, 1),
      fork: false,
      visibility_private: false
    }.merge(attributes))
  end

  it "parses metadata" do
    expect(manifest.malformed?).to be_falsey
    expect(manifest.dependencies).to_not be_nil
  end

  it "parses dependencies" do
    deps = manifest.dependencies
    anyio_dep = deps.find { |d| d.package_name == "anyio" }
    expect(anyio_dep).to be_an_instance_of(ManifestAdapters::Manifest::Dependency)
    expect(anyio_dep.package_name).to eq("anyio")
    expect(anyio_dep.requirements).to eq("= 3.7.0")
    expect(anyio_dep.raw_requirements).to eq("3.7.0")
    expect(anyio_dep.scope).to eq(Types::Scope[:runtime])
    expect(anyio_dep.malformed?).to be_falsey
  end

  it "parses all registry dependencies" do
    deps = manifest.dependencies
    package_names = deps.map(&:package_name)
    expect(package_names).to include("anyio", "sniffio", "charset-normalizer", "pytest", "iniconfig", "packaging", "pluggy")
    expect(package_names.count).to eq(7)
  end

  it "identifies dev dependencies from dependency-groups" do
    deps = manifest.dependencies
    pytest_dep = deps.find { |d| d.package_name == "pytest" }
    expect(pytest_dep.scope).to eq(Types::Scope[:development])
  end

  # NOTE: The following tests use inline TOML content rather than fixture files
  # to avoid triggering the license scanner on fake package names.

  it "does not include git-sourced dependencies" do
    content = <<~TOML
    version = 1
    requires-python = ">=3.12"

    [[package]]
    name = "requests"
    version = "2.31.0"
    source = { registry = "https://pypi.org/simple" }

    [[package]]
    name = "some-git-dep"
    version = "0.1.0"
    source = { git = "https://github.com/example/repo.git" }
    TOML

    deps = manifest(content: content).dependencies
    package_names = deps.map(&:package_name)

    expect(package_names).to include("requests")
    expect(package_names).not_to include("some-git-dep")
  end

  it "does not include path-sourced dependencies" do
    content = <<~TOML
    version = 1
    requires-python = ">=3.12"

    [[package]]
    name = "requests"
    version = "2.31.0"
    source = { registry = "https://pypi.org/simple" }

    [[package]]
    name = "some-path-dep"
    version = "0.2.0"
    source = { path = "./packages/local" }
    TOML

    deps = manifest(content: content).dependencies
    package_names = deps.map(&:package_name)

    expect(package_names).to include("requests")
    expect(package_names).not_to include("some-path-dep")
  end

  it "does not include editable-sourced dependencies" do
    content = <<~TOML
    version = 1
    requires-python = ">=3.12"

    [[package]]
    name = "requests"
    version = "2.31.0"
    source = { registry = "https://pypi.org/simple" }

    [[package]]
    name = "some-editable-dep"
    version = "0.3.0"
    source = { editable = "./src/mypackage" }
    TOML

    deps = manifest(content: content).dependencies
    package_names = deps.map(&:package_name)

    expect(package_names).to include("requests")
    expect(package_names).not_to include("some-editable-dep")
  end

  it "does not include virtual-sourced dependencies" do
    content = <<~TOML
    version = 1
    requires-python = ">=3.12"

    [[package]]
    name = "requests"
    version = "2.31.0"
    source = { registry = "https://pypi.org/simple" }

    [[package]]
    name = "myproject"
    version = "0.1.0"
    source = { virtual = "." }
    TOML

    deps = manifest(content: content).dependencies
    package_names = deps.map(&:package_name)

    expect(package_names).to include("requests")
    expect(package_names).not_to include("myproject")
  end

  it "handles invalid TOML" do
    manifest = manifest(content: "{")
    expect(manifest).to be_malformed
  end

  it "handles invalid requirements" do
    content = <<~TOML
    version = 1
    requires-python = ">=3.12"

    [[package]]
    name = "bad-package"
    version = "^1.4.4"
    source = { registry = "https://pypi.org/simple" }
    TOML

    # manifest.dependencies rejects all malformed dependencies on return
    expect(manifest(content: content).dependencies).to be_empty
  end

  specify { expect(manifest.manifest_type).to eq Types::Manifest[:uv_lock] }
end
