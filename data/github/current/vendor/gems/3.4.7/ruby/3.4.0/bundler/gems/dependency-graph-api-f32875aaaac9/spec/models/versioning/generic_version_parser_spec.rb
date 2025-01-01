require "spec_helper"
require "rails_helper"
require "active_support"
require "active_support/core_ext"

describe Versioning::GenericVersionParser do

  it "creates a named version if ecosystem supports named versions and version is not valid semver" do
    v1 = described_class.generate(
      allow_named_versions: true,
      primary_identifier: "main",
    )

    expect(v1.instance_of?(Versioning::NamedVersion)).to be_truthy
  end

  it "creates a semantic version if ecosystem was defined and version is valid semver" do
    v1 = described_class.generate(
      allow_named_versions: true,
      primary_identifier: 1,
      minor: 0,
      patch: 0,
    )

    expect(v1.instance_of?(Versioning::SemanticVersion)).to be_truthy
  end

  it "creates a semantic version if no ecosystem was defined and version is valid semver" do
    v1 = described_class.generate(
      primary_identifier: 1,
      minor: 0,
      patch: 0,
    )

    expect(v1.instance_of?(Versioning::SemanticVersion)).to be_truthy
  end

  LEGAL_SEMVER = %w[
    0.0.4
    1.2.3
    10.20.30
    1.1.2-prerelease+meta
    1.1.2+meta
    1.1.2+meta-valid
    1.0.0-alpha
    1.0.0-beta
    1.0.0-alpha.beta
    1.0.0-alpha.beta.1
    1.0.0-alpha.1
    1.0.0-alpha0.valid
    1.0.0-alpha.0valid
    1.0.0-alpha-a.b-c-somethinglong+build.1-aef.1-its-okay
    1.0.0-rc.1+build.1
    2.0.0-rc.1+build.123
    1.2.3-beta
    10.2.3-DEV-SNAPSHOT
    1.2.3-SNAPSHOT-123
    1.0.0
    2.0.0
    1.1.7
    2.0.0+build.1848
    2.0.1-alpha.1227
    1.0.0-alpha+beta
    1.2.3----RC-SNAPSHOT.12.9.1--.12+788
    1.2.3----R-S.12.9.1--.12+meta
    1.2.3----RC-SNAPSHOT.12.9.1--.12
    1.0.0+0.build.1-rc.10000aaa-kk-0.1
    99999999999999999999999.999999999999999999.99999999999999999
    1.0.0-0A.is.legal
  ]

  ALLOWED_NON_SEMVER = %w[
    1
    1.2
    1.2.3-0123
    1.2.3-0123.0123
    1.1.2+.123
    1.0.0-alpha_beta
    1.2
    1.2.3.DEV
    9.8.7-whatever+meta+meta
  ]

  NAMED_VERSIONS = %w[
    main
    master
    ab2903bdce6310cfbddd87c418f253cf29b2dec9
    6b2903bdce6310cfbddd87c418f253cf29b2dec9
    +invalid
    -invalid
    -invalid+invalid
    -invalid.01
    alpha
    alpha.beta
    alpha.beta.1
    alpha.1
    alpha+beta
    alpha_beta
    alpha.
    alpha..
    beta
  ]

  LEGAL_SEMVER.each do |version|
    it "parses #{version} as a valid semver" do
      expect(described_class.valid_named_version?(true, version)).to be false
    end
  end

  ALLOWED_NON_SEMVER.each do |version|
    it "parses #{version} as semver-ish" do
      expect(described_class.valid_named_version?(true, version)).to be false
    end
  end

  NAMED_VERSIONS.each do |version|
    it "parses #{version} as a named version" do
      expect(described_class.valid_named_version?(true, version)).to be true
    end
  end
end
