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

  before(:each) do
    DependencyGraph.flipper.enable(:dependency_graph_go_mod_replace)
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

  it "valid: has a replacement for just the version" do
    m = manifest(content: "module example.com/replacement-test\n\n" +
      "go 1.24.3\n\n" +
      "require github.com/Masterminds/semver v1.5.0 // indirect\n\n" +
      "replace github.com/Masterminds/semver => github.com/Masterminds/semver v2.0.0")
    expect(m.malformed?).to eq(false)

    dep = m.dependencies.first
    expect(dep.package_name).to eq("github.com/Masterminds/semver")
    expect(dep.requirements).to eq("= 2.0.0")
    expect(dep.raw_requirements).to eq("2.0.0")
  end

  it "valid: ignores replacements when the flag is disabled" do
    DependencyGraph.flipper.disable(:dependency_graph_go_mod_replace)
    m = manifest(content: "module example.com/replacement-test\n\n" +
      "go 1.24.3\n\n" +
      "require github.com/Masterminds/semver v1.5.0 // indirect\n\n" +
      "replace github.com/Masterminds/semver => /workspaces/semver")
    expect(m.malformed?).to eq(false)

    dep = m.dependencies.first
    expect(dep.package_name).to eq("github.com/Masterminds/semver")
    expect(dep.requirements).to eq("= 1.5.0")
    expect(dep.raw_requirements).to eq("1.5.0")
  end

  it "valid: has a replacement for just the path" do
    m = manifest(content: "module example.com/replacement-test\n\n" +
      "go 1.24.3\n\n" +
      "require github.com/Masterminds/semver v1.5.0 // indirect\n\n" +
      "replace github.com/Masterminds/semver => /workspaces/semver")
    expect(m.malformed?).to eq(false)

    dep = m.dependencies.first
    expect(dep.package_name).to eq("/workspaces/semver")
    expect(dep.requirements).to eq("= 1.5.0")
    expect(dep.raw_requirements).to eq("1.5.0")
  end

  it "valid: has a replacement for the path and version" do
    m = manifest(content: "module example.com/replacement-test\n\n" +
      "go 1.24.3\n\n" +
      "require github.com/Masterminds/semver v1.5.0 // indirect\n\n" +
      "replace github.com/Masterminds/semver => github.com/github/semver v5.0.0")
    expect(m.malformed?).to eq(false)

    dep = m.dependencies.first
    expect(dep.package_name).to eq("github.com/github/semver")
    expect(dep.requirements).to eq("= 5.0.0")
    expect(dep.raw_requirements).to eq("5.0.0")
  end

  it "valid: has a replacement for just one version" do
    m = manifest(content: "module example.com/replacement-test\n\n" +
      "go 1.24.3\n\n" +
      "require github.com/Masterminds/semver v1.5.0 // indirect\n\n" +
      "require github.com/Masterminds/semver v1.0.0 // indirect\n\n" +
      "replace github.com/Masterminds/semver v1.0.0 => github.com/github/semver v5.0.0")
    expect(m.malformed?).to eq(false)

    untouched, replaced = m.dependencies.sort_by(&:package_name)

    expect(untouched.package_name).to eq("github.com/Masterminds/semver")
    expect(untouched.requirements).to eq("= 1.5.0")
    expect(untouched.raw_requirements).to eq("1.5.0")

    expect(replaced.package_name).to eq("github.com/github/semver")
    expect(replaced.requirements).to eq("= 5.0.0")
    expect(replaced.raw_requirements).to eq("5.0.0")
  end

  it "valid: has multiple replacements" do
    m = manifest(content: "module example.com/replacement-test\n\n" +
      "go 1.24.3\n\n" +
      "require github.com/Masterminds/semver v1.5.0 // indirect\n\n" +
      "require github.com/example/packageone v1.0.0 // indirect\n\n" +
      "require github.com/example/packagetwo v0.2.0 // indirect\n\n" +
      "replace github.com/example/packageone => github.com/example/packageone v1.0.1\n" +
      "replace github.com/example/packagetwo v0.2.0 => github.com/example/packagetwo v2.0.1")
    expect(m.malformed?).to eq(false)

    expect(m.dependencies.size).to eq(3)
    semver, packageone, packagetwo = m.dependencies.sort_by(&:package_name)
    expect(semver.package_name).to eq("github.com/Masterminds/semver")
    expect(semver.requirements).to eq("= 1.5.0")
    expect(semver.raw_requirements).to eq("1.5.0")

    expect(packageone.package_name).to eq("github.com/example/packageone")
    expect(packageone.requirements).to eq("= 1.0.1")
    expect(packageone.raw_requirements).to eq("1.0.1")

    expect(packagetwo.package_name).to eq("github.com/example/packagetwo")
    expect(packagetwo.requirements).to eq("= 2.0.1")
    expect(packagetwo.raw_requirements).to eq("2.0.1")
  end

  it "valid: marks a single 'tool' dependency as development scope" do
    m = manifest(content: "module example.com/tool-multi\n\n" +
      "go 1.24.3\n\n" +
      "tool github.com/github/semver\n\n" +
      "require (\n" +
      " github.com/github/semver v1.0.0 // indirect\n" +
      " golang.org/x/tools v0.33.0 // indirect\n" +
      ")\n")
    expect(m.malformed?).to eq(false)
    expect(m.dependencies.size).to eq(2)

    semver, tools = m.dependencies.sort_by(&:package_name)
    expect(semver.package_name).to eq("github.com/github/semver")
    expect(semver.scope).to eq(Types::Scope[:development])
    expect(tools.package_name).to eq("golang.org/x/tools")
    expect(tools.scope).to eq(Types::Scope[:runtime])
  end

  it "valid: marks multiple 'tool' dependencies as development scope" do
    m = manifest(content: "module example.com/tool-multi\n\n" +
      "go 1.24.3\n\n" +
      "tool (\n" +
      " github.com/github/semver\n" +
      " golang.org/x/tools\n" +
      ")\n\n" +
      "require (\n" +
      " github.com/github/semver v1.0.0 // indirect\n" +
      " golang.org/x/tools v0.33.0 // indirect\n" +
      ")\n")
    expect(m.malformed?).to eq(false)
    expect(m.dependencies.size).to eq(2)
    semver, tools = m.dependencies.sort_by(&:package_name)
    expect(semver.package_name).to eq("github.com/github/semver")
    expect(semver.scope).to eq(Types::Scope[:development])
    expect(tools.package_name).to eq("golang.org/x/tools")
    expect(tools.scope).to eq(Types::Scope[:development])
  end

  it "valid: 'tool' dependency not in require is ignored" do
    m = manifest(content: "module example.com/tool-unused\n\n" +
      "go 1.24.3\n\n" +
      "tool (\n" +
      " github.com/unused/tool\n" +
      ")\n\n" +
      "require (\n" +
      " github.com/github/semver v1.0.0 // indirect\n" +
      ")\n")
    expect(m.malformed?).to eq(false)
    expect(m.dependencies.size).to eq(1)
    expect(m.dependencies.first.package_name).to eq("github.com/github/semver")
    expect(m.dependencies.first.scope).to eq(Types::Scope[:runtime])
  end

  it "valid: marks a 'tool' dependency as development scope when that dependency has been replaced" do
    m = manifest(content: "module example.com/tool-test\n\n" +
      "go 1.24.3\n\n" +
      "tool (\n" +
      "	github.com/github/semver\n" +
      ")\n\n" +
      "require (\n" +
      "	github.com/Masterminds/semver v1.5.0 // indirect\n" +
      "	golang.org/x/mod v0.24.0 // indirect\n" +
      "	golang.org/x/sync v0.14.0 // indirect\n" +
      "	golang.org/x/tools v0.33.0 // indirect\n" +
      ")\n" +
      "replace github.com/Masterminds/semver => github.com/github/semver v5.0.0")
    expect(m.malformed?).to eq(false)
    expect(m.dependencies.size).to eq(4)

    semver, mod, sync, tools = m.dependencies.sort_by(&:package_name)

    # semver has been replaced with a development tool, so it should
    # have a development scope.
    expect(semver.package_name).to eq("github.com/github/semver")
    expect(semver.scope).to eq(Types::Scope[:development])

    expect(mod.package_name).to eq("golang.org/x/mod")
    expect(mod.scope).to eq(Types::Scope[:runtime])
    expect(sync.package_name).to eq("golang.org/x/sync")
    expect(sync.scope).to eq(Types::Scope[:runtime])
    expect(tools.package_name).to eq("golang.org/x/tools")
    expect(tools.scope).to eq(Types::Scope[:runtime])
  end
end
