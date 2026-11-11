require "rails_helper"
require "manifest_adapters"

describe "cargo.toml parsing" do
  def manifest(attributes = {})
    ::ManifestAdapters.parse(**{
      git_ref: "93dfb3353dddcde2ab11e9df8f4d0fba6bc12606",
      github_repository_id: 105,
      filename: "Cargo.toml",
      path: "",
      content: file_fixture("Cargo.toml").read, # default to static file fixture
      pushed_at: Time.new(2022, 4, 25),
      fork: false,
      visibility_private: false
    }.merge(attributes))
  end

  it "parses metadata" do
    expect(manifest.malformed?).to be_falsey
    expect(manifest.dependencies).to_not be_nil
  end

  it "parses runtime dependencies from all appropriate Cargo build scopes" do
    deps = manifest
      .dependencies
      .select { |d| d.scope == Types::Scope[:runtime] }
      .each_with_object({}) { |d, h| h[d.package_name] = d }

    # general sanity checks
    expect(deps.length).to eq 5
    expect(deps.values.select(&:malformed?)).to be_empty

    # check [dependencies], including resolved single and range bounds on version
    expect(deps["rand"]).to_not be_nil
    expect(deps["rand"].raw_requirements).to eq "^0.8.5"
    expect(deps["rand"].requirements).to eq ">= 0.8.5, < 0.9.0"

    expect(deps["plotters"]).to_not be_nil
    expect(deps["plotters"].raw_requirements).to eq "^0.3.1"
    expect(deps["plotters"].requirements).to eq ">= 0.3.1, < 0.4.0"

    expect(deps["rayon"]).to_not be_nil
    expect(deps["rayon"].raw_requirements).to eq "~1.5.1"
    expect(deps["rayon"].requirements).to eq ">= 1.5.1, < 1.6.0"

    expect(deps["clap"]).to_not be_nil
    expect(deps["clap"].raw_requirements).to eq "3.1.6"
    expect(deps["clap"].requirements).to eq ">= 3.1.6, < 4.0.0"

    # check [target.*.dependencies]
    expect(deps["parking_lot"]).to_not be_nil
    expect(deps["parking_lot"].raw_requirements).to eq ">1, <=3.4.5"
    expect(deps["parking_lot"].requirements).to eq ">= 2.0.0, <= 3.4.5"
  end

  it "parses development dependencies from all appropriate Cargo build scopes" do
    dev_deps = manifest
      .dependencies
      .select { |d| d.scope == Types::Scope[:development] }
      .each_with_object({}) { |d, h| h[d.package_name] = d }

    # general sanity checks
    expect(dev_deps.length).to eq 6
    expect(dev_deps.values.select(&:malformed?)).to be_empty

    # check [dev-dependencies], including explicit and nested versions
    expect(dev_deps["serde"]).to_not be_nil
    expect(dev_deps["serde"].raw_requirements).to eq "~1.2.3"
    expect(dev_deps["serde"].requirements).to eq ">= 1.2.3, < 1.3.0"
    expect(dev_deps["serde_json"]).to_not be_nil
    expect(dev_deps["serde_json"].raw_requirements).to eq ">1.0.0, <=3"
    expect(dev_deps["serde_json"].requirements).to eq "> 1.0.0, < 4.0.0"

    # check [build-dependencies] including aliased pkg name and wildcards
    expect(dev_deps["time"]).to_not be_nil
    expect(dev_deps["time"].raw_requirements).to eq ">2.0.*, <3.5.0"
    expect(dev_deps["time"].requirements).to eq ">= 2.1.0, < 3.5.0"
    expect(dev_deps["gif"]).to_not be_nil
    expect(dev_deps["gif"].raw_requirements).to eq "< 0.3.*"
    expect(dev_deps["gif"].requirements).to eq "< 0.3.0"

    # check [target.*.dev-dependencies] including misordered version range
    expect(dev_deps["base64"]).to_not be_nil
    expect(dev_deps["base64"].raw_requirements).to eq "<3.1.0, >= 1.2.2"
    expect(dev_deps["base64"].requirements).to eq ">= 1.2.2, < 3.1.0"

    # check [target.*.build-dependencies] including aliased pkg name
    expect(dev_deps["bitflags"]).to_not be_nil
    expect(dev_deps["bitflags"].raw_requirements).to eq "~1.1.0"
    expect(dev_deps["bitflags"].requirements).to eq ">= 1.1.0, < 1.2.0"
  end

  it "processes alternate TOML package syntax used in manifests" do
    alt_format_manifest = <<~EOF
      [package]
      name = "burn_after_reading"
      version = "0.8.3"
      edition = "2018"

      [dependencies.plotters]
      version = "^0.3.1"

      [dependencies.rayon]
      version = "~1.5.1"

      [dev-dependencies.clap]
      version = ">1"
      EOF

    got = manifest(content: alt_format_manifest)
    expect(got.dependencies.length).to eq 3
    expect(got.malformed?).to be_falsey, "expected to parse well-formed, alt-format manifest content: #{alt_format_manifest}"
  end

  it "fails gracefully when processing corrupt manifests" do
    bad_manifest = <<~EOF
      [package]
      name = "burn_after_reading"
      version = "0.8.2"
      edition = "2018"

      [dependencies]
      plotters = "^0.3.1"
      rayon = "~1.5.1"

      [target.bad_toml.dependencies[
      clap = ">1.*"
      EOF

    got = manifest(content: bad_manifest)
    expect(got.malformed?).to be_truthy, "expected to fail on corrupt manifest content: #{bad_manifest}"
  end

  it "skips bad entries when processing invalid manifest dependencies" do
    bad_manifest = <<~EOF
      [package]
      name = "who_did_this_to_you"
      version = "1.2.3"
      edition = "2018"

      [target.bad_toml.dependencies]
      1234 = "&nonsense"

      [dependencies]
      plotters = "^0.3.1"
      rayon = "~1.5.1"
      clap = ">1.*"
      EOF

    got = manifest(content: bad_manifest)
    expect(got.malformed?).to be_falsey, "expected to succeed by skipping corrupt manifest dependency: #{bad_manifest}"
    expect(got.dependencies.length).to eq 3
    expect(got.dependencies.select(&:malformed?)).to be_empty
  end

  it "skips dependency entries mapping to an invalid Cargo package scope entry" do
    bad_manifest = <<~EOF
      [package]
      name = "confused_about_scopes"
      version = "2.2.1"
      edition = "2018"

      [target.'cfg(unix)'.dev-dependencies]
      rayon = "~1.5.1"

      [target.unknown-platform.target.tricky.build-dependencies]
      lost_lib_1 = "1.0.0"

      [package.dependencies]
      lost_lib_2 = "1.0.0"

      [dependencies]
      plotters = "^0.3.1"
      EOF

    got = manifest(content: bad_manifest)
    expect(got.malformed?).to be_falsey, "expected to succeed #{bad_manifest}"
    expect(got.dependencies.length).to eq 2
    expect(got.dependencies.select(&:malformed?)).to be_empty
    expect(got.dependencies.select { |d| d.package_name.starts_with?("lost_lib") }).to be_empty
  end

  it "skips dependencies without 'version' entry" do
    bad_manifest = <<~EOF
      [package]
      name = "handles_locally_hosted_packages_right"
      version = "1.2.3"
      edition = "2018"

      [dependencies]
      plotters = "^0.3.1"
      foobar = { path = "src/something/something" }

      [dev-dependencies]
      rayon = "~1.5.1"

      [build-dependencies]
      baz = ">1.0.0"
      EOF

    got = manifest(content: bad_manifest)
    expect(got.malformed?).to be_falsey, "expected to succeed #{bad_manifest}"
    expect(got.dependencies.length).to eq 3
    expect(got.dependencies.select(&:malformed?)).to be_empty
    expect(got.dependencies.select { |d| d.package_name == "foobar" }).to be_empty
  end
end
