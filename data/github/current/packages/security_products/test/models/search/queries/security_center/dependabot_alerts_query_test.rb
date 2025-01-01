# typed: true
# frozen_string_literal: true

require "test_helper"

class SearchQueriesSecurityCenterDependabotAlertsQueryTest < GitHub::TestCase
  fixtures do
    @query_parser = Search::Queries::SecurityCenter::DependabotAlertsQuery
  end

  context "parse_and_normalize" do
    test "returns an empty hash when query string is empty" do
      query_string = ""
      query_hash = @query_parser.parse_and_normalize(query_string)

      assert_empty query_hash
    end

    test "returns an invalid hash when duplicate qualifiers are present" do
      query_string = "is:open severity:high,critical severity:low"
      query_hash = @query_parser.parse_and_normalize(query_string)
      invalid_hash = { is: [:invalid] }

      assert_equal invalid_hash, query_hash
    end

    test "returns an invalid hash when conflicting values are present" do
      query_string = "is:open -severity:high severity:high"
      query_hash = @query_parser.parse_and_normalize(query_string)
      invalid_hash = { is: [:invalid] }

      assert_equal invalid_hash, query_hash
    end

    test "returns a hash with the default :is qualifier-value pair if no other params are present" do
      query_string = "is:open"
      query_hash = @query_parser.parse_and_normalize(query_string)
      result_hash = { "is" => [:open] }

      assert_equal result_hash, query_hash
    end

    test "converts :is and :sort values to symbols if present" do
      query_string = "is:open sort:oldest"

      base_hash = @query_parser.parse(query_string)
      base_result_hash = { "is" => ["open"], "sort" => ["oldest"], "_literals" => [] }

      assert_equal base_result_hash, base_hash

      query_hash = @query_parser.parse_and_normalize(query_string)
      result_hash = { "is" => [:open], "sort" => :created_asc }

      assert_equal result_hash, query_hash
    end

    test "remove sort from the resulting hash if ignore_sort is true" do
      query_string = "is:open sort:oldest"

      query_hash = @query_parser.parse_and_normalize(query_string, ignore_sort: true)
      result_hash = { "is" => [:open] }

      assert_equal result_hash, query_hash
    end

    test "converts string literals into a single search phrase if present" do
      query_string = "is:open foo sort:oldest bar"

      base_hash = @query_parser.parse(query_string)
      base_result_hash = { "is" => ["open"], "sort" => ["oldest"], "_literals" => %w[foo bar] }

      assert_equal base_result_hash, base_hash

      query_hash = @query_parser.parse_and_normalize(query_string)
      result_hash = { "is" => [:open], "sort" => :created_asc, "phrase" => "foo bar" }

      assert_equal result_hash, query_hash
    end

    test "preserve case for manifest path, package, and ecosystem" do
      query_string = "is:open package:SharpZip,tar ecosystem:RubyGems,Maven,npm"
      query_hash = @query_parser.parse_and_normalize(query_string)
      result_hash = { "is" => [:open], "package" => %w[SharpZip tar], "ecosystem" => %w[RubyGems Maven npm] }

      assert_equal result_hash, query_hash

      query_string = "is:open manifest:Gemfile,Gemfile.lock"
      query_hash = @query_parser.parse_and_normalize(query_string)
      result_hash = { "is" => [:open], "manifest" => ["Gemfile", "Gemfile.lock"] }

      assert_equal result_hash, query_hash
    end

    test "handles maven group:artifact format for package" do
      query_hash = @query_parser.parse_and_normalize("is:open package:com.fasterxml.jackson.core:jackson-databind")
      result_hash = { "is" => [:open], "package" => ["com.fasterxml.jackson.core:jackson-databind"] }

      assert_equal result_hash, query_hash
    end

    test "returns a hash with optional params if provided" do
      query_string = "is:open repo:repo1,repo2 severity:critical,high"
      query_hash = @query_parser.parse_and_normalize(query_string)
      result_hash = { "is" => [:open], "repo" => %w[repo1 repo2], "severity" => %w[critical high] }

      assert_equal result_hash, query_hash
    end

    test "parses EPSS percentage values" do
      query_string = "is:open epss_percentage:0.5"
      query_hash = @query_parser.parse_and_normalize(query_string)
      refute_nil query_hash["epss_percentage"]
      assert_equal ["0.5"], query_hash["epss_percentage"]
    end

    test "normalizes state value" do
      assert_equal({ "is" => [:open] }, @query_parser.parse_and_normalize("is:open"))
      assert_equal({ "is" => [:closed] }, @query_parser.parse_and_normalize("is:closed"))
      assert_equal({ "is" => [:open] }, @query_parser.parse_and_normalize("is:Open"))
      assert_equal({ "is" => [:closed] }, @query_parser.parse_and_normalize("is:CLOSED"))
      assert_equal({ "is" => [:open, :closed] }, @query_parser.parse_and_normalize("is:open,closed"))
      assert_equal({ "is" => [:open, :closed] }, @query_parser.parse_and_normalize("is:OPeN,CLoSED"))
      assert_equal({ "is" => [:open, :closed] }, @query_parser.parse_and_normalize("is:open,closed,gibberish"))
      assert_equal({ "is" => [:invalid] }, @query_parser.parse_and_normalize("is:gibberish"))
      assert_equal({}, @query_parser.parse_and_normalize(""))
      assert_equal({}, @query_parser.parse_and_normalize(nil))
    end

    test "normalizes sort value" do
      assert_equal({ "sort" => :created_desc }, @query_parser.parse_and_normalize("sort:newest"))
      assert_equal({ "sort" => :created_asc }, @query_parser.parse_and_normalize("sort:oldest"))
      assert_equal({ "sort" => :severity }, @query_parser.parse_and_normalize("sort:severity"))
      assert_equal({ "sort" => :vulnerable_manifest_path }, @query_parser.parse_and_normalize("sort:manifest-path"))
      assert_equal({ "sort" => :affects }, @query_parser.parse_and_normalize("sort:package-name"))
      assert_equal({ "sort" => :most_important }, @query_parser.parse_and_normalize("sort:most-important", can_sort_by_most_important: true))
      assert_equal({ "sort" => :created_desc }, @query_parser.parse_and_normalize("sort:gibberish"))
      assert_equal({ "sort" => :most_important }, @query_parser.parse_and_normalize("sort:gibberish", can_sort_by_most_important: true))
      assert_equal({ "sort" => :created_desc }, @query_parser.parse_and_normalize("sort:Newest"))
      assert_equal({ "sort" => :created_asc }, @query_parser.parse_and_normalize("sort:OLDEST"))
      assert_equal({ "sort" => :severity }, @query_parser.parse_and_normalize("sort:sEvErIty"))
      assert_equal({}, @query_parser.parse_and_normalize(""))
      assert_equal({}, @query_parser.parse_and_normalize(nil))
    end

    test "normalizes severity value" do
      assert_equal({ "severity" => ["low"] }, @query_parser.parse_and_normalize("severity:low"))
      assert_equal({ "severity" => ["moderate"] }, @query_parser.parse_and_normalize("severity:medium"))
      assert_equal({ "severity" => ["moderate"] }, @query_parser.parse_and_normalize("severity:moderate"))
      assert_equal({ "severity" => ["high"] }, @query_parser.parse_and_normalize("severity:high"))
      assert_equal({ "severity" => ["critical"] }, @query_parser.parse_and_normalize("severity:critical"))
      assert_equal({ "severity" => %w[low moderate] }, @query_parser.parse_and_normalize("severity:low,medium"))
      assert_equal({ "severity" => %w[low moderate] }, @query_parser.parse_and_normalize("severity:LOW,MEDIUM"))
      assert_equal({ "severity" => %w[low moderate] }, @query_parser.parse_and_normalize("severity:low,medium,gibberish"))
      assert_equal({}, @query_parser.parse_and_normalize("severity:gibberish"))
    end

    test "normalizes relationship value" do
      assert_equal({ "relationship" => ["direct"] }, @query_parser.parse_and_normalize("relationship:DIREct"))
      assert_equal({ "relationship" => ["direct"] }, @query_parser.parse_and_normalize("relationship:direct"))
      assert_equal({}, @query_parser.parse_and_normalize(""))
    end
  end

  context "#valid_epss_qualifiers?" do
    test "returns true if specific epss value is valid" do
      # Nil and empty strings are valid
      assert @query_parser.valid_epss_qualifiers?(nil)

      # Numeric values 0.0 and 1.0 are valid
      assert @query_parser.valid_epss_qualifiers?(["0"])
      assert @query_parser.valid_epss_qualifiers?(["0.0"])
      assert @query_parser.valid_epss_qualifiers?(["0.9"])
      assert @query_parser.valid_epss_qualifiers?(["1"])
      assert @query_parser.valid_epss_qualifiers?(["0.000450000"])

      refute @query_parser.valid_epss_qualifiers?([""])
      refute @query_parser.valid_epss_qualifiers?(["=0.5"])
      refute @query_parser.valid_epss_qualifiers?(["-0.1"])
      refute @query_parser.valid_epss_qualifiers?(["1.1"])
      refute @query_parser.valid_epss_qualifiers?(["String"])
    end

    test "returns true if gt/e epss value is valid" do
      assert @query_parser.valid_epss_qualifiers?([">0", ">0.1", ">0.9", ">1", ">0.000450000"])
      assert @query_parser.valid_epss_qualifiers?([">=0", ">=0.1", ">=0.9", ">=1", ">=0.000450000"])

      refute @query_parser.valid_epss_qualifiers?([">-0.1"])
      refute @query_parser.valid_epss_qualifiers?([">1.1"])
      refute @query_parser.valid_epss_qualifiers?([">String"])
    end

    test "returns true if lt/e epss value is valid" do
      assert @query_parser.valid_epss_qualifiers?(["<0", "<0.1", "<0.9", "<1", "<0.000450000"])
      assert @query_parser.valid_epss_qualifiers?(["<=0", "<=0.1", "<=0.9", "<=1", "<=0.000450000"])

      refute @query_parser.valid_epss_qualifiers?(["<-0.1"])
      refute @query_parser.valid_epss_qualifiers?(["<1.1"])
      refute @query_parser.valid_epss_qualifiers?(["<String"])
    end

    test "returns true if epss range is valid" do
      assert @query_parser.valid_epss_qualifiers?(["0..0.5", "0.1..0.2", "0.99..0.999", "0..1", "0.000450000..0.000540000"])

      refute @query_parser.valid_epss_qualifiers?(["0..0"])
      refute @query_parser.valid_epss_qualifiers?(["1..0"])
      refute @query_parser.valid_epss_qualifiers?([">0..1"])
      refute @query_parser.valid_epss_qualifiers?(["0.."])
      refute @query_parser.valid_epss_qualifiers?(["..1"])
      refute @query_parser.valid_epss_qualifiers?(["StringA..StringB"])
    end
  end
end
