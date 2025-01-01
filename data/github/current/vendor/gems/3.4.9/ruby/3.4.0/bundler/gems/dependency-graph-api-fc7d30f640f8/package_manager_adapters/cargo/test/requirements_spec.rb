require "spec_helper"
require "active_support"
require "active_support/core_ext"
require_relative "../lib/cargo/requirements"

describe Cargo::Requirements do
  it "correctly expands a Cargo single bound into well-formed DG version requirements" do
    # Cargo expands these into ranges by default! these aren't pinned
    trials = [
      {
        input: "1",
        expected: ">= 1.0.0, < 2.0.0",
      },
      {
        input: "1.2",
        expected: ">= 1.2.0, < 2.0.0",
      },
      {
        input: "234",
        expected: ">= 234.0.0, < 235.0.0",
      },
      {
        input: "22.33",
        expected: ">= 22.33.0, < 23.0.0",
      },
      {
        input: "1.2.3",
        expected: ">= 1.2.3, < 2.0.0",
      },
      {
        input: "2.0.1",
        expected: ">= 2.0.1, < 3.0.0",
      },
      {
        input: "11.22.33",
        expected: ">= 11.22.33, < 12.0.0",
      },
    ]

    trials.each do |t|
      # default (unprefixed behavior)
      got, failed = described_class.parse(t[:input])
      expect(failed).to (be false),  "input: #{t[:input]}; expected: #{t[:expected]}; got: #{got}"
      expect(got).to (eq t[:expected]), "input: #{t[:input]}; expected: #{t[:expected]}; got: #{got}"

      # caret prefixed bounds are identical to default
      caret_prefixed = "^" + t[:input]
      got, failed = described_class.parse(caret_prefixed)
      expect(failed).to (be false),  "input: #{caret_prefixed}; expected: #{t[:expected]}; got: #{got}"
      expect(got).to (eq t[:expected]), "input: #{caret_prefixed}; expected: #{t[:expected]}; got: #{got}"
    end
  end

  it "correctly special-cases Cargo expansions for single bound with tilde prefix" do
    # tilde mode introduces stricter upper bounds in the expansion, when major version is >0
    trials = [
      {
        input: "~1",
        expected: ">= 1.0.0, < 2.0.0",
      },
      {
        input: "~1.0",
        expected: ">= 1.0.0, < 1.1.0",
      },
      {
        input: "~1.0.0",
        expected: ">= 1.0.0, < 1.1.0",
      },
      {
        input: "~2.2",
        expected: ">= 2.2.0, < 2.3.0",
      },
      {
        input: "~2.2.2",
        expected: ">= 2.2.2, < 2.3.0",
      },
      {
        input: "~1.2.3",
        expected: ">= 1.2.3, < 1.3.0",
      },
      {
        input: "~1.2.0",
        expected: ">= 1.2.0, < 1.3.0",
      },
      {
        input: "~2.0.0",
        expected: ">= 2.0.0, < 2.1.0",
      },
      {
        input: "~2.0.1",
        expected: ">= 2.0.1, < 2.1.0",
      },
      {
        input: "~11.22.33",
        expected: ">= 11.22.33, < 11.23.0",
      },
      {
        input: "~1.222.3",
        expected: ">= 1.222.3, < 1.223.0",
      },
    ]

    trials.each do |t|
      got, failed = described_class.parse(t[:input])
      expect(failed).to (be false),  "input: #{t[:input]}; expected: #{t[:expected]}; got: #{got}"
      expect(got).to (eq t[:expected]), "input: #{t[:input]}; expected: #{t[:expected]}; got: #{got}"
    end
  end

  it "correctly special-cases expansions for Cargo single bounds with major version 0" do
    # Cargo applies special-case rules for strict bounds expansion when major version is 0
    trials = [
      # special case: 0-major only specified element:
      # upper bound is expanded like default/caret
      {
        input: "0",
        expected: ">= 0.0.0, < 1.0.0",
      },
      # special case: 0-major version, any minor, patch unspecified:
      # use "tilde-mode" strict upper bound behavior
      {
        input: "0.0",
        expected: ">= 0.0.0, < 0.1.0",
      },
      {
        input: "0.1",
        expected: ">= 0.1.0, < 0.2.0",
      },
      {
        input: "0.2",
        expected: ">= 0.2.0, < 0.3.0",
      },
      # if major and minor are specified as "0" versions
      # (no wildcard or missing elements!) it's a special case
      {
        input: "0.0.0",
        expected: ">= 0.0.0, < 0.0.1",
      },
      {
        input: "0.0.2",
        expected: ">= 0.0.2, < 0.0.3",
      },
      # 0-major version, >0 in minor, any patch value:
      # use "tilde-mode" strict upper bound behavior
      {
        input: "0.1.0",
        expected: ">= 0.1.0, < 0.2.0",
      },
      {
        input: "0.2.3",
        expected: ">= 0.2.3, < 0.3.0",
      },
      {
        input: "0.222.333",
        expected: ">= 0.222.333, < 0.223.0",
      },
    ]

    # 0-major indices should be treated the same regardless of prefix
    # so we test all three variants and expect the same results
    trials.each do |t|
      got, failed = described_class.parse(t[:input])
      expect(failed).to (be false),  "input: #{t[:input]}; expected: #{t[:expected]}; got: #{got}"
      expect(got).to (eq t[:expected]), "input: #{t[:input]}; expected: #{t[:expected]}; got: #{got}"

      caret_prefixed = "^" + t[:input]
      got, failed = described_class.parse(caret_prefixed)
      expect(failed).to (be false),  "input: #{caret_prefixed}; expected: #{t[:expected]}; got: #{got}"
      expect(got).to (eq t[:expected]), "input: #{caret_prefixed}; expected: #{t[:expected]}; got: #{got}"

      tilde_prefixed = "~" + t[:input]
      got, failed = described_class.parse(tilde_prefixed)
      expect(failed).to (be false),  "input: #{tilde_prefixed}; expected: #{t[:expected]}; got: #{got}"
      expect(got).to (eq t[:expected]), "input: #{tilde_prefixed}; expected: #{t[:expected]}; got: #{got}"
    end
  end

  it "expands Cargo single bounds with wildcards as per Cargo spec" do
    trials = [
      {
        input: "*",
        expected: ">= 0.0.0",
      },
      {
        input: "0.*",
        expected: ">= 0.0.0, < 1.0.0",
      },
      {
        input: "0.0.*",
        expected: ">= 0.0.0, < 0.1.0",
      },
      {
        input: "1.*",
        expected: ">= 1.0.0, < 2.0.0",
      },
      {
        input: "1.2.*",
        expected: ">= 1.2.0, < 1.3.0",
      },
      {
        input: "44.55.*",
        expected: ">= 44.55.0, < 44.56.0",
      },
    ]

    trials.each do |t|
      got, failed = described_class.parse(t[:input])
      expect(failed).to (be false),  "input: #{t[:input]}; expected: #{t[:expected]}; got: #{got}"
      expect(got).to (eq t[:expected]), "input: #{t[:input]}; expected: #{t[:expected]}; got: #{got}"
    end
  end

  it "expands Cargo single bounds with mixed prefixes (expansion modes) and wildcards are treated corrected" do
    trials = [
      {
        input: "^0.*",
        expected: ">= 0.0.0, < 1.0.0",
      },
      {
        input: "~0.*",
        expected: ">= 0.0.0, < 1.0.0",
      },
      {
        input: "^0.0.*",
        expected: ">= 0.0.0, < 0.1.0",
      },
      {
        input: "~0.0.*",
        expected: ">= 0.0.0, < 0.1.0",
      },
      # Above major version 0, tilde and std expansion differ,
      # but only when wildcard expansion rules don't trump both
      {
        input: "^1.*",
        expected: ">= 1.0.0, < 2.0.0",
      },
      {
        input: "~1.*",
        expected: ">= 1.0.0, < 2.0.0",
      },
      {
        # wierd special case for std/caret mode + patch wildcard!
        input: "^1.2.*",
        expected: ">= 1.2.0, < 1.3.0",
      },
      {
        input: "~1.2.*",
        expected: ">= 1.2.0, < 1.3.0",
      },
      {
        input: "^44.55.*",
        expected: ">= 44.55.0, < 44.56.0",
      },
      {
        input: "~44.55.*",
        expected: ">= 44.55.0, < 44.56.0",
      },
    ]

    trials.each do |t|
      got, failed = described_class.parse(t[:input])
      expect(failed).to (be false),  "input: #{t[:input]}; expected: #{t[:expected]}; got: #{got}"
      expect(got).to (eq t[:expected]), "input: #{t[:input]}; expected: #{t[:expected]}; got: #{got}"
    end
  end

  it "captures arbitrary dash-separated suffix on any fully-specified, well-formed Cargo semver" do
    trials = [
      {
        input: "1.2.3-alpha.9",
        expected: ">= 1.2.3-alpha.9, < 2.0.0",
      },
      {
        input: "1.2.0-dev",
        expected: ">= 1.2.0-dev, < 2.0.0",
      },
      {
        input: "~1.2.3-dev",
        expected: ">= 1.2.3-dev, < 1.3.0",
      },
      {
        input: "4.0.0-platform_apple][e",
        expected: ">= 4.0.0-platform_apple][e, < 5.0.0",
      },
      {
        input: "~5.19.333-release-123-💥",
        expected: ">= 5.19.333-release-123-💥, < 5.20.0",
      },
      {
        input: "^6.6.0-route",
        expected: ">= 6.6.0-route, < 7.0.0",
      },
      {
        input: ">= 1.0.0-platform(vic_20), <=3",
        expected: ">= 1.0.0-platform(vic_20), < 4.0.0",
      },
      {
        input: ">= 1.0.0-platform(vic_20), <=3.1.2-beta.6",
        expected: ">= 1.0.0-platform(vic_20), <= 3.1.2-beta.6",
      },
      {
        input: "0.1.2-baz",
        expected: ">= 0.1.2-baz, < 0.2.0",
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
      "=*",
      "^*",
      "~*",
      "*-alpha.1",
      "&2.3.4",
      "1.💥.3",
      "1.2.x-beta",
      "1,2.4",
      "2.3_4",
      "^2.3_4",
      "~2.3_4",
      "1.2.3.4",
      "^1.2.3.4",
      "~1.2.3.4",
      "1.2.3_beta",
      "1.2.a",
      "~1.2.a",
      "^1.2.a",
      "2.3.4.5-beta",
      "~2.3.4.5-beta",
      "^2.3.4.5-beta",
      # suffixes are not allowed on wildcard or partially-specified bounds
      "^2.4.*-yolo.🙈.🙉.🙊-beta.456",
      "0.1-dev",
      "~0-foobar",
      "1.*-platform(vic_20)",
      # add more examples here!
    ]

    trials.each do |input|
      got, failed = described_class.parse(input)
      expect(failed).to (be true), "expected to fail on invalid input: #{input}"
    end
  end

  it "correctly resolves/expands single bounds with equality comparison operator according to Cargo spec" do
    trials = [
      # partially specified versions with "=" operator are equivalent to
      # expansions on single bounds without an operator, in tilde mode
      {
        input: "=1",
        expected: ">= 1.0.0, < 2.0.0",
      },
      {
        input: "=1.2",
        expected: ">= 1.2.0, < 1.3.0",
      },
      {
        input: "=1.*",
        expected: ">= 1.0.0, < 2.0.0",
      },
      {
        input: "=1.2.*",
        expected: ">= 1.2.0, < 1.3.0",
      },
      # fully specified version with "=" operator must match a package release exactly
      {
        input: "=1.2.3",
        expected: "= 1.2.3",
      },
      {
        input: "=11.222.3333",
        expected: "= 11.222.3333",
      },
      {
        input: "=1.3.4-rc5",
        expected: "= 1.3.4-rc5",
      },
      {
        input: "=0",
        expected: ">= 0.0.0, < 1.0.0",
      },
      {
        input: "=0.0",
        expected: ">= 0.0.0, < 0.1.0",
      },
      {
        input: "=0.3",
        expected: ">= 0.3.0, < 0.4.0",
      },
      {
        input: "=0.*",
        expected: ">= 0.0.0, < 1.0.0",
      },
      {
        input: "=0.0.*",
        expected: ">= 0.0.0, < 0.1.0",
      },
      {
        input: "=0.3.*",
        expected: ">= 0.3.0, < 0.4.0",
      },
      # nonsense, and Cargo defaults to version 0.1.0 when initializing projects, but legal
      {
        input: "=0.0.0",
        expected: "= 0.0.0",
      },
    ]

    trials.each do |t|
      got, failed = described_class.parse(t[:input])
      expect(failed).to (be false),  "input: #{t[:input]}; expected: #{t[:expected]}; got: #{got}"
      expect(got).to (eq t[:expected]), "input: #{t[:input]}; expected: #{t[:expected]}; got: #{got}"
    end
  end

  it "correctly resolves/expands single bounds with non-equality comparison operator according to Cargo spec" do
    trials = [
      # single comparison-operator bounds are only "expanded" to account for partial-spec or wildcards
      {
        input: ">1",
        expected: ">= 2.0.0",
      },
      {
        input: ">1.2",
        expected: ">= 1.3.0",
      },
      {
        input: ">1.*",
        expected: ">= 2.0.0",
      },
      {
        input: ">=1.2.*",
        expected: ">= 1.2.0",
      },
      # fully specified version with a comparison operator are accepted as-is
      {
        input: "<1.2.3",
        expected: "< 1.2.3",
      },
      {
        input: "<=11.222.3333",
        expected: "<= 11.222.3333",
      },
      {
        input: ">1.3.4-rc5",
        expected: "> 1.3.4-rc5",
      },
      {
        input: ">=0",
        expected: ">= 0.0.0",
      },
      {
        input: ">0.1",
        expected: ">= 0.2.0",
      },
      {
        input: ">0.3",
        expected: ">= 0.4.0",
      },
      {
        input: ">0.*",
        expected: ">= 1.0.0",
      },
      {
        input: ">0.0.*",
        expected: ">= 0.1.0",
      },
      {
        input: ">0.3.*",
        expected: ">= 0.4.0",
      },
      # nonsense, and Cargo defaults to version 0.1.0 when initializing new projects, but legal
      {
        input: "=0.0.0",
        expected: "= 0.0.0",
      },
      {
        input: ">0.0.0",
        expected: "> 0.0.0",
      },
      {
        input: "<0.0.0",
        expected: "< 0.0.0",
      },
    ]

    trials.each do |t|
      got, failed = described_class.parse(t[:input])
      expect(failed).to (be false),  "input: #{t[:input]}; expected: #{t[:expected]}; got: #{got}"
      expect(got).to (eq t[:expected]), "input: #{t[:input]}; expected: #{t[:expected]}; got: #{got}"
    end
  end


  it "correctly resolves/expands pairs of bounds according to Cargo spec" do
    trials = [
      {
        input: ">1, <3",
        expected: ">= 2.0.0, < 3.0.0",
      },
      {
        input: ">1.2, <3.4",
        expected: ">= 1.3.0, < 3.4.0",
      },
      {
        input: ">1.2.3, <3.4.5",
        expected: "> 1.2.3, < 3.4.5",
      },
      # a pair of fully-specified bounds can safely capture suffixes, if present
      {
        input: ">1.2.3-alpha, <3.4.5-beta",
        expected: "> 1.2.3-alpha, < 3.4.5-beta",
      },
      {
        input: ">1.*, <3.*",
        expected: ">= 2.0.0, < 3.0.0",
      },
      {
        input: ">1.2.*, <3.4.*",
        expected: ">= 1.3.0, < 3.4.0",
      },
      {
        input: ">=1, <=3",
        expected: ">= 1.0.0, < 4.0.0",
      },
      {
        input: ">=1.2, <=3.4",
        expected: ">= 1.2.0, < 3.5.0",
      },
      {
        input: ">=1.2.3, <=3.4.5",
        expected: ">= 1.2.3, <= 3.4.5",
      },
      # a single suffix on either fully-specified range is also safe to capture
      {
        input: ">=1.2.3-beta.3, <=3.4.5",
        expected: ">= 1.2.3-beta.3, <= 3.4.5",
      },
      {
        input: ">=1.2.3, <=3.4.5-beta.7",
        expected: ">= 1.2.3, <= 3.4.5-beta.7",
      },
      {
        input: ">=1.*, <=3.*",
        expected: ">= 1.0.0, < 4.0.0",
      },
      {
        input: ">=1.2.*, <=3.4.*",
        expected: ">= 1.2.0, < 3.5.0",
      },

      # fixes misordered but otherwise well-formed version range pairs
      {
        input: "<3.0.0, >=1.0.0",
        expected: ">= 1.0.0, < 3.0.0",
      },
      {
        input: "<=3.0.0, >1.0.0",
        expected: "> 1.0.0, <= 3.0.0",
      },
      {
        input: "<4.1, >=2",
        expected: ">= 2.0.0, < 4.1.0",
      },
      {
        input: "<4.0.0-rc4, >=3.2.6-dev",
        expected: ">= 3.2.6-dev, < 4.0.0-rc4",
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
      "=1.2.3, <2.3.4",
      "=0.1.2, =0.1.3",
      ">1, <3, <=2.4",
      ">1.2, >2.3",
      "<=5.1.2, <=5.1.3",
      ">2.0.0, =3.0.0",
      ">*, <2",
      ">=1.2, <*",
      ">=~1.2.3, <3.0.0",
      ">=^1.2.3, <3.0.0",
      ">=1.2.3, <~3.0.0",
      ">=1.2.3, <^3.0.0",
      ">1.2.*-beta",
      "=1.*-beta",
      "<2.3-beta",
      "<2-beta",
      "<=2.*-beta",
      # add more examples here!
    ]

    trials.each do |input|
      got, failed = described_class.parse(input)
      expect(failed).to (be true), "expected to fail on invalid input: #{input}"
    end
  end
end
