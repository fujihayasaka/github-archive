require "rails_helper"

describe "Package.resolved parsing" do
  let (:v1_manifest) do
    {
      "object": {
        "pins": [
          {
            "package": "v1-swift-package",
            "repositoryURL": "https://github.com/owner/v1-swift-package",
            "state": {
              "branch": "main",
              "revision": "9f39744e025c7d377987f30b03770805dcb0bcd1",
              "version": "1.0.0"
            }
          }
        ]
      },
      "version": 1
    }
  end

  let (:v2_manifest) do
    {
      "pins": [
        {
          "identity": "v1-swift-package",
          "kind": "remoteSourceControl",
          "location": "https://github.com/owner/v2-swift-package",
          "state": {
            "revision": "576528c7618838ed3bdb967b4e176841994aa01d",
            "version": "2.2.0"
          }
        }
      ],
      "version": 2
    }
  end

  def parse_manifest(manifest_content:)
    ManifestAdapters.parse(
      git_ref: "5b5d4c6",
      github_repository_id: 234,
      filename: "Package.resolved",
      path: "",
      content: manifest_content.to_json,
      pushed_at: Time.new(2023, 1, 1),
      fork: false,
      visibility_private: false,
    )
  end

  it "correctly parses v1 manifests" do
    manifest = parse_manifest(manifest_content: v1_manifest)
    expect(manifest.manifest_type).to eq Types::Manifest[:package_resolved]
    expect(manifest.package_manager).to eq Types::PackageManager[:swift]
    expect(manifest.malformed?).to be_falsey
    expect(manifest.dependencies.size).to eq 1
    expect(manifest.dependencies).to match_array [
      ManifestAdapters::Manifest::Dependency.new(
        package_name: "github.com/owner/v1-swift-package",
        requirements: "= 1.0.0",
        raw_requirements: "1.0.0",
        scope: :runtime,
        malformed: false
      )
    ]
  end

  it "correctly parses v2 manifests" do
    manifest = parse_manifest(manifest_content: v2_manifest)
    expect(manifest.manifest_type).to eq Types::Manifest[:package_resolved]
    expect(manifest.package_manager).to eq Types::PackageManager[:swift]
    expect(manifest.malformed?).to be_falsey
    expect(manifest.dependencies.size).to eq 1
    expect(manifest.dependencies).to match_array [
      ManifestAdapters::Manifest::Dependency.new(
        package_name: "github.com/owner/v2-swift-package",
        requirements: "= 2.2.0",
        raw_requirements: "2.2.0",
        scope: :runtime,
        malformed: false
      )
    ]
  end

  it "doesnt parse manifests with no pins as malformed" do
    manifest = parse_manifest(manifest_content: {  "version": 1 })
    expect(manifest.malformed?).to be_falsey

    manifest = parse_manifest(manifest_content: {  "version": 2 })
    expect(manifest.malformed?).to be_falsey
  end

  it "flags unsupported manifest versions as malformed" do
    v1_manifest[:version] = 3
    manifest = parse_manifest(manifest_content: v1_manifest)
    expect(manifest.malformed?).to be_truthy

    v2_manifest.delete(:version)
    manifest = parse_manifest(manifest_content: v2_manifest)
    expect(manifest.malformed?).to be_truthy
  end

  it "flags manifest with invalid format as malformed" do
    manifest = parse_manifest(manifest_content: [])
    expect(manifest.malformed?).to be_truthy

    manifest = parse_manifest(manifest_content: "not a hash")
    expect(manifest.malformed?).to be_truthy
  end

  it "rejects dependencies with invalid package source" do
    v2_manifest[:pins][0][:location] =  "invalid url"
    manifest = parse_manifest(manifest_content: v2_manifest)

    expect(manifest.dependencies).to be_empty
  end

  it "handles packages with scp style source" do
    v2_manifest[:pins][0][:location] =  "  git@github.com:owner/scp-package.git"
    manifest = parse_manifest(manifest_content: v2_manifest)

    expect(manifest.dependencies).to match_array [
      ManifestAdapters::Manifest::Dependency.new(
        package_name: "github.com/owner/scp-package",
        requirements: "= 2.2.0",
        raw_requirements: "2.2.0",
        scope: :runtime,
        malformed: false
      )
    ]
  end

  it "handles varying cases in package source" do
    v2_manifest[:pins][0][:location] =  "https://WWW.GitHub.com/Owner/diff-CASED-package.GIT"
    manifest = parse_manifest(manifest_content: v2_manifest)

    expect(manifest.dependencies).to match_array [
      ManifestAdapters::Manifest::Dependency.new(
        package_name: "github.com/owner/diff-cased-package",
        requirements: "= 2.2.0",
        raw_requirements: "2.2.0",
        scope: :runtime,
        malformed: false
      )
    ]
  end

  it "handles dependencies with missing version" do
    v2_manifest[:pins][0][:state].delete(:version)
    manifest = parse_manifest(manifest_content: v2_manifest)

    expect(manifest.dependencies.size).to eq 1
    expect(manifest.dependencies).to match_array [
      ManifestAdapters::Manifest::Dependency.new(
        package_name: "github.com/owner/v2-swift-package",
        requirements: ">= 0",
        raw_requirements: "576528c7618838ed3bdb967b4e176841994aa01d",
        scope: :runtime,
        malformed: false
      )
    ]
  end

  it "rejects dependencies with non semver compliant version" do
    v2_manifest[:pins][0][:state][:version] =  "not-semver"
    manifest = parse_manifest(manifest_content: v2_manifest)

    expect(manifest.malformed?).to be_falsey
    expect(manifest.dependencies).to be_empty
  end

end
