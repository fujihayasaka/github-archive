require "rails_helper"

describe ManifestAdapters::Maven::Requirements do
  it "correctly parses Maven version ranges" do
    # Cases below come from https://docs.oracle.com/middleware/1212/core/MAVEN/maven_version.htm#MAVEN402
    expect(described_class.parse("1.0")).to eq "= 1.0"
    expect(described_class.parse("(,1.0]")).to eq "<= 1.0"
    expect(described_class.parse("(,1.0)")).to eq "< 1.0"
    expect(described_class.parse("[1.0]")).to eq "= 1.0"
    expect(described_class.parse("[1.0,)")).to eq ">= 1.0"
    expect(described_class.parse("(1.0,)")).to eq "> 1.0"
    expect(described_class.parse("(,1.0]")).to eq "<= 1.0"
    expect(described_class.parse("(,1.0)")).to eq "< 1.0"
    expect(described_class.parse("(1.0,2.0)")).to eq "> 1.0, < 2.0"
    expect(described_class.parse("[1.0,2.0)")).to eq ">= 1.0, < 2.0"
    expect(described_class.parse("(1.0,2.0]")).to eq "> 1.0, <= 2.0"
    expect(described_class.parse("(,1.0], [1.2,)")).to eq "<= 1.0 || >= 1.2"

    # Maven defines "(,1.1), (1.1,)" as being equivalent to != 1.1. We
    # don't have a != operator in the dependency graph semantic
    # versioning model, but we do have OR so we parse it directly as
    # "< 1.1 || > 1.1"
    expect(described_class.parse("(,1.1),(1.1,)")).to eq "< 1.1 || > 1.1"

    # Some versions with text/snapshot in them
    expect(described_class.parse("1.23.47-SNAPSHOT")).to eq "= 1.23.47-SNAPSHOT"
    expect(described_class.parse("28.23.1")).to eq "= 28.23.1"

    # Invalid requirments
    # Note (1.10) is *not* a valid version
    expect(described_class.parse("(1.10)")).to eq ""
    expect(described_class.parse("(1.1,2.3))")).to eq ""
    expect(described_class.parse("1.0 1.1")).to eq ""
    expect(described_class.parse("1.0.")).to eq ""

    # Maven's requirements format is just like nuget's except it
    # *doesn't* support the wildcard format
    expect(described_class.parse("6.1.*")).to eq ""

    # Some versions have trailing "null" sections that should be stripped out
    expect(described_class.parse("[1.0.Final]")).to eq "= 1.0"
    expect(described_class.parse("[1.0.ga]")).to eq "= 1.0"
    expect(described_class.parse("[1.0.Final.GA]")).to eq "= 1.0"
    expect(described_class.parse("1.0.Abc.Beta.Final")).to eq "= 1.0.Abc.Beta"
    expect(described_class.parse("1.0.Beta.4")).to eq "= 1.0.Beta.4"
  end
end
