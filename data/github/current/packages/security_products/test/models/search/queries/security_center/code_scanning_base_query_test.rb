# typed: true
# frozen_string_literal: true

require "test_helper"
require "turboscan"

class SearchQueriesSecurityCenterCodeScanningBaseQueryTest < GitHub::TestCase
  fixtures do
    @user = create(:user)
  end

  context "autofilter methods" do
    test "it returns the value for autofilter" do
      q = create_query("autofilter:true")
      assert_equal "true", q.autofilter
      assert_equal ::Turboscan::Proto::AlertClassificationFilter::ALERT_CLASSIFICATION_FILTER_UNCLASSIFIED, q.classification_enum
      assert q.has_valid_classification?

      q = create_query("autofilter:tRuE")
      assert_equal "tRuE", q.autofilter
      assert_nil q.classification_enum
      refute q.has_valid_classification?

      q = create_query("autofilter:false")
      assert_equal "false", q.autofilter
      assert_nil q.classification_enum
      refute q.has_valid_classification?

      q = create_query("autofilter:foo")
      assert_equal "foo", q.autofilter
      assert_nil q.classification_enum
      refute q.has_valid_classification?

      q = create_query("")
      assert_nil q.autofilter
      assert_nil q.classification_enum
      assert q.has_valid_classification?
    end
  end

  context "severity methods" do
    test "returns valid array of a single severity with appropriate enum" do
      q = create_query("severity:critical")
      assert_equal ["critical"], q.severities
      assert_equal [::Turboscan::Proto::Severity::SEVERITY_CRITICAL], q.severity_enums
      assert q.has_valid_severity?

      q = create_query("severity:high")
      assert_equal ["high"], q.severities
      assert_equal [::Turboscan::Proto::Severity::SEVERITY_HIGH], q.severity_enums
      assert q.has_valid_severity?

      q = create_query("severity:medium")
      assert_equal ["medium"], q.severities
      assert_equal [::Turboscan::Proto::Severity::SEVERITY_MEDIUM], q.severity_enums
      assert q.has_valid_severity?

      q = create_query("severity:low")
      assert_equal ["low"], q.severities
      assert_equal [::Turboscan::Proto::Severity::SEVERITY_LOW], q.severity_enums
      assert q.has_valid_severity?

      q = create_query("severity:warning")
      assert_equal ["warning"], q.severities
      assert_equal [::Turboscan::Proto::Severity::SEVERITY_WARNING], q.severity_enums
      assert q.has_valid_severity?

      q = create_query("severity:note")
      assert_equal ["note"], q.severities
      assert_equal [::Turboscan::Proto::Severity::SEVERITY_NOTE], q.severity_enums
      assert q.has_valid_severity?

      q = create_query("severity:error")
      assert_equal ["error"], q.severities
      assert_equal [::Turboscan::Proto::Severity::SEVERITY_ERROR], q.severity_enums
      assert q.has_valid_severity?

      q = create_query("severity:cRiTiCaL")
      assert_equal ["cRiTiCaL"], q.severities
      assert_equal [::Turboscan::Proto::Severity::SEVERITY_CRITICAL], q.severity_enums
      assert q.has_valid_severity?

      q = create_query("severity:critical,error")
      assert_equal %w[critical error], q.severities
      assert_equal [::Turboscan::Proto::Severity::SEVERITY_CRITICAL, ::Turboscan::Proto::Severity::SEVERITY_ERROR], q.severity_enums
      assert q.has_valid_severity?

      q = create_query("severity:critical severity:error")
      assert_equal %w[critical error], q.severities
      assert_equal [::Turboscan::Proto::Severity::SEVERITY_CRITICAL, ::Turboscan::Proto::Severity::SEVERITY_ERROR], q.severity_enums
      assert q.has_valid_severity?

      q = create_query("severity:foo")
      assert_equal ["foo"], q.severities
      assert_empty q.severity_enums
      refute q.has_valid_severity?

      q = create_query("")
      assert_empty q.severities
      assert_empty q.severity_enums
      assert q.has_valid_severity?
    end

    test "returns valid list of excluded severities with appropriate enums" do
      q = create_query("severity:critical")
      assert_empty q.excluded_severities
      assert_empty q.excluded_severity_enums

      q = create_query("-severity:critical")
      assert_equal ["critical"], q.excluded_severities
      assert_equal [::Turboscan::Proto::Severity::SEVERITY_CRITICAL], q.excluded_severity_enums

      q = create_query("-severity:critical,low")
      assert_equal %w[critical low], q.excluded_severities
      assert_equal [
        ::Turboscan::Proto::Severity::SEVERITY_CRITICAL,
        ::Turboscan::Proto::Severity::SEVERITY_LOW
      ], q.excluded_severity_enums

      q = create_query("-severity:foo")
      assert_equal ["foo"], q.excluded_severities
      assert_equal [], q.excluded_severity_enums

      q = create_query("")
      assert_equal [], q.excluded_severities
      assert_equal [], q.excluded_severity_enums
    end
  end

  context "tool methods" do
    test "tool returns a single tool" do
      assert_nil create_query("is:open").tool
      assert_nil create_query("tool:").tool
      assert_equal "abc", create_query("tool:abc").tool
      assert_equal "def", create_query("tool:abc,def").tool
      assert_equal "def", create_query("tool:abc tool:def").tool
      assert_equal "abc", create_query("tool:abc -tool:def").tool
    end

    test "tools returns a list of tools" do
      assert_empty create_query("is:open").tools
      assert_empty create_query("tool:").tools
      assert_equal ["abc"], create_query("tool:abc").tools
      assert_equal %w[abc def], create_query("tool:abc,def").tools
      assert_equal %w[abc def], create_query("tool:abc tool:def").tools
      assert_equal ["abc"], create_query("tool:abc -tool:def").tools
    end

    test "excluded_tools returns a list of excluded tools" do
      assert_empty create_query("is:open").excluded_tools
      assert_empty create_query("-tool:").excluded_tools
      assert_empty create_query("tool:abc").excluded_tools
      assert_equal %w[abc def], create_query("-tool:abc,def").excluded_tools
      assert_equal ["def"], create_query("tool:abc -tool:def").excluded_tools
    end
  end

  context "rule methods" do
    test "rule returns a single rule" do
      assert_nil create_query("is:open").rule_sarif_identifier
      assert_nil create_query("rule:").rule_sarif_identifier
      assert_equal "abc", create_query("rule:abc").rule_sarif_identifier
      assert_equal "def", create_query("rule:abc,def").rule_sarif_identifier
      assert_equal "def", create_query("rule:abc rule:def").rule_sarif_identifier
      assert_equal "abc", create_query("rule:abc -rule:def").rule_sarif_identifier
    end

    test "excluded_rules returns a list of excluded rules" do
      assert_empty create_query("is:open").excluded_rule_sarif_identifiers
      assert_empty create_query("-rule:").excluded_rule_sarif_identifiers
      assert_empty create_query("rule:abc").excluded_rule_sarif_identifiers
      assert_equal %w[abc def], create_query("-rule:abc,def").excluded_rule_sarif_identifiers
      assert_equal ["def"], create_query("rule:abc -rule:def").excluded_rule_sarif_identifiers
    end
  end

  context "resolution methods" do
    test "returns valid single resolution with appropriate enum" do
      q = create_query("resolution:fixed")
      assert_equal ["fixed"], q.resolutions
      assert_equal [::Turboscan::Proto::ResultResolutionFilter::FILTER_NO_RESOLUTION], q.resolution_enums
      assert q.has_valid_resolutions?

      q = create_query("resolution:false-positive")
      assert_equal ["false-positive"], q.resolutions
      assert_equal [::Turboscan::Proto::ResultResolutionFilter::FILTER_FALSE_POSITIVE], q.resolution_enums
      assert q.has_valid_resolutions?

      q = create_query("resolution:used-in-tests")
      assert_equal ["used-in-tests"], q.resolutions
      assert_equal [::Turboscan::Proto::ResultResolutionFilter::FILTER_USED_IN_TESTS], q.resolution_enums
      assert q.has_valid_resolutions?

      q = create_query("resolution:wont-fix")
      assert_equal ["wont-fix"], q.resolutions
      assert_equal [::Turboscan::Proto::ResultResolutionFilter::FILTER_WONT_FIX], q.resolution_enums
      assert q.has_valid_resolutions?

      q = create_query("resolution:dismissed")
      assert_equal ["dismissed"], q.resolutions
      assert_same_elements [
        ::Turboscan::Proto::ResultResolutionFilter::FILTER_WONT_FIX,
        ::Turboscan::Proto::ResultResolutionFilter::FILTER_USED_IN_TESTS,
        ::Turboscan::Proto::ResultResolutionFilter::FILTER_FALSE_POSITIVE
        ], q.resolution_enums
      assert q.has_valid_resolutions?

      # doesn't include duplicate entry for more specific query in enum
      q = create_query("resolution:false-positive,dismissed")
      assert_equal %w[false-positive dismissed], q.resolutions
      assert_same_elements [
        ::Turboscan::Proto::ResultResolutionFilter::FILTER_WONT_FIX,
        ::Turboscan::Proto::ResultResolutionFilter::FILTER_USED_IN_TESTS,
        ::Turboscan::Proto::ResultResolutionFilter::FILTER_FALSE_POSITIVE
        ], q.resolution_enums
      assert q.has_valid_resolutions?

      q = create_query("resolution:fIxEd")
      assert_equal ["fIxEd"], q.resolutions
      assert_equal [::Turboscan::Proto::ResultResolutionFilter::FILTER_NO_RESOLUTION], q.resolution_enums
      assert q.has_valid_resolutions?

      q = create_query("resolution:foo")
      assert_equal ["foo"], q.resolutions
      assert_empty q.resolution_enums
      refute q.has_valid_resolutions?

      q = create_query("")
      assert_empty q.resolutions
      assert_empty q.resolution_enums
      assert q.has_valid_resolutions?
    end

    test "returns valid list of excluded resolutions with appropriate enums" do
      q = create_query("resolution:false-positive")
      assert_empty q.excluded_resolutions
      assert_empty q.excluded_resolution_enums

      q = create_query("-resolution:false-positive")
      assert_equal ["false-positive"], q.excluded_resolutions
      assert_equal [::Turboscan::Proto::ResultResolutionFilter::FILTER_FALSE_POSITIVE], q.excluded_resolution_enums

      q = create_query("-resolution:false-positive,fixed")
      assert_equal %w[false-positive fixed], q.excluded_resolutions
      assert_equal [
        ::Turboscan::Proto::ResultResolutionFilter::FILTER_FALSE_POSITIVE,
        ::Turboscan::Proto::ResultResolutionFilter::FILTER_NO_RESOLUTION
      ], q.excluded_resolution_enums

      q = create_query("-resolution:dismissed")
      assert_equal ["dismissed"], q.excluded_resolutions
      assert_same_elements [
        ::Turboscan::Proto::ResultResolutionFilter::FILTER_WONT_FIX,
        ::Turboscan::Proto::ResultResolutionFilter::FILTER_USED_IN_TESTS,
        ::Turboscan::Proto::ResultResolutionFilter::FILTER_FALSE_POSITIVE
        ], q.excluded_resolution_enums
      assert q.has_valid_resolutions?

      q = create_query("-resolution:foo")
      assert_equal ["foo"], q.excluded_resolutions
      assert_equal [], q.excluded_resolution_enums

      q = create_query("")
      assert_equal [], q.excluded_resolutions
      assert_equal [], q.excluded_resolution_enums
    end
  end

  context "tag methods" do
    test "tags returns a list of tags" do
      assert_empty create_query("is:open").tags
      assert_empty create_query("tool:").tags
      assert_equal ["abc"], create_query("tag:abc").tags
      assert_equal %w[abc def], create_query("tag:abc,def").tags
      assert_equal %w[abc def], create_query("tag:abc tag:def").tags
      assert_equal ["abc"], create_query("tag:abc -tag:def").tags
    end

    test "excluded_rules returns a list of excluded rules" do
      assert_empty create_query("is:open").excluded_tags
      assert_empty create_query("-tag:").excluded_tags
      assert_empty create_query("tag:abc").excluded_tags
      assert_equal %w[abc def], create_query("-tag:abc,def").excluded_tags
      assert_equal ["def"], create_query("tag:abc -tag:def").excluded_tags
    end
  end

  context "team methods" do
    test "single" do
      q = create_query("team:woof")
      assert_equal ["woof"], q.team_names
    end

    test "multiple by dupelicated qualifiers" do
      q = create_query("team:woof team:meow")
      assert_equal %w[woof meow], q.team_names
    end

    test "multiple comma separated" do
      q = create_query("team:woof,meow")
      assert_equal %w[woof meow], q.team_names
    end

    test "empty" do
      q = create_query("team:")
      assert_empty q.team_names
    end

    test "negate single" do
      q = create_query("-team:woof")
      assert_equal ["woof"], q.excluded_team_names
    end

    test "negate multiple" do
      q = create_query("-team:woof -team:meow")
      assert_equal %w[woof meow], q.excluded_team_names
    end

    test "negate multiple comma separated" do
      q = create_query("-team:woof,meow")
      assert_equal %w[woof meow], q.excluded_team_names
    end

    test "negate empty" do
      q = create_query("-team:")
      assert_empty q.excluded_team_names
    end

    test "mixed negation" do
      q = create_query("team:woof -team:meow")
      assert_equal ["woof"], q.team_names
      assert_equal ["meow"], q.excluded_team_names

      q = create_query("-team:woof team:meow")
      assert_equal ["woof"], q.excluded_team_names
      assert_equal ["meow"], q.team_names
    end
  end

  context "topic methods" do
    test "single" do
      q = create_query("topic:woof")
      assert_equal ["woof"], q.topics
    end

    test "multiple by dupelicated qualifiers" do
      q = create_query("topic:woof topic:meow")
      assert_equal %w[woof meow], q.topics
    end

    test "multiple comma separated" do
      q = create_query("topic:woof,meow")
      assert_equal %w[woof meow], q.topics
    end

    test "empty" do
      q = create_query("topic:")
      assert_empty q.topics
    end

    test "negate single" do
      q = create_query("-topic:woof")
      assert_equal ["woof"], q.excluded_topics
    end

    test "negate multiple" do
      q = create_query("-topic:woof -topic:meow")
      assert_equal %w[woof meow], q.excluded_topics
    end

    test "negate multiple comma separated" do
      q = create_query("-topic:woof,meow")
      assert_equal %w[woof meow], q.excluded_topics
    end

    test "negate empty" do
      q = create_query("-topic:")
      assert_empty q.excluded_topics
    end

    test "mixed negation" do
      q = create_query("topic:woof -topic:meow")
      assert_equal ["woof"], q.topics
      assert_equal ["meow"], q.excluded_topics

      q = create_query("-topic:woof topic:meow")
      assert_equal ["woof"], q.excluded_topics
      assert_equal ["meow"], q.topics
    end
  end

  context "sort methods" do
    test "returns valid sort with appropriate enum" do
      q = create_query("")
      assert_nil q.sort
      assert_nil q.sort_enum

      q = create_query("sort:created-desc")
      assert_equal "created-desc", q.sort
      assert_equal :CREATED_DESCENDING, q.sort_enum

      q = create_query("sort:created-asc")
      assert_equal "created-asc", q.sort
      assert_equal :CREATED_ASCENDING, q.sort_enum

      q = create_query("sort:updated-desc")
      assert_equal "updated-desc", q.sort
      assert_equal :UPDATED_DESCENDING, q.sort_enum

      q = create_query("sort:updated-asc")
      assert_equal "updated-asc", q.sort
      assert_equal :UPDATED_ASCENDING, q.sort_enum

      q = create_query("sort:Created-Desc")
      assert_equal "created-desc", q.sort
      assert_equal :CREATED_DESCENDING, q.sort_enum

      q = create_query("sort:CREATED-ASC")
      assert_equal "created-asc", q.sort
      assert_equal :CREATED_ASCENDING, q.sort_enum

      q = create_query("sort:uPdAtEd-DeSc")
      assert_equal "updated-desc", q.sort
      assert_equal :UPDATED_DESCENDING, q.sort_enum

      q = create_query("sort:fake")
      assert_equal "fake", q.sort
      assert_nil q.sort_enum
    end
  end

  context "#is_valid?" do
    test "empty query is valid" do
      q = create_query("")
      assert q.is_valid?
    end

    test "unqualified terms is valid" do
      q = create_query("foo")
      # code scanning supports raw query string
      assert q.is_valid?
    end

    test "unknown qualifier is valid" do
      q = create_query("foo:bar")
      # valid for now; the query parsing doesn't distinguish unknown qualifiers from unqualified terms
      assert q.is_valid?
    end

    test "qualifier without value is invalid" do
      refute create_query("severity:").is_valid?
      refute create_query("severity: foo").is_valid?
      refute create_query("severity: is:open").is_valid?
      refute create_query("severity: is:open foo").is_valid?
    end

    test "unknown state is invalid" do
      q = create_query("is:fake")
      refute q.is_valid?
    end

    test "unknown severity is invalid" do
      q = create_query("severity:fake")
      refute q.is_valid?
    end

    test "unknown severity negation is ignored" do
      q = create_query("-severity:fake")
      assert q.is_valid?
    end

    test "unknown sort is ignored" do
      q = create_query("sort:fake")

      assert q.is_valid?
    end

    test "unknown resolution is invalid" do
      q = create_query("resolution:fake")
      refute q.is_valid?
    end

    test "unknown resolution negation is ignored" do
      q = create_query("-resolution:fake")
      assert q.is_valid?
    end
  end

  context "#qualifier_selected" do
    test "returns true if qualifier exists with the specified value" do
      assert create_query("severity:high").qualifier_selected?(name: :severity, value: "high")
      assert create_query("severity:High").qualifier_selected?(name: :severity, value: "high")
      assert create_query("severity:HIGH").qualifier_selected?(name: :severity, value: "high")
      assert create_query("severity:hIgH").qualifier_selected?(name: :severity, value: "high")
    end
  end

  def create_query(query)
    Search::Queries::SecurityCenter::CodeScanningBaseQuery.new(query)
  end
end
