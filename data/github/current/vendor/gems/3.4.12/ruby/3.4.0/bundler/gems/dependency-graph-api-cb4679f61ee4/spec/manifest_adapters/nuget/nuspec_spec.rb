require "rails_helper"
require "manifest_adapters"

describe "nuspec parsing" do
  def manifest(attributes = {})
    ::ManifestAdapters.parse(**{
      git_ref: "78716382bd3de2dbf141643bbe40f93185b5d4c6",
      github_repository_id: 55,
      filename: ".nuspec",
      path: "",
      content: file_fixture(".nuspec").read,
      pushed_at: Time.new(2017, 1, 1),
      fork: false,
      visibility_private: false,
    }.merge(attributes))
  end

  def grouped_dep_manifest(attributes = {})
    ::ManifestAdapters.parse(**{
      git_ref: "78716382bd3de2dbf141643bbe40f93185b5d4c6",
      github_repository_id: 55,
      filename: "proj.nuspec",
      path: "",
      content: file_fixture("proj.nuspec").read,
      pushed_at: Time.new(2017, 1, 1),
      fork: false,
      visibility_private: false,
    }.merge(attributes))
  end

  it "parses metadata" do
    expect(manifest.dependent_name).to eq("sample")
    expect(manifest.dependent_version).to eq("1.0.0")
    expect(manifest.malformed?).to be_falsey
    expect(manifest.dependencies).to_not be_nil
  end

  it "parses dependencies" do
    expect(manifest.dependencies).to be_an_instance_of(Array)
    expect(manifest.dependencies.first).to be_an_instance_of(ManifestAdapters::Manifest::Dependency)
    expect(manifest.dependencies.first.package_name).to eq("another-package")
    expect(manifest.dependencies.first.requirements).to eq("= 3.0.0")
    expect(manifest.dependencies.first.raw_requirements).to eq("3.0.0")
    expect(manifest.dependencies.first.scope).to eq(Types::Scope[:runtime])
    expect(manifest.dependencies.first.malformed?).to be_falsey
  end

  it "parses dependency groups" do
    expect(grouped_dep_manifest.dependencies).to be_an_instance_of(Array)
    expect(grouped_dep_manifest.dependencies.first).to be_an_instance_of(ManifestAdapters::Manifest::Dependency)
    expect(grouped_dep_manifest.dependencies.first.package_name).to eq("FluentNHibernate")
  end

  it "understands dependency versions" do
    expect(manifest.dependencies.last.requirements).to eq("= 1.0.0")
    expect(manifest.dependencies.last.raw_requirements).to eq("1.0.0")
    expect(manifest.dependencies[3].requirements).to eq("= 2.0.0")
    expect(manifest.dependencies[3].raw_requirements).to eq("[2.0.0]")
    expect(manifest.dependencies[4].requirements).to eq(">= 6, < 7")
    expect(manifest.dependencies[4].raw_requirements).to eq("6.*")
    expect(manifest.dependencies[5].requirements).to eq("<= 1.5")
    expect(manifest.dependencies[5].raw_requirements).to eq("(,1.5]")
    expect(ManifestAdapters::Nuget::Requirements.parse(("(1.0)"))).to be_empty
  end

  it "understands dependency includes" do
    expect(manifest.dependencies.last.scope).to eq(Types::Scope[:development])
    expect(manifest.dependencies.first.scope).to eq(Types::Scope[:runtime])
    expect(manifest.dependencies[2].scope).to eq(Types::Scope[:development])
  end
end
