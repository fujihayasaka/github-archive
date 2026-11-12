require "rails_helper"

describe ManifestAdapters::Composer::Requirements do
  it "correctly parses version ranges" do
    # exact versions
    expect(described_class.parse("1.3.2")).to eq "= 1.3.2"
    expect(described_class.parse("1.0")).to eq "= 1.0"
    expect(described_class.parse("5.0")).to eq "= 5.0"
    expect(described_class.parse("v1.0.0")).to eq "= 1.0.0"
    expect(described_class.parse("4.0.0-beta")).to eq "= 4.0.0-beta"

    # specific bounds
    expect(described_class.parse(">=1.3.2")).to eq ">= 1.3.2"
    expect(described_class.parse("<=1.3.2")).to eq "<= 1.3.2"
    expect(described_class.parse(">1.3.2")).to eq "> 1.3.2"
    expect(described_class.parse("<1.3.2")).to eq "< 1.3.2"

    # wildcards
    expect(described_class.parse("1.3.*")).to eq "~> 1.3.0"
    expect(described_class.parse("1.0.*")).to eq "~> 1.0.0"
    expect(described_class.parse("1.*")).to eq "~> 1.0"

    # # tilde
    expect(described_class.parse("~1.3.2")).to eq "~> 1.3.2"
    expect(described_class.parse("~1.3")).to eq "~> 1.3"

    # # caret
    expect(described_class.parse("^1.3.2")).to eq ">= 1.3.2, < 2.0.0"
    expect(described_class.parse("^0.3.2")).to eq ">= 0.3.2, < 0.4.0"

    # AND groups
    expect(described_class.parse(">=1.0 <2.0")).to eq ">= 1.0, < 2.0"
    expect(described_class.parse(">=1.0,<2.0")).to eq ">= 1.0, < 2.0"

    # OR groups
    expect(described_class.parse(">=1.0 || <2.0")).to eq ">= 1.0 || < 2.0"

    # version range
    expect(described_class.parse("1.0 - 2.0")).to eq ">= 1.0, < 2.1"
    expect(described_class.parse("1.0.0 - 2.1.0")).to eq ">= 1.0.0, <= 2.1.0"

    # bringing in branch aliases
    expect(described_class.parse("dev-master")).to eq ""
    expect(described_class.parse("dev-trunk")).to eq ""

    # other versions - from dependabot
    expect(described_class.parse(">=1.0.0@dev")).to eq ">= 1.0.0@dev" #stability constraints
    expect(described_class.parse("^1.8@dev")).to eq ">= 1.8@dev, < 2.0" # a real life example!
    expect(described_class.parse("@dev")).to eq ">= 0"

    expect(described_class.parse(">=whatever as 1.0.0")).to eq ">= 1.0.0" #aliases

    expect(described_class.parse(">= v1.0.0")).to eq ">= 1.0.0"

    expect(described_class.parse("*")).to eq ">= 0"
    expect(described_class.parse("x")).to eq ">= 0"
    expect(described_class.parse("1.x")).to eq "~> 1.0"

    expect(described_class.parse("1.")).to eq "= 1"

    # invalid requirements
    expect(described_class.parse("(1.10)")).to eq ""
    expect(described_class.parse("(1.1,2.3))")).to eq ""
    expect(described_class.parse(">= 1.x")).to eq ""
    expect(described_class.parse("1.0-2.0")).to eq "" #invalid format checked with https://semver.mwl.be/ linked from docs

  end
end
