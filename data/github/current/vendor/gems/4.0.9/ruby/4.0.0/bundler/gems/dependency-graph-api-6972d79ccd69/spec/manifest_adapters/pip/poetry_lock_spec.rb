require "rails_helper"
require "manifest_adapters"

describe "poetry.lock parsing" do
  def manifest(attributes = {})
    ::ManifestAdapters.parse(**{
      git_ref: "78716382bd3de2dbf141643bbe40f93185b5d4c6",
      github_repository_id: 105,
      filename: "poetry.lock",
      path: "",
      content: file_fixture("poetry.lock").read,
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
    first_dep, last_dep = manifest.dependencies.first, manifest.dependencies.last
    expect(first_dep).to be_an_instance_of(ManifestAdapters::Manifest::Dependency)
    expect(first_dep.package_name).to eq("appdirs")
    expect(first_dep.requirements).to eq("= 1.4.4")
    expect(first_dep.raw_requirements).to eq("1.4.4")
    expect(first_dep.scope).to eq(Types::Scope[:runtime])
    expect(first_dep.malformed?).to be_falsey

    expect(last_dep).to be_an_instance_of(ManifestAdapters::Manifest::Dependency)
    expect(last_dep.package_name).to eq("zipp")
    expect(last_dep.requirements).to eq("= 3.5.0")
    expect(last_dep.raw_requirements).to eq("3.5.0")
    expect(last_dep.scope).to eq(Types::Scope[:development])
    expect(last_dep.malformed?).to be_falsey
  end

  it "does not contain git-sourced dependency" do
    dep = manifest.dependencies.find { |d| d.package_name == "pluggy" }
    expect(dep).to be_nil
  end

  it "does not contain path-sourced dependency" do
    dep = manifest.dependencies.find { |d| d.package_name == "poetry-core" }
    expect(dep).to be_nil
  end

  it "does not contain url-sourced dependency" do
    dep = manifest.dependencies.find { |d| d.package_name == "pycparser" }
    expect(dep).to be_nil
  end

  it "handles invalid TOML" do
    manifest = manifest(content: "{")
    expect(manifest).to be_malformed
  end

  it "handles invalid requirements" do
    content = <<~TOML
    [[package]]
    name = "sup"
    version = "^1.4.4"
    description = "stuff"
    category = "main"
    optional = false
    python-versions = "*"
    TOML

    # manifest.dependencies rejects all malformed dependencies on return
    expect(manifest(content: content).dependencies).to be_empty
  end
end
