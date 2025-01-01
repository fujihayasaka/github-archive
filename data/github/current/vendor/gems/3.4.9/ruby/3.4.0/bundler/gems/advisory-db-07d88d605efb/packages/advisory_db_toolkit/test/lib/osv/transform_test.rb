# frozen_string_literal: true

require "test_helper"
require_relative "osv_helper"

class OSVTransformTest < Minitest::Test
  include OSVHelper

  def setup
    @subject = AdvisoryDBToolkit::OSV::Transform
  end

  def test_transforms_advisory_interfaces_to_osv_using_the_schema_v1_transformer
    advisory = create_advisory_interface
    osv = @subject.to_osv(advisory)
    assert_kind_of Hash, osv
    assert_equal "1.4.0", osv["schema_version"]
  end

  def test_transforms_osv_data_to_advisory_interface_using_the_schema_v1_transformer
    initial_advisory = create_advisory_interface
    osv = @subject.to_osv(initial_advisory)
    advisory = @subject.from_osv(osv)
    assert_kind_of AdvisoryDBToolkit::OSV::Interfaces::Advisory, advisory
    assert_equal initial_advisory.ghsa_id, advisory.ghsa_id
  end

  def test_transform_osv_data_supports_multiple_semantic_versions_in_advisories
    initial_advisory = create_advisory_interface
    osv = @subject.to_osv(initial_advisory)
    osv["affected"] = [{
      "package" => { "name" => "aahframe.work", "ecosystem" => "Go" },
      "ranges" => [{ "type" => "SEMVER", "events" => [
        { "introduced" => "0" }, { "fixed" => "0.12.4" },
        { "introduced" => "1.1.0" }, { "fixed" => "1.12.4" }
      ] }],
    }]
    advisory = @subject.from_osv(osv)
    assert_equal advisory.vulnerabilities.length, 2
  end
end
