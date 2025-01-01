# frozen_string_literal: true

require "test_helper"

class RustsecAdvisoryTest < ActiveSupport::TestCase
  test "initialize_from_path returns an instance whose raw_payload uses UTF-8 encoding" do
    rustsec_advisory = nil

    VCR.use_cassette("rustsec_RUSTSEC-2020-0089.yml") do
      rustsec_advisory = RustsecAdvisory.initialize_from_path("crates/nanorand/RUSTSEC-2020-0089.md")
    end

    assert_equal Encoding::UTF_8, rustsec_advisory.raw_payload.encoding
  end

  test "withdrawn status is included in advisory payload" do
    raw_payload = <<~RAW_PAYLOAD
      ```toml
      [advisory]
      id = "RUSTSEC-2019-0031"
      package = "spin"
      date = "2019-11-21"
      informational = "unmaintained"
      url = "https://github.com/mvdnes/spin-rs/commit/7516c80"
      withdrawn = "2020-10-08"

      [versions]
      patched = []
      unaffected = [">= 0"] # workaround for `yanked = true` not removing the advisory
      ```

      # spin is no longer actively maintained

      The author of the `spin` crate does not have time or interest to maintain it.

      Consider the following alternatives (all of which support `no_std`):

      - [`conquer-once`](https://github.com/oliver-giersch/conquer-once)
      - [`lock_api`](https://crates.io/crates/lock_api) (a subproject of `parking_lot`)
        - [`spinning_top`](https://github.com/rust-osdev/spinning_top) spinlock crate built on `lock_api`
      - [`spinning`](https://github.com/4lDO2/spinning-rs)
    RAW_PAYLOAD

    importer_objects = RustsecAdvisory.new(raw_payload: raw_payload, path: "crates/spin/RUSTSEC-2019-0031.md").importer_objects

    importer_objects.each { |obj| assert obj.dig("advisory_payload", "withdrawn") }
  end

  test "#vulnerabilities properly parses patched and unaffected" do
    raw_payload = generate_raw_payload(
      patched: [">= 300.0.4"],
      unaffected: ["< 300.0.0"],
    )
    rustsec_advisory = RustsecAdvisory.new(raw_payload: raw_payload, path: "crates/github-test/RUSTSEC-2022-0123.md")

    assert_equal({
      0 => {
        ecosystem: "rust",
        package_name: "github-test",
        vulnerable_version_range: ">= 300.0.0",
        first_patched_version: ">= 300.0.4",
      },
    }, rustsec_advisory.vulnerabilities)
  end

  test "#vulnerabilities propertly parses data when unaffected is an empty array" do
    raw_payload = generate_raw_payload(patched: [">= 300.0.4"], unaffected: [])
    rustsec_advisory = RustsecAdvisory.new(raw_payload: raw_payload, path: "crates/github-test/RUSTSEC-2022-0123.md")

    assert_equal({
      0 => {
        ecosystem: "rust",
        package_name: "github-test",
        vulnerable_version_range: nil,
        first_patched_version: ">= 300.0.4",
      },
    }, rustsec_advisory.vulnerabilities)
  end

  test "#vulnerabilities properly parses data when unaffected is missing" do
    raw_payload = generate_raw_payload(patched: [">= 300.0.4"], unaffected: [])
      .sub("\nunaffected = []", "")
    rustsec_advisory = RustsecAdvisory.new(raw_payload: raw_payload, path: "crates/github-test/RUSTSEC-2022-0123.md")

    assert_equal({
      0 => {
        ecosystem: "rust",
        package_name: "github-test",
        vulnerable_version_range: nil,
        first_patched_version: ">= 300.0.4",
      },
    }, rustsec_advisory.vulnerabilities)
  end

  test "#vulnerabilities properly parses data when patched is empty, but there is unaffected" do
    raw_payload = generate_raw_payload(patched: [], unaffected: ["< 300.0.0"])
    rustsec_advisory = RustsecAdvisory.new(raw_payload: raw_payload, path: "crates/github-test/RUSTSEC-2022-0123.md")

    assert_equal({
      0 => {
        ecosystem: "rust",
        package_name: "github-test",
        vulnerable_version_range: ">= 300.0.0",
        first_patched_version: nil,
      },
    }, rustsec_advisory.vulnerabilities)
  end

  test "#informational is properly parsed" do
    raw_payload = generate_raw_payload(
      patched: [">= 1.2.5"],
      unaffected: ["=1.2.0", "=1.2.1"],
      type: ["unmaintained"],
    )
    rustsec_advisory = RustsecAdvisory.new(raw_payload: raw_payload, path: "crates/github-test/RUSTSEC-2022-0098.md")
    assert_equal ["unmaintained"], rustsec_advisory.type
  end

  test "#vulnerabilities properly parses unaffected with equal signs" do
    # e.g. https://cs.github.com/rustsec/advisory-db/blob/48214447dfbbd79dadf9fbd9b3eeb9d877b3126c/crates/time/RUSTSEC-2020-0071.md?q=repo%3ARustSec%2Fadvisory-db+path%3Acrates%2F+%22unaffected+%3D+%5B%5C%22%3D%22#L38
    raw_payload = generate_raw_payload(
      patched: [">= 1.2.5"],
      unaffected: ["=1.2.0", "=1.2.1"],
    )
    rustsec_advisory = RustsecAdvisory.new(raw_payload: raw_payload, path: "crates/github-test/RUSTSEC-2022-0123.md")

    assert_equal({
      0 => {
        ecosystem: "rust",
        package_name: "github-test",
        vulnerable_version_range: nil,
        first_patched_version: ">= 1.2.5, 1.2.0",
      },
      1 => {
        ecosystem: "rust",
        package_name: "github-test",
        vulnerable_version_range: nil,
        first_patched_version: "1.2.1",
      },
    }, rustsec_advisory.vulnerabilities)
  end

  def generate_raw_payload(patched: [], unaffected: [], type: ["maintained"])
    <<~RAW_PAYLOAD
      ```toml
      [advisory]
      id = "RUSTSEC-2022-0123"
      package = "github-test"
      aliases = ["CVE-2022-1234"]
      categories = ["denial-of-service"]
      date = "2022-08-08"
      informational = #{type}
      url = "https://www.github.com/advisories/GHSA-1234-5678-9012"

      [versions]
      patched = #{patched}
      unaffected = #{unaffected}
      ```

      # Lorem ipsum dolor sit amet

      Consectetur adipiscing elit, sed do.

      Eiusmod tempor.
    RAW_PAYLOAD
  end
end
