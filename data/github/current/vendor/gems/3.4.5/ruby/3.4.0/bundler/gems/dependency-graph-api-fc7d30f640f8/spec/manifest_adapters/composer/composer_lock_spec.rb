require "rails_helper"
require "manifest_adapters"

describe "composer.lock parsing" do
  def manifest(attributes = {})
    ::ManifestAdapters.parse(**{
      git_ref: "78716382bd3de2dbf141643bbe40f93185b5d4c6",
      github_repository_id: 105,
      filename: "composer.lock",
      path: "",
      content: file_fixture("composer.lock").read,
      pushed_at: Time.new(2019, 1, 1),
      fork: false,
      visibility_private: false
    }.merge(attributes))
  end

  it "parses metadata" do
    expect(manifest.malformed?).to be_falsey
    expect(manifest.dependencies).to_not be_nil
  end

  it "parses dependencies" do
    expect(manifest.dependencies).to be_an_instance_of(Array)
    expect(manifest.dependencies.first).to be_an_instance_of(ManifestAdapters::Manifest::Dependency)
    expect(manifest.dependencies.first.package_name).to eq("blah/blahblah")
    expect(manifest.dependencies.first.requirements).to eq("= 2.2.3")
    expect(manifest.dependencies.first.raw_requirements).to eq("2.2.3")
    expect(manifest.dependencies.first.scope).to eq(Types::Scope[:runtime])
    expect(manifest.dependencies.first.malformed?).to be_falsey
  end

  it "understands dependency versions" do
    expect(manifest.dependencies.first.package_name).to eq("blah/blahblah")
    expect(manifest.dependencies.first.requirements).to eq("= 2.2.3")
    expect(manifest.dependencies.first.raw_requirements).to eq("2.2.3")
    expect(manifest.dependencies.second.package_name).to eq("cebe/markdown")
    expect(manifest.dependencies.second.requirements).to eq("= 1.2.1")
    expect(manifest.dependencies.second.raw_requirements).to eq("v1.2.1")
  end

  it "understands branch aliases that do/do not have a explicitly defined alias" do
    expect(manifest.dependencies[-2].package_name).to eq("sarahsarah/branchalias")
    expect(manifest.dependencies[-2].requirements).to eq("= 2.0-dev")
    expect(manifest.dependencies[-2].raw_requirements).to eq("2.0-dev")
    expect(manifest.dependencies.last.package_name).to eq("sarahsarah/nobranchalias")
    expect(manifest.dependencies.last.requirements).to eq("")
    expect(manifest.dependencies.last.raw_requirements).to eq("dev-trunk")
  end

  it "understands dependency scopes" do
    expect(manifest.dependencies.last.scope).to eq(Types::Scope[:development])
    expect(manifest.dependencies.first.scope).to eq(Types::Scope[:runtime])
  end
end
