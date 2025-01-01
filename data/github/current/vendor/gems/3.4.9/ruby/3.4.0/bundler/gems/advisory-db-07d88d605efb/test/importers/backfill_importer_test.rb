# frozen_string_literal: true

require "test_helper"

class BackfillImporterTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  test "knows its source" do
    assert_equal "backfill", BackfillImporter.source
  end

  test "does not allow a directory that does not exist or an empty directory" do
    assert_raises ArgumentError do
      BackfillImporter.new(feed_entries_directory: "not-a-directory")
    end

    assert_raises ArgumentError do
      empty_dir = File.join("tmp", "empty")
      Dir.mkdir(empty_dir) unless Dir.exist?(empty_dir)
      BackfillImporter.new(feed_entries_directory: empty_dir)
    end
  end

  attr_reader :test_yaml_dir

  def write_test_yamls
    @test_yaml_dir = File.join("tmp", "test-advisory-yamls")
    Dir.mkdir(test_yaml_dir) unless Dir.exist?(test_yaml_dir)

    File.write("#{test_yaml_dir}/advisory_1.yaml", <<~ADVISORY)
      ---
      identifier: backfill/go-CVE-2021-21291
      cve_id: CVE-2021-21291
      advisory_payload:
        cwe_ids:
        - CWE-601
        cvss_v3: CVSS:3.1/AV:N/AC:L/PR:N/UI:R/S:U/C:L/I:L/A:N
        cvss_v4:
        summary: Open Redirect
        references:
        - https://github.com/oauth2-proxy/oauth2-proxy/commit/780ae4f3c99b579cb2ea9845121caebb6192f725
        - https://github.com/oauth2-proxy/oauth2-proxy/releases/tag/v7.0.0
        vulnerabilities:
          0:
            ecosystem: go
            package_name: github.com/oauth2-proxy/oauth2-proxy
            vulnerable_version_range: "< 7.0.0"
            first_patched_version: 7.0.0
      raw_payload:
        version: 1
    ADVISORY

    # Second file is .yml, first one is .yaml.  Both should work
    File.write("#{test_yaml_dir}/advisory_2.yml", <<~ADVISORY)
      ---
      identifier: backfill/go-CVE-2021-21237
      cve_id: CVE-2021-21237
      advisory_payload:
        cwe_ids:
        - CWE-94
        cvss_v3: CVSS:3.1/AV:N/AC:L/PR:N/UI:N/S:U/C:L/I:L/A:L
        cvss_v4:
        summary: Arbitrary Code Execution
        references:
        - https://github.com/git-lfs/git-lfs/commit/fc664697ed2c2081ee9633010de0a7f9debea72a
        - https://github.com/git-lfs/git-lfs/releases/tag/v2.13.2
        vulnerabilities:
          0:
            ecosystem: go
            package_name: github.com/git-lfs/git-lfs/creds
            vulnerable_version_range: "< 2.13.2"
            first_patched_version: 2.13.2
      raw_payload:
        version: 1
    ADVISORY

    File.write("#{test_yaml_dir}/advisory_3.yaml", <<~ADVISORY)
      ---
      identifier: backfill/pypi-CVE-2018-7576
      cve_id: CVE-2018-7576
      advisory_payload:
        cwe_ids:
        - CWE-476
        cvss_v3: CVSS:3.0/AV:N/AC:L/PR:N/UI:R/S:U/C:N/I:N/A:H
        cvss_v4: CVSS:4.0/AV:N/AC:L/AT:N/PR:N/UI:P/VC:N/VI:N/VA:H/SC:N/SI:N/SA:N
        summary: Null pointer dereference in TensorFlow leads to exploitation
        references:
        - https://github.com/tensorflow/tensorflow/commit/c48431588e7cf8aff61d4c299231e3e925144df8
        - https://github.com/tensorflow/tensorflow
        - https://github.com/tensorflow/tensorflow/blob/master/tensorflow/security/advisory/tfsa-2018-002.md
        vulnerabilities:
          0:
            ecosystem: PyPI
            package_name: tensorflow-gpu
            vulnerable_version_range: ">= 1.0.0"
            first_patched_version: 1.6.0
      raw_payload:
        version: 1
    ADVISORY
  end

  test "imports a directory of yaml files" do
    refute AdvisoryReview.exists?(cve_id: "CVE-2021-21291")
    refute AdvisoryReview.exists?(cve_id: "CVE-2021-21237")

    write_test_yamls
    perform_enqueued_jobs(only: [ResolveFeedEntryJob]) do
      BackfillImporter.new(feed_entries_directory: test_yaml_dir).import
    end

    assert advisory = AdvisoryReview.find_by!(cve_id: "CVE-2021-21291")
    assert_equal(
      {
        "cvss_v3" => "CVSS:3.1/AV:N/AC:L/PR:N/UI:R/S:U/C:L/I:L/A:N",
        "cvss_v4" => nil,
        "cwe_ids" => ["CWE-601"],
        "summary" => "Open Redirect",
        "references" => [
          "https://github.com/oauth2-proxy/oauth2-proxy/commit/780ae4f3c99b579cb2ea9845121caebb6192f725",
          "https://github.com/oauth2-proxy/oauth2-proxy/releases/tag/v7.0.0",
        ],
        "vulnerabilities" => {
          0 => {
            "ecosystem" => "go",
            "first_patched_version" => "7.0.0",
            "package_name" => "github.com/oauth2-proxy/oauth2-proxy",
            "vulnerable_version_range" => "< 7.0.0",
          },
        },
      },
      advisory.advisory_payload,
    )

    assert AdvisoryReview.exists?(cve_id: "CVE-2021-21237")
  end

  test "import an advisory with a CVSS v4 score" do
    refute AdvisoryReview.exists?(cve_id: "CVE-2018-7576")

    write_test_yamls
    perform_enqueued_jobs(only: [ResolveFeedEntryJob]) do
      BackfillImporter.new(feed_entries_directory: test_yaml_dir).import
    end

    assert advisory = AdvisoryReview.find_by!(cve_id: "CVE-2018-7576")
    assert_equal(
      {
        "cvss_v3" => "CVSS:3.0/AV:N/AC:L/PR:N/UI:R/S:U/C:N/I:N/A:H",
        "cvss_v4" => "CVSS:4.0/AV:N/AC:L/AT:N/PR:N/UI:P/VC:N/VI:N/VA:H/SC:N/SI:N/SA:N",
        "cwe_ids" => ["CWE-476"],
        "references" => [
          "https://github.com/tensorflow/tensorflow/commit/c48431588e7cf8aff61d4c299231e3e925144df8",
          "https://github.com/tensorflow/tensorflow",
          "https://github.com/tensorflow/tensorflow/blob/master/tensorflow/security/advisory/tfsa-2018-002.md",
        ],
        "summary" => "Null pointer dereference in TensorFlow leads to exploitation",
        "vulnerabilities" => {
          0 => {
            "ecosystem" => "PyPI",
            "first_patched_version" => "1.6.0",
            "package_name" => "tensorflow-gpu",
            "vulnerable_version_range" => ">= 1.0.0",
          },
        },
      },
      advisory.advisory_payload,
    )

    assert AdvisoryReview.exists?(cve_id: "CVE-2018-7576")
  end
end
