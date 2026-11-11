require "rails_helper"

describe ManifestAdapters::Nuget::Requirements do
  it "correctly parses Nuget version ranges" do
    # Lovingly taken from Maven Requiremnts test
    expect(described_class.parse("1.0")).to eq "= 1.0"
    expect(described_class.parse("1.*")).to eq ">= 1, < 2"
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

    expect(described_class.parse("(,1.1),(1.1,)")).to eq "< 1.1 || > 1.1"

    expect(described_class.parse("1.23.47-SNAPSHOT")).to eq "= 1.23.47-SNAPSHOT"
    expect(described_class.parse("28.23.1")).to eq "= 28.23.1"

    # Invalid requirments
    # Note (1.10) is *not* a valid version
    expect(described_class.parse("(1.10)")).to eq ""
    expect(described_class.parse("(1.1,2.3))")).to eq ""
    expect(described_class.parse("1.0 1.1")).to eq ""
  end
end

describe ManifestAdapters::Nuget::Requirements::Transformer do
  context "wildcard_upper_bound" do
    it "increments" do
      expect(described_class.wildcard_upper_bound("6.")).to eq("7")
      expect(described_class.wildcard_upper_bound("6.3.")).to eq("6.4")
      expect(described_class.wildcard_upper_bound("6.3-alpha.")).to eq("6.4")
    end
  end
  context "wildcard_lower_bound" do
    it "decrements" do
      expect(described_class.wildcard_lower_bound("6.")).to eq("6")
      expect(described_class.wildcard_lower_bound("6.3.")).to eq("6.3")
      expect(described_class.wildcard_lower_bound("6.3-alpha.")).to eq("6.3-alpha")
    end
  end
end
