# coding: utf-8
# Tests of ../../../app/manifest_adapters/manifest_adapters/go/go_mod_parser.rb

require "rails_helper"
require "manifest_adapters"

describe "go.mod parsing:" do

  # When this test is run by script/cibuild, Dockerfile.test is
  # responsible for placing the Go program at ./gomod2json.  For
  # interactive test runs, we run 'go build' to ensure it is up to date.
  # (The TEST_ENV var is set by script/setup-and-test.)
  before(:all) do
    if ENV["TEST_ENV"] != "ci"
      system("cd go && go build -o .. ./ecosystem/go/gomod2json") or
        abort("gomod_spec: failed to build gomod2json")
    end
  end

  def manifest(attributes = {})
    ::ManifestAdapters.parse(**{
      git_ref: "78716382bd3de2dbf141643bbe40f93185b5d4c6",
      github_repository_id: 55,
      filename: "go.mod",
      path: "",
      pushed_at: Time.new(2017, 1, 1),
      fork: false,
      visibility_private: false,
    }.merge(attributes))
  end

  it "malformed: missing module directive" do
    m = manifest(content: "require a.b/c v1.2.3")
    expect(m.malformed?).to eq(true)
  end

  it "malformed: syntax error" do
    m = manifest(content: "this is not a go.mod file")
    expect(m.malformed?).to eq(true)
  end

  it "valid: trivial" do
    m = manifest(content: "module foo.com/bar")
    expect(m.malformed?).to eq(false)
    # Manifest.dependent_name is always blank.
    # See comment in ../../../app/manifest_adapters/manifest_adapters/go/adapter.rb
    expect(m.dependent_name).to eq("")
    expect(m.dependent_version).to eq(nil)
    expect(m.dependencies).to eq([])
  end

  # This is a regression test for a crash that occurs when the
  # contents of a file are presented to the parser in a string tagged
  # as ASCII_8BIT, even when the file is valid UTF-8 text.
  it "valid: UTF-8" do
    m = manifest(content: "module foo.com/aЯ世".force_encoding(Encoding::ASCII_8BIT))
    expect(m.malformed?).to eq(false)
  end

  it "valid: has dependencies" do
    m = manifest(content: "module foo.com/bar\n" +
      "require bar.com/foo v1.2.3 // indirect\n" +
      "require bar.com/wiz v1.0.0-alpha+001")
    expect(m.malformed?).to eq(false)
    dep0, dep1 = m.dependencies
    expect(dep0.package_name).to eq("bar.com/foo")
    expect(dep0.requirements).to eq("= 1.2.3")
    expect(dep0.raw_requirements).to eq("1.2.3")
    expect(dep1.package_name).to eq("bar.com/wiz")
    expect(dep1.requirements).to eq("= 1.0.0-alpha")
    expect(dep1.raw_requirements).to eq("1.0.0-alpha")
    expect(m.dependencies.size).to eq(2)
  end
end
