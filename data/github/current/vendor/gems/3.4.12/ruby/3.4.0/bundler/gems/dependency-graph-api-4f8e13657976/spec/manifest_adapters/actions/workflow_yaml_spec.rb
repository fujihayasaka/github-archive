require "rails_helper"
require "manifest_adapters"

describe "workflow.yaml parsing" do
  def manifest(attributes = {})
    ::ManifestAdapters.parse(**{
      git_ref: "78716382bd3de2dbf141643bbe40f93185b5d4c6",
      github_repository_id: 105,
      filename: "a_nice_workflow.yaml",
      path: ".github/workflows/",
      content: file_fixture("workflow.yaml").read,
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
    expect(first_dep.package_name).to eq("actions/regular_external_action")
    expect(first_dep.requirements).to eq("= 1.*.*")
    expect(first_dep.raw_requirements).to eq("v1")
    expect(first_dep.scope).to eq(Types::Scope[:runtime])
    expect(first_dep.malformed?).to be_falsey

    expect(last_dep).to be_an_instance_of(ManifestAdapters::Manifest::Dependency)
    expect(last_dep.package_name).to eq("octo-org/this-repo/.github/workflows/workflow-sha-version.yml")
    expect(last_dep.requirements).to eq("= 172239021f7ba04fe7327647b213799853a9eb89")
    expect(last_dep.raw_requirements).to eq("172239021f7ba04fe7327647b213799853a9eb89")
    expect(last_dep.scope).to eq(Types::Scope[:runtime])
    expect(last_dep.malformed?).to be_falsey
  end

  it "rejects docker image dependencies" do
    dependencies = manifest.dependencies.map { |dep| dep.package_name }

    expect(dependencies).to_not include("docker://alpine:3.8")
  end

  it "handles invalid requirements" do
    content = <<~YAML
    name: Testing all types of dependencies

    jobs:
      first_job:
        runs-on: ubuntu-latest

        steps:
        - uses: somestuff
    YAML

    # manifest.dependencies rejects all malformed dependencies on return
    expect(manifest(content: content).dependencies).to be_empty
  end

  it "handles parsing errors gracefully" do
    content = "blah: blah\n stuff: blah\n\n\nmorestuff: blah" # syntax that'll break Psych
    expect(manifest(content: content).malformed?).to be_truthy
  end

  it "handles incorrect actions syntax gracefully" do
    # malformed manifest because `- name:` is incorrect actions syntax and would parse as an array
    content_1 = <<~YAML
    - name: Testing all types of dependencies

    jobs:
      first_job:
        runs-on: ubuntu-latest

        steps:
        - uses: somestuff@v1.0.1
    YAML

    parsed_content_1 = manifest(content: content_1)
    expect(parsed_content_1.dependencies).to be_empty
    expect(parsed_content_1.malformed?).to be_truthy

    # lack of indentation for `first_job`
    content_2 = <<~YAML
    name: Testing all types of dependencies

    jobs:
    first_job:
      runs-on: ubuntu-latest

    steps:
      - uses: somestuff@v1.0.1
    YAML

    parsed_content_2 = manifest(content: content_2)
    expect(parsed_content_2.dependencies).to be_empty
    # we're not expecting the manifest to be malformed just because one job/step might be missing indentation
  end

  it "handles aliasing in workflows" do
    content = <<~YAML
    name: Testing all types of dependencies

    jobs:
      first_job:
        runs-on: &os ubuntu-latest

        steps:
        - uses: somestuff@v1.0.1
      second_job:
        runs-on: *os

        steps:
        - uses: otherstuff@v2
    YAML

    parsed_content = manifest(content: content)
    expect(parsed_content.dependencies).to_not be_empty
    expect(parsed_content.malformed?).to be_falsey
  end

  it "handles dates & symbols in workflows" do
    content = <<~YAML
    env:
      cache_generation: 2022-02-22
      generation_time: 11:22:33

    name: Testing all types of dependencies

    jobs:
      first_job:
        if: ${{ github.ref == 'refs/heads/main' }}
        runs-on: ubuntu-latest

        steps:
        - uses: somestuff@v1.0.1
          with:
            key: :SYMBOL
    YAML

    parsed_content = manifest(content: content)
    expect(parsed_content.dependencies).to_not be_empty
    expect(parsed_content.malformed?).to be_falsey
  end

  it "parse_version expands Actions semvers when encountered" do
    units = [
      # non-semvers
      { in: "foobarbazz", out: "= foobarbazz" },
      { in: "d612bbcfdd4b703b1831c142c3dc8a9063ae56f2", out: "= d612bbcfdd4b703b1831c142c3dc8a9063ae56f2" },
      { in: "", out: "= " }, # sigh...

      # non-semvers 2: corrupt semver elems are detected, falls back to "named version"
      { in: "vNOGOOD", out: "= vNOGOOD" },
      { in: "v1a.2.3", out: "= v1a.2.3" },
      { in: "vaka-102/add-support-for-auto-incrementing-node-projects", out: "= vaka-102/add-support-for-auto-incrementing-node-projects" },
      { in: "veracode-backend_v1.0.0", out: "= veracode-backend_v1.0.0" },
      { in: "versys/v0.1.0", out: "= versys/v0.1.0" },
      { in: "vad44023a93711e3deb337508980b4b5e9bcdc5dc", out: "= vad44023a93711e3deb337508980b4b5e9bcdc5dc" },
      { in: "v1d44023a93711e3deb337508980b4b5e9bcdc5dc", out: "= v1d44023a93711e3deb337508980b4b5e9bcdc5dc" },
      { in: "vd7906e4ad0b1822421a7e6a35d5ca353c962f410", out: "= vd7906e4ad0b1822421a7e6a35d5ca353c962f410" },
      { in: "v2.foo", out: "= v2.foo" },
      { in: "v2.1.3.foo", out: "= v2.1.3.foo" },
      { in: "v2.3.4.-prerelease.beta.1", out: "= v2.3.4.-prerelease.beta.1" },
      { in: "v1.2a.3-pre", out: "= v1.2a.3-pre" },
      { in: "v1.2.3pre", out: "= v1.2.3pre" },

      # Actions semvers (always 'v' prefixed)
      { in: "v2", out: "= 2.*.*" },
      { in: "v2.1", out: "= 2.1.*" },
      { in: "v222.333.444", out: "= 222.333.444" },
      { in: "v2.*.*", out: "= 2.*.*" },
      { in: "v2.x.x", out: "= 2.x.x" },
      { in: "   v2.1", out: "= 2.1.*" },
      { in: "v2.1.3", out: "= 2.1.3" },
      { in: "v2.1.3-foo", out: "= 2.1.3-foo" },
      { in: "v2.3-foo", out: "= 2.3.*-foo" },
      { in: "v2.3.4-alpha.rc1+x64", out: "= 2.3.4-alpha.rc1+x64" },
    ]

    units.each do |unit|
      parser = ManifestAdapters::Actions::Parsers::WorkflowYaml.new("", private_repository: false)
      got = parser.send(:parse_version, unit[:in])
      expect(got).to eq(unit[:out])
    end
  end
end
