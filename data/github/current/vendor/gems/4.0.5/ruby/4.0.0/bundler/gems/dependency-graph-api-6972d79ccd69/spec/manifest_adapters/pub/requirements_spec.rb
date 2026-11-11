require "spec_helper"
require "active_support"
require "active_support/core_ext"
require_relative "../../../app/manifest_adapters/manifest_adapters/pub/requirements"

describe ManifestAdapters::Pub::Requirements do
  it "correctly expands a Pub single bound into well-formed DG version requirements" do
    trials = [
      {
        input: "",
        expected: "*",
      },
      {
        input: "any",
        expected: "*",
      },
      {
        input: "0.1.2",
        expected: "= 0.1.2",
      },
      {
        input: "1.2.3",
        expected: "= 1.2.3",
      },
      {
        input: "33.44.55",
        expected: "= 33.44.55",
      },
    ]

    trials.each do |t|
      got, failed = described_class.parse(t[:input])
      expect(failed).to (be false),  "input: #{t[:input]}; expected: #{t[:expected]}; got: #{got}"
      expect(got).to (eq t[:expected]), "input: #{t[:input]}; expected: #{t[:expected]}; got: #{got}"
    end
  end

  it "correctly special-cases Pub expansions for single bound with caret prefix" do
    trials = [
      {
        input: "^1.2.3",
        expected: ">= 1.2.3, < 2.0.0",
      },
      {
        input: "^33.44.55",
        expected: ">= 33.44.55, < 34.0.0",
      },
      {
        input: "^0.0.0",
        expected: ">= 0.0.0, < 0.1.0",
      },
      {
        input: "^0.1.2",
        expected: ">= 0.1.2, < 0.2.0",
      },
      {
        input: "^0.55.66",
        expected: ">= 0.55.66, < 0.56.0",
      },
    ]

    trials.each do |t|
      got, failed = described_class.parse(t[:input])
      expect(failed).to (be false),  "input: #{t[:input]}; expected: #{t[:expected]}; got: #{got}"
      expect(got).to (eq t[:expected]), "input: #{t[:input]}; expected: #{t[:expected]}; got: #{got}"
    end
  end

  it "captures arbitrary dash-separated suffix on any fully-specified, well-formed Pub semver" do
    trials = [
      {
        input: "0.1.2-baz",
        expected: "= 0.1.2-baz",
      },
      {
        input: "1.2.3-alpha.9",
        expected: "= 1.2.3-alpha.9",
      },
      {
        input: "1.2.0-dev",
        expected: "= 1.2.0-dev",
      },
      {
        input: "^0.1.2-dev",
        expected: ">= 0.1.2-dev, < 0.2.0",
      },
      {
        input: "^1.2.3-dev",
        expected: ">= 1.2.3-dev, < 2.0.0",
      },
      {
        input: "4.0.0-platform_apple][e",
        expected: "= 4.0.0-platform_apple][e",
      },
      {
        input: "^5.19.333-release-123-💥",
        expected: ">= 5.19.333-release-123-💥, < 6.0.0",
      },
      {
        input: "^6.6.0-route",
        expected: ">= 6.6.0-route, < 7.0.0",
      },
      {
        input: ">=1.0.0-platform(vic_20) <=3.0.0",
        expected: ">= 1.0.0-platform(vic_20), <= 3.0.0",
      },
      {
        input: ">=1.0.0-platform(vic_20) <=3.1.2-beta.6",
        expected: ">= 1.0.0-platform(vic_20), <= 3.1.2-beta.6",
      },
    ]

    trials.each do |t|
      got, failed = described_class.parse(t[:input])
      expect(failed).to (be false),  "input: #{t[:input]}; expected: #{t[:expected]}; got: #{got}"
      expect(got).to (eq t[:expected]), "input: #{t[:input]}; expected: #{t[:expected]}; got: #{got}"
    end
  end

  it "captures arbitrary plus-separated prerelease suffix on any fully-specified, well-formed Pub semver" do
    trials = [
      {
        input: "0.1.2+baz",
        expected: "= 0.1.2+baz",
      },
      {
        input: "1.2.3+alpha.9",
        expected: "= 1.2.3+alpha.9",
      },
      {
        input: "1.2.0+dev",
        expected: "= 1.2.0+dev",
      },
      {
        input: "^0.1.2+dev",
        expected: ">= 0.1.2+dev, < 0.2.0",
      },
      {
        input: "^1.2.3+dev",
        expected: ">= 1.2.3+dev, < 2.0.0",
      },
      {
        input: "4.0.0+platform_apple][e",
        expected: "= 4.0.0+platform_apple][e",
      },
      {
        input: "^5.19.333+release-123-💥",
        expected: ">= 5.19.333+release-123-💥, < 6.0.0",
      },
      {
        input: "^6.6.0+route",
        expected: ">= 6.6.0+route, < 7.0.0",
      },
      {
        input: ">=1.0.0+platform(vic_20) <=3.0.0",
        expected: ">= 1.0.0+platform(vic_20), <= 3.0.0",
      },
      {
        input: ">=1.0.0+platform(vic_20) <=3.1.2+beta.6",
        expected: ">= 1.0.0+platform(vic_20), <= 3.1.2+beta.6",
      },
    ]

    trials.each do |t|
      got, failed = described_class.parse(t[:input])
      expect(failed).to (be false),  "input: #{t[:input]}; expected: #{t[:expected]}; got: #{got}"
      expect(got).to (eq t[:expected]), "input: #{t[:input]}; expected: #{t[:expected]}; got: #{got}"
    end
  end

  it "fails to parse or expand invalid single-bound version range specs" do
    trials = [
      ">=",
      "^",
      "<",
      "*-alpha.1",
      "&2.3.4",
      "1.💥.3",
      "1.2.x-beta",
      "1,2.4",
      "2.3_4",
      "^2.3_4",
      "2",
      "2.3",
      "1.2.3.4",
      "^1.2.3.4",
      "1.2.3_beta",
      "1.x",
      "1.2.x",
      "1.x.3",
      "x.2.3",
      "^1.2.x",
      "2.3.4.5-beta",
      "^2.3.4.5-beta",
      "^2.4+yolo.🙈.🙉.🙊-beta.456",
      "0.1+dev",
      "000.0+foobar",
      "1+platform(vic_20)",
      # add more examples here!
    ]

    trials.each do |input|
      got, failed = described_class.parse(input)
      expect(failed).to (be true), "expected to fail on invalid input: #{input}"
    end
  end

  it "correctly resolves/expands single bounds with non-equality comparison operator according to Pub spec" do
    trials = [
      {
        input: ">1.0.0",
        expected: "> 1.0.0",
      },
      {
        input: ">=1.2.0",
        expected: ">= 1.2.0",
      },
      {
        input: ">= 1.2.0",
        expected: ">= 1.2.0",
      },
      {
        input: "<4.3.2",
        expected: "< 4.3.2",
      },
      {
        input: "< 4.3.2",
        expected: "< 4.3.2",
      },
      {
        input: ">0.1.2",
        expected: "> 0.1.2",
      },
      {
        input: ">=0.1.2",
        expected: ">= 0.1.2",
      },
      {
        input: "<1.2.3+prerelease-foobar.7",
        expected: "< 1.2.3+prerelease-foobar.7",
      },
      {
        input: "<=11.222.3333+alpha",
        expected: "<= 11.222.3333+alpha",
      },
      {
        input: ">1.3.4-rc5",
        expected: "> 1.3.4-rc5",
      },
      {
        input: ">=1.3.4-rc5",
        expected: ">= 1.3.4-rc5",
      },
      {
        input: "0.0.0",
        expected: "= 0.0.0",
      },
      {
        input: ">0.0.0",
        expected: "> 0.0.0",
      },
      {
        input: ">=0.0.0",
        expected: ">= 0.0.0",
      },
      {
        input: "<=0.0.0",
        expected: "<= 0.0.0",
      },
    ]

    trials.each do |t|
      got, failed = described_class.parse(t[:input])
      expect(failed).to (be false),  "input: #{t[:input]}; expected: #{t[:expected]}; got: #{got}"
      expect(got).to (eq t[:expected]), "input: #{t[:input]}; expected: #{t[:expected]}; got: #{got}"
    end
  end

  it "correctly resolves/expands pairs of bounds according to Pub spec" do
    trials = [
      {
        input: ">=1.2.3 <3.0.0",
        expected: ">= 1.2.3, < 3.0.0",
      },
      {
        input: ">1.2.3 <3.4.5",
        expected: "> 1.2.3, < 3.4.5",
      },
      {
        input: ">=1.2.3 <=3.4.5",
        expected: ">= 1.2.3, <= 3.4.5",
      },
      # handles unexpected spaces between range op and semver
      {
        input: ">= 0.5.0 <1.0.0",
        expected: ">= 0.5.0, < 1.0.0",
      },
      {
        input: ">=0.5.0 < 1.0.0",
        expected: ">= 0.5.0, < 1.0.0",
      },
      # a pair of fully-specified bounds can safely capture suffixes, if present
      {
        input: ">1.2.3-alpha <3.4.5-beta",
        expected: "> 1.2.3-alpha, < 3.4.5-beta",
      },
      {
        input: ">1.2.3+alpha <3.4.5+beta",
        expected: "> 1.2.3+alpha, < 3.4.5+beta",
      },
      {
        input: ">=1.2.3+pre.2 <=3.4.5-dev.5",
        expected: ">= 1.2.3+pre.2, <= 3.4.5-dev.5",
      },
      # a single suffix on either fully-specified range is also safe to capture
      {
        input: ">=1.2.3-beta.3 <=3.4.5",
        expected: ">= 1.2.3-beta.3, <= 3.4.5",
      },
      {
        input: ">=1.2.3 <=3.4.5-beta.7",
        expected: ">= 1.2.3, <= 3.4.5-beta.7",
      },
      # fixes misordered but otherwise well-formed version range pairs
      {
        input: "<3.0.0 >=1.0.0",
        expected: ">= 1.0.0, < 3.0.0",
      },
      {
        input: "<=3.0.0 >1.0.0",
        expected: "> 1.0.0, <= 3.0.0",
      },
      {
        input: "<=3.0.0 > 1.0.0",
        expected: "> 1.0.0, <= 3.0.0",
      },
      {
        input: "<= 3.0.0 >1.0.0",
        expected: "> 1.0.0, <= 3.0.0",
      },
      {
        input: "<4.1.3-next >=2.0.0+pre",
        expected: ">= 2.0.0+pre, < 4.1.3-next",
      },
      {
        input: "<4.0.0+rc4 >=3.2.6-dev",
        expected: ">= 3.2.6-dev, < 4.0.0+rc4",
      },
    ]

    trials.each do |t|
      got, failed = described_class.parse(t[:input])
      expect(failed).to (be false),  "input: #{t[:input]}; expected: #{t[:expected]}; got: #{got}"
      expect(got).to (eq t[:expected]), "input: #{t[:input]}; expected: #{t[:expected]}; got: #{got}"
    end
  end

  it "fails to parse or expand invalid version range bounds" do
    trials = [
      "1.2.3, <2.3.4",
      "0.1.2 0.1.3",
      "^0.1.2 <0.1.3",
      ">=1.0.0 <3.1",
      ">1.2 >2.3",
      "<=5.1.2 <=5.1.3",
      ">2.0.0 =3.0.0",
      ">2.3, <=3.0.0",
      ">=1.2. <2.0.0",
      ">=1.2.3 <^3.0.0",
      ">=^1.2.3 <3.0.0",
      "=1.2.3 <3.0.0+foo",
      ">=1.2.3, <^3.0.0",
      "<0.0.0",
      # add more examples here!
    ]

    trials.each do |input|
      got, failed = described_class.parse(input)
      expect(failed).to (be true), "expected to fail on invalid input: #{input}"
    end
  end
end
