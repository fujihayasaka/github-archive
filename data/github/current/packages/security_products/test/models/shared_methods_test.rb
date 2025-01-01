# typed: true
# frozen_string_literal: true

require "test_helper"

module Vulnerability::SharedMethodsTest
  extend ActiveSupport::Concern
  extend T::Helpers

  requires_ancestor { VulnerabilityModelTest }

  included do
    T.bind(self, T.class_of(VulnerabilityModelTest))

    context "validation" do
      test "strips leading or trailing whitespace from identifiers" do
        vulnerability_with_white_source_id = build_vulnerability white_source_id: " WS-1900-0005 "
        assert vulnerability_with_white_source_id.valid?
        assert_equal "WS-1900-0005", vulnerability_with_white_source_id.white_source_id

        vulnerability_with_cve_id = build_vulnerability cve_id: " CVE-1900-0001 "
        assert vulnerability_with_cve_id.valid?
        assert_equal "CVE-1900-0001", vulnerability_with_cve_id.cve_id
      end

      test "coerces blank strings to nil for identifiers" do
        vulnerability_with_white_source_id = build_vulnerability white_source_id: " "
        assert vulnerability_with_white_source_id.valid?
        assert_nil vulnerability_with_white_source_id.white_source_id
      end

      test "cvss_v3 does not accept a vector string that obeys the format, but has invalid key-value pairs" do
        # PR:X is an invalid pair.
        cvss_v3 = "CVSS:3.1/AV:L/AC:L/PR:X/UI:N/S:U/C:L/I:H/A:H"
        vulnerability = build_vulnerability cvss_v3: cvss_v3
        refute_predicate vulnerability, :valid?
      end

      test "severity can be nil" do
        vulnerability = create_vuln severity: nil
        assert_predicate vulnerability, :valid?
        assert_nil vulnerability.reload.severity
      end

      test "arbitrary classifications are not allowed" do
        vulnerability = build_vulnerability classification: "invalid"
        refute_predicate vulnerability, :valid?
      end
    end

    test "it has many vulnerable version ranges" do
      vulnerability = create_vuln with_ranges: 0

      attrs1 = {
        affects:     "rails",
        requirements: ">= 4.0.0, <= 4.2.0",
        fixed_in:    "4.2.1",
        vulnerability_id: vulnerability.id
      }

      attrs2 = {
        affects:     "rails",
        requirements: ">= 5.0.0, <= 5.0.9",
        fixed_in:    "5.1.0",
        vulnerability_id: vulnerability.id
      }


      create :vulnerable_version_range, attrs1
      create :vulnerable_version_range, attrs2

      assert_equal 2, vulnerability.vulnerable_version_ranges.count
    end

    test "it has many cwes" do
      vulnerability = create_vuln
      cwe_reference1 = create :cwe_reference, source: vulnerability
      cwe_reference2 = create :cwe_reference, source: vulnerability

      assert_same_elements [cwe_reference1.cwe, cwe_reference2.cwe], vulnerability.cwes
    end

    test "it has one repository advisory" do
      advisory = create(:repository_advisory)

      attrs = { ghsa_id: advisory.ghsa_id, affects: "rake" }
      attrs = attrs.merge({ scope: "innersource", security_advisory_id: advisory.id, advisory_repository_id: advisory.repository_id }) if scoped?
      vulnerability = create_vuln attrs
      assert_equal advisory, vulnerability.repository_advisory
    end

    context ".disclosed" do
      test "excludes non-public ecosystems" do
        # vulns on public ecosystems
        vuln_a = create_vuln :published_vulnerability, ecosystem: "npm", affects: "testpackage"
        vuln_b = create_vuln :published_vulnerability, ecosystem: "maven", affects: "testpackage2"

        assert vuln_a.disclosed?
        assert vuln_b.disclosed?
        # vuln on a non-public ecosystem (uses special test_preview_eco which will always be private)
        vuln_c = create_vuln :published_vulnerability, ecosystem: "test_preview_eco", affects: "testpackage3"
        refute vuln_c.disclosed?
        # vuln with mix of ranges, some public, some preview
        vuln_d = create_vuln :published_vulnerability, ecosystem: "npm", affects: "testpackage"
        create :vulnerable_version_range, :preview, vulnerability_id: vuln_d.id
        assert vuln_d.disclosed?

        disclosed_vulns = vuln_class.disclosed
        assert_includes disclosed_vulns, vuln_a
        assert_includes disclosed_vulns, vuln_b
        refute_includes disclosed_vulns, vuln_c
        assert_includes disclosed_vulns, vuln_d
      end

      test "includes unreviewed advisories" do
        vuln1 = create_vuln status: :unreviewed
        vuln2 = create_vuln :published_vulnerability, ecosystem: "test_preview_eco", affects: "testpackage"

        assert_predicate vuln1, :disclosed?
        refute_predicate vuln2, :disclosed?

        disclosed_vulns = vuln_class.disclosed

        assert_includes disclosed_vulns, vuln1
        refute_includes disclosed_vulns, vuln2
      end
    end

    context "#process_alerts" do
      test "creates a vulnerability alerting event" do
        vulnerability = create_vuln :published_vulnerability

        assert_difference -> { VulnerabilityAlertingEvent.count }, 1 do
          vulnerability.process_alerts(actor: @admin)
        end

        alerting_event = VulnerabilityAlertingEvent.last

        alerting_event_vuln = get_associated_vulnerability(T.must(alerting_event).with_scope(:open_source))
        assert_equal vulnerability, alerting_event_vuln
        assert_predicate alerting_event, :on_process_alerts?
        assert_equal @admin, T.must(alerting_event).actor
        refute_predicate alerting_event, :processed?
        refute_predicate alerting_event, :finished?
      end

      test "creates a vulnerable version range alerting process for each range" do
        vulnerability = create_vuln :published_vulnerability, with_ranges: 2

        assert_difference -> { VulnerableVersionRangeAlertingProcess.count }, vulnerability.vulnerable_version_ranges.size do
          vulnerability.process_alerts
        end

        alerting_event = VulnerabilityAlertingEvent.last
        vulnerability.vulnerable_version_ranges.each do |range|
          alerting_process = VulnerableVersionRangeAlertingProcess.where(vulnerable_version_range_id: range.id).last
          assert_equal alerting_event, T.must(alerting_process).vulnerability_alerting_event
          assert_equal range, T.must(alerting_process).vulnerable_version_range
          refute_predicate alerting_event, :processed?
        end
      end

      test "enqueues a job for each range" do
        vulnerability = create_vuln :published_vulnerability, with_ranges: 2

        assert_enqueued_jobs vulnerability.vulnerable_version_ranges.size, only: VulnerableVersionRangeCreateVulnerabilityAlertsJob, queue: "vulnerability_identification" do
          vulnerability.process_alerts
        end

        vulnerability.vulnerable_version_ranges.each do |range|
          alerting_process = VulnerableVersionRangeAlertingProcess.where(vulnerable_version_range_id: range.id).last
          assert_enqueued_with(job: VulnerableVersionRangeCreateVulnerabilityAlertsJob, args: [T.must(alerting_process).id], queue: "vulnerability_identification")
        end
      end

      test "can specify a subset of ranges" do
        vulnerability = create_vuln :published_vulnerability, with_ranges: 2

        assert_difference -> { VulnerableVersionRangeAlertingProcess.count }, 1 do
          assert_enqueued_jobs 1, only: VulnerableVersionRangeCreateVulnerabilityAlertsJob, queue: "vulnerability_identification" do
            vulnerability.process_alerts(range_ids: [vulnerability.vulnerable_version_ranges.first.id])
          end
        end
      end

      test "errors if the vulnerability isn't published" do
        vulnerability = create_vuln :withdrawn

        assert_no_enqueued_jobs do
          assert_raises ArgumentError do
            vulnerability.process_alerts
          end
        end
      end

      test "does not process alerts for malware advisories" do
        vulnerability = create_vuln :published_vulnerability, :malware

        assert_no_difference -> { VulnerabilityAlertingEvent.count } do
          vulnerability.process_alerts(actor: @admin)
        end
      end

      test "does not process alerts for advisory on ecosystem dependency graph does not support" do
        vulnerability = create_vuln :published_vulnerability, ecosystem: "erlang"

        assert_no_difference -> { VulnerabilityAlertingEvent.count } do
          vulnerability.process_alerts(actor: @admin)
        end
      end

      test "does not process alerts for advisory on ecosystem that is not public" do
        VulnerableVersionRange.any_instance.stubs(:has_public_ecosystem?).returns(false)
        vulnerability = create_vuln :published_vulnerability, ecosystem: "actions"

        assert_no_difference -> { VulnerabilityAlertingEvent.count } do
          vulnerability.process_alerts(actor: @admin)
        end
      end
    end

    context "#affects" do
      test "it returns a uniq list of affected packages" do
        vulnerability = create_vuln with_ranges: 0
        create :vulnerable_version_range, vulnerability_id: vulnerability.id, affects: "rails", requirements: ">= 4.0.0, <= 4.2.0"
        create :vulnerable_version_range, vulnerability_id: vulnerability.id, affects: "rails", requirements: ">= 5.0.0, <= 5.0.9"

        assert_equal ["rails"], vuln_class.find(vulnerability.id).affects # pull from db to avoid memoization
      end
    end

    test "provides a CVSS v3 overall score" do
      vulnerability = create_vuln cvss_v3: nil
      assert_equal 0.0, vulnerability.cvss_v3_score

      vulnerability.cvss_v3 = "CVSS:3.1/invalid-stuff-here"
      assert_equal 0.0, vulnerability.cvss_v3_score

      vulnerability.update!(cvss_v3: "CVSS:3.1/AV:P/AC:L/PR:N/UI:N/S:C/C:H/I:H/A:H")
      assert_equal 7.7, vulnerability.cvss_v3_score

      vulnerability.update!(cvss_v3: "CVSS:3.0/AV:N/AC:L/PR:L/UI:R/S:U/C:H/I:H/A:H")
      assert_equal 8.0, vulnerability.cvss_v3_score
    end

    def assert_approx_time(expected, actual, delta: 5)
      assert(
        ((actual.to_time - delta)..(actual.to_time + delta)).cover?(expected),
        "Expected #{actual} to equal #{expected}, +/- #{delta} seconds",
      )
    end

    context "#enqueue_deletion_of_withdrawn_alerts" do
      test "it queues up a job" do
        vulnerability = create_vuln

        assert_enqueued_with(job: WithdrawRepositoryVulnerabilityAlertsJob, args: [{ vulnerability_id: vulnerability.id }], queue: "vulnerability_identification") do
          vulnerability.enqueue_deletion_of_withdrawn_alerts
        end
      end
    end

    context "#vulnerable_versions" do
      test "it returns a list of vulnerable version ranges" do
        vulnerability = create_vuln with_ranges: 0
        create :vulnerable_version_range,
          vulnerability_id: vulnerability.id,
          affects:     "rails",
          requirements: ">= 4.0.0, <= 4.2.0"
        create :vulnerable_version_range,
          vulnerability_id: vulnerability.id,
          affects:     "rails",
          requirements: ">= 5.0.0, <= 5.0.9"

        assert_same_elements [
          "rails >= 4.0.0, <= 4.2.0",
          "rails >= 5.0.0, <= 5.0.9",
        ], vuln_class.find(vulnerability.id).vulnerable_versions # pull from db to avoid memoization
      end
    end

    context "#dependency_graph_supported" do
      test "correctly filters out vulnerabilities that are not supported by dependency graph" do
        go_vulnerability = get_associated_vulnerability(create(:vulnerable_version_range, :with_scoped_vulnerability, ecosystem: "go"))
        erlang_vulnerability = get_associated_vulnerability(create(:vulnerable_version_range, :with_scoped_vulnerability, ecosystem: "erlang"))

        vulns_with_vvrs = vuln_class.includes(:vulnerable_version_ranges)

        assert_equal 2, vulns_with_vvrs.all.count
        assert_equal 1, vulns_with_vvrs.dependency_graph_supported.count
      end

      test "filters out vulnerabilities who have no vulnerable version ranges with an ecosystem that is supported by dependency graph" do
        vulnerability_a = get_associated_vulnerability(create(:vulnerable_version_range, :with_scoped_vulnerability, ecosystem: "RubyGems"))
        create(:vulnerable_version_range, vulnerability_id: vulnerability_a.id)
        vulnerability_b = get_associated_vulnerability(create(:vulnerable_version_range, :with_scoped_vulnerability, ecosystem: "test_preview_eco"))
        vulnerability_c = get_associated_vulnerability(create(:vulnerable_version_range, :with_scoped_vulnerability, ecosystem: "npm"))
        assert_equal 3, vuln_class.count

        actual_vulnerabilities = vuln_class.dependency_graph_supported

        assert_equal 2, actual_vulnerabilities.length
        assert_includes actual_vulnerabilities, vulnerability_a
        assert_includes actual_vulnerabilities, vulnerability_c
      end
    end

    context "#identifier" do
      test "returns cve_id if cve_id and white_source_id are both set" do
        vuln = build_vulnerability cve_id: "CVE-2019-1111", white_source_id: "WS-2019-3333"
        assert_equal "CVE-2019-1111", vuln.identifier
      end

      test "returns ghsa id if white_source_id and npm_id are set, but cve_id is nil" do
        vuln = build_vulnerability cve_id: nil, npm_id: 1234, white_source_id: "WS-2019-3333"
        assert_equal vuln.ghsa_id, vuln.identifier
      end
    end

    context "#readable_by?" do
      test "is false if on a preview platform" do
        vulnerability = create_vuln :preview

        refute vulnerability.disclosed?
        refute vulnerability.readable_by?(@rando)
      end

      test "is false if simulated" do
        vulnerability = create_vuln :published_vulnerability, simulation: true

        refute vulnerability.disclosed?
        refute vulnerability.readable_by?(@rando)
      end

      test "is true if disclosed" do
        vulnerability = create_vuln :published_vulnerability

        assert vulnerability.disclosed?
        assert vulnerability.readable_by?(@rando)
      end

      test "is always true for staff" do
        vulnerability = create_vuln :published_vulnerability, simulation: true

        refute vulnerability.disclosed?
        assert vulnerability.readable_by?(@admin)
      end
    end

    context "#description_with_references" do
      test "includes references section" do
        reference = create(:vulnerability_reference)
        create(:scoped_vulnerability, id: reference.vulnerability.id, ghsa_id: reference.vulnerability.ghsa_id)
        reference.reload
        vulnerability = get_associated_vulnerability(reference.with_scope(:open_source))

        assert_equal <<~DEFAULT, vulnerability.description_with_references
          #{vulnerability.description}
          ### References
          - #{reference.url}
        DEFAULT
      end

      test "does not include references section if no references are present" do
        vulnerability = create_vuln

        assert_equal vulnerability.description, vulnerability.description_with_references
      end
    end

    context "#description_text" do
      test "removes html tags" do
        vulnerability = create_vuln :published_vulnerability, description: "### Impact\nThe function [MakeGrapplerFunctionItem](https://github.com/tensorflow/tensorflow/blob/master/tensorflow/core/grappler/utils/functions.cc#L221) takes arguments that determine the sizes of inputs and outputs."
        expected  = "Impact\nThe function MakeGrapplerFunctionItem takes arguments that determine the sizes of inputs and outputs."
        assert_equal expected, vulnerability.description_text
      end
    end

    context "#permalink" do
      test "returns an advisory db link for a publicly disclosed vulnerability" do
        ghsa_id = generate(:ghsa_id)
        vulnerability = create_vuln ghsa_id: ghsa_id

        assert_equal "https://github.com/advisories/#{ghsa_id}", vulnerability.permalink

        assert_equal "https://github.com/advisories/#{ghsa_id}", vulnerability.permalink(include_host: true)

        assert_equal "/advisories/#{ghsa_id}", vulnerability.permalink(include_host: false)
      end
    end

    test "#target_for_conditional_access returns :no_target_for_conditional_access" do
      vuln = create_vuln cve_id: nil, white_source_id: nil
      assert_equal :no_target_for_conditional_access, vuln.target_for_conditional_access
    end

    test "#async_target_for_conditional_access returns :no_target_for_conditional_access" do
      vuln = create_vuln cve_id: nil, white_source_id: nil
      assert_equal :no_target_for_conditional_access, vuln.async_target_for_conditional_access.sync
    end

    test "filters out unreviewed advisories" do
      vulnerability1 = create_vuln status: "unreviewed"
      vulnerability2 = create_vuln :vulnerability_with_range, status: "unreviewed"
      vulnerability3 = create_vuln :vulnerability_with_range, status: "published"
      vulnerability4 = create_vuln :vulnerability_with_range, status: "published"

      assert_equal 4, vuln_class.all.count
      assert_equal 2, vuln_class.has_been_reviewed.count

      refute_includes vuln_class.has_been_reviewed, vulnerability1
      refute_includes vuln_class.has_been_reviewed, vulnerability2
    end

    test "filters out advisories without severities" do
      vulnerability1 = create_vuln :vulnerability_with_range, severity: "high"
      vulnerability2 = create_vuln :vulnerability_with_range, severity: "critical"
      vulnerability3 = create_vuln :vulnerability_with_range, severity: nil

      assert_equal 3, vuln_class.all.count

      assert_equal 2, vuln_class.has_a_severity.count

      refute_includes vuln_class.has_a_severity, vulnerability3
    end

    test "works as a Flipper actor" do
      vuln = create_vuln
      feature = GitHub.flipper[:test_feature_flag]

      feature.enable
      assert feature.enabled?(vuln)
      feature.disable
      refute feature.enabled?(vuln)
      feature.enable(vuln)
      assert feature.enabled?(vuln)
      feature.disable(vuln)
      refute feature.enabled?(vuln)
    end

    [:description, :summary].each do |field|
      test "supports emoji for #{field}" do
        models = if scoped?
          [:scoped_vulnerability, :scoped_published_vulnerability]
        else
          [:vulnerability, :published_vulnerability]
        end

        models.each do |model|
          vuln = create(model, field => "we ❤️ emojis")

          assert_multibyte_tracked_changes(vuln, field)
        end
      end
    end

    context "malware?" do
      test "false if the vulnerability is not classified as malware" do
        vulnerability = create_vuln
        refute_predicate vulnerability, :malware?
      end

      test "true if the vulnerability is classified as malware" do
        vulnerability = create_vuln :malware
        assert_predicate vulnerability, :malware?
      end
    end

    context "#severity_score" do
      test "generates a score from the severity if no CVSS present" do
        vulnerability = create_vuln severity: "critical", cvss_v3: nil, cvss_v4: nil

        assert_nil vulnerability.cvss_v3
        assert_nil vulnerability.cvss_v4
        assert_equal 9.0, vulnerability.severity_score
      end

      test "generates a score from cvss_v3 if present" do
        vulnerability = create_vuln cvss_v3: "CVSS:3.1/AV:N/AC:H/PR:H/UI:R/S:C/C:H/I:H/A:H", cvss_v4: nil

        refute_nil vulnerability.cvss_v3
        assert_nil vulnerability.cvss_v4
        assert_equal 7.7, vulnerability.severity_score
      end

      test "generates a score from cvss_v4 if present", feature_enabled: :advisory_db_cvss_v4 do
        vulnerability = create_vuln cvss_v3: nil, cvss_v4: "CVSS:4.0/AV:N/AC:H/AT:P/PR:L/UI:A/VC:H/VI:H/VA:L/SC:H/SI:L/SA:H"

        assert_nil vulnerability.cvss_v3
        refute_nil vulnerability.cvss_v4
        assert_equal 8.7, vulnerability.severity_score
      end

      test "defaults to generating a score from cvss_v4 if both cvss_v3 and cvss_v4 are present", feature_enabled: :advisory_db_cvss_v4 do
        vulnerability = create_vuln(
          cvss_v3: "CVSS:3.1/AV:N/AC:H/PR:H/UI:R/S:C/C:H/I:H/A:H",
          cvss_v4: "CVSS:4.0/AV:N/AC:H/AT:P/PR:L/UI:A/VC:H/VI:H/VA:L/SC:H/SI:L/SA:H"
        )

        refute_nil vulnerability.cvss_v3
        refute_nil vulnerability.cvss_v4
        assert_equal 8.7, vulnerability.severity_score
      end

      test "defaults to generating a score from cvss_v3 if both cvss_v3 and cvss_v4 are present and the feature flag is disabled", feature_disabled: :advisory_db_cvss_v4 do
        vulnerability = create_vuln(
          cvss_v3: "CVSS:3.1/AV:N/AC:H/PR:H/UI:R/S:C/C:H/I:H/A:H",
          cvss_v4: "CVSS:4.0/AV:N/AC:H/AT:P/PR:L/UI:A/VC:H/VI:H/VA:L/SC:H/SI:L/SA:H"
        )

        refute_nil vulnerability.cvss_v3
        refute_nil vulnerability.cvss_v4
        assert_equal 7.7, vulnerability.severity_score
      end

      test "ignores cvss if severity differs from cvss severity" do
        vulnerability = create_vuln(
          severity: "low",
          cvss_v4: "CVSS:4.0/AV:N/AC:H/AT:P/PR:L/UI:A/VC:H/VI:H/VA:L/SC:H/SI:L/SA:H"
        )

        refute_nil vulnerability.cvss_v4
        assert_equal 0.1, vulnerability.severity_score
      end
    end
  end
end

class VulnerabilityModelTest < GitHub::TestCase
  include StringFromBinaryTestHelper
  extend T::Helpers

  def vuln_class
    raise NotImplementedError
  end

  def scoped?
    raise NotImplementedError
  end

  def common_test_fixtures
    @admin = create :staff_admin_user
    @rando = create :user
  end

  def create_vuln(*args, &block)
    # For now, in order to handle more complex factories we must simply duplicate them
    # in the scoped vulnerability factory with a `scoped_` prefix. The factories used
    # in this test suite go here
    shared_factories = [:published_vulnerability, :vulnerability_with_range]

    unless shared_factories.include?(args[0])
      args = [:vulnerability] + args
    end

    args[0] = ("scoped_" + args[0].to_s).to_sym if scoped?

    create *T.unsafe(args), &block
  end

  def build_vulnerability(*args, &block)
    factory = scoped? ? :scoped_vulnerability : :vulnerability
    build *T.unsafe([factory] + args), &block
  end

  def get_associated_vulnerability(associated)
    if scoped?
      associated.with_scope(:open_source).scoped_vulnerability
    else
      associated.vulnerability
    end
  end
end
