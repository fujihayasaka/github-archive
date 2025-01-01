# typed: true
# frozen_string_literal: true

require "test_helper"

class CVEEPSSTest < GitHub::TestCase

  fixtures do
    @cve_epss = create(:cve_epss, percentage: 0.87)
  end

  def vuln_class
    CVEEPSS
  end

  def scoped?
    false
  end

  context "cve_epss" do
    test "valid cve_epss" do
      assert @cve_epss.valid?
    end

    test "should be invalid without cve_id" do
      @cve_epss.cve_id = nil
      assert_not @cve_epss.valid?
    end

    test "should be invalid with duplicate cve_id" do
      duplicate_cve_epss = @cve_epss.dup
      @cve_epss.save
      assert_not duplicate_cve_epss.valid?
    end

    test "should be valid with percentage as string" do
      @cve_epss.percentage = "0.000450000"
      assert @cve_epss.valid?
    end

    test "should be invalid without percentage" do
      invalid_cve_epss = build(:cve_epss, :invalid_percentage)
      assert_not invalid_cve_epss.valid?
      assert invalid_cve_epss.errors[:percentage].include?("can't be blank")
    end

    test "should be invalid with percentage out of range" do
      @cve_epss.percentage = 1.1
      assert_not @cve_epss.valid?
      @cve_epss.percentage = -0.1
      assert_not @cve_epss.valid?
    end

    test "should be valid with percentile as string" do
      @cve_epss.percentage = "0.160010000"
      assert @cve_epss.valid?
    end

    test "should be invalid without percentile" do
      invalid_cve_epss = build(:cve_epss, :invalid_percentile)
      assert_not invalid_cve_epss.valid?
      assert invalid_cve_epss.errors[:percentile].include?("can't be blank")
    end

    test "should be invalid with percentile out of range" do
      @cve_epss.percentile = 1.1
      assert_not @cve_epss.valid?
      @cve_epss.percentile = -0.1
      assert_not @cve_epss.valid?
    end

    test "should be valid with calculation_date as string" do
      @cve_epss.calculation_date = "2024-07-17"
      assert @cve_epss.valid?
    end

    test "should be invalid without calculation_date" do
      @cve_epss.calculation_date = nil
      assert_not @cve_epss.valid?
    end

    test "cve_epss should be associated with repository advisory and vice versa" do
      assert @cve_epss.vulnerability.present?
      assert @cve_epss.vulnerability.cve_epss.present?

      vulnerability = create(:vulnerability, :with_cve)
      @cve_epss.vulnerability = vulnerability
      @cve_epss.save!
      assert_equal vulnerability, @cve_epss.vulnerability
      assert_equal vulnerability.cve_epss, @cve_epss
    end

    test "synchronize_search_index should call synchronize_search_index on vulnerability", skip_enterprise: true do
      @cve_epss.vulnerability.expects(:synchronize_search_index).once

      @cve_epss.synchronize_search_index
    end

    test "synchronize_search_index should NOT call synchronize_search_index on vulnerability in enterprise mode", enterprise_only: true do
      # this test should verify the opposite of the the earlier test, so vulnerability should not be called
      @cve_epss.vulnerability.expects(:synchronize_search_index).never

      @cve_epss.synchronize_search_index
    end

    test "when updated, we synchronize the search index", skip_enterprise: true do
      @cve_epss.vulnerability.expects(:synchronize_search_index).once
      @cve_epss.percentage = @cve_epss.percentage - 0.01
      @cve_epss.save!
    end
  end

  context "#percentage=" do
    test "sets the percentage as a float" do
      record = CVEEPSS.new(percentage: "0.5")
      assert_equal record.percentage, 0.5
    end

    test "sets the percentage to nil if value is not present" do
      record = CVEEPSS.new(percentage: nil)
      assert_nil record.percentage
    end

    test "should convert percentage to float if value is present" do
      @cve_epss.percentage = "0.123"
      assert_equal 0.123, @cve_epss.percentage

      @cve_epss.percentage = 0.456
      assert_equal 0.456, @cve_epss.percentage

      @cve_epss.percentage = nil
      refute_nil @cve_epss.percentage
    end
  end

  context "#percentile=" do
    test "sets the percentile as a float" do
      record = CVEEPSS.new(percentile: "0.75")
      assert_equal record.percentile, 0.75
    end

    test "sets the percentile to nil if value is not present" do
      record = CVEEPSS.new(percentile: nil)
      assert_nil record.percentile
    end

    test "should convert percentile to float if value is present" do
      @cve_epss.percentile = "0.123"
      assert_equal 0.123, @cve_epss.percentile

      @cve_epss.percentile = 0.456
      assert_equal 0.456, @cve_epss.percentile

      @cve_epss.percentile = nil
      refute_nil @cve_epss.percentile
    end
  end

  context ".parse_query_qualifier" do
    test "returns empty hash for invalid query" do
      assert_equal({}, CVEEPSS.parse_query_qualifier(nil))
      assert_equal({}, CVEEPSS.parse_query_qualifier(""))
      assert_equal({}, CVEEPSS.parse_query_qualifier("foo"))
      assert_equal({}, CVEEPSS.parse_query_qualifier("0.05..1.0..2.0"))
      assert_equal({}, CVEEPSS.parse_query_qualifier(">0.05..1.0"))
      assert_equal({}, CVEEPSS.parse_query_qualifier("..1"))
      assert_equal({}, CVEEPSS.parse_query_qualifier("0.."))
      assert_equal({}, CVEEPSS.parse_query_qualifier("-0.1..1"))
      assert_equal({}, CVEEPSS.parse_query_qualifier("0..1."))
      assert_equal({}, CVEEPSS.parse_query_qualifier("foo..bar"))
    end

    test "returns range query hash" do
      assert_equal({ range: true, start: 0.05, end: 1.0 }, CVEEPSS.parse_query_qualifier("0.05..1.0"))
      assert_equal({ range: true, start: 0.0, end: 1.0 }, CVEEPSS.parse_query_qualifier("0..1"))
      assert_equal({ range: true, start: 0.0, end: 1.0 }, CVEEPSS.parse_query_qualifier("0.0..1"))
    end

    test "returns comparison query hash" do
      assert_equal({ comparison: true, operator: :">",  number: 0.3 }, CVEEPSS.parse_query_qualifier(">0.3"))
      assert_equal({ comparison: true, operator: :">=", number: 0.3 }, CVEEPSS.parse_query_qualifier(">=0.3"))
      assert_equal({ comparison: true, operator: :"<",  number: 0.3 }, CVEEPSS.parse_query_qualifier("<0.3"))
      assert_equal({ comparison: true, operator: :"<=", number: 0.3 }, CVEEPSS.parse_query_qualifier("<=0.3"))
      assert_equal({ comparison: true, operator: :"=",  number: 0.3 }, CVEEPSS.parse_query_qualifier("0.3"))
    end
  end

  context ".valid_query_qualifier?" do
    test "returns true for valid range query" do
      assert CVEEPSS.valid_query_qualifier?("0.05..1.0")
      assert CVEEPSS.valid_query_qualifier?("0..1")
      assert CVEEPSS.valid_query_qualifier?("0.0..1")
    end

    test "returns true for valid comparison query" do
      assert CVEEPSS.valid_query_qualifier?("0.3")
      assert CVEEPSS.valid_query_qualifier?(">0.3")
      assert CVEEPSS.valid_query_qualifier?(">=0.3")
      assert CVEEPSS.valid_query_qualifier?("<0.3")
      assert CVEEPSS.valid_query_qualifier?("<=0.3")
    end

    test "returns false for invalid range query" do
      refute CVEEPSS.valid_query_qualifier?("0.05..1.0..2.0")
      refute CVEEPSS.valid_query_qualifier?(">0.05..1.0")
      refute CVEEPSS.valid_query_qualifier?("..1")
      refute CVEEPSS.valid_query_qualifier?("0..")
      refute CVEEPSS.valid_query_qualifier?("-0.1..1")
      refute CVEEPSS.valid_query_qualifier?("0..1.1")
      refute CVEEPSS.valid_query_qualifier?("foo..bar")
    end

    test "returns false for invalid comparison query" do
      refute CVEEPSS.valid_query_qualifier?("3")
      refute CVEEPSS.valid_query_qualifier?("NaN")
      refute CVEEPSS.valid_query_qualifier?("-5")
      refute CVEEPSS.valid_query_qualifier?("4.b")
      refute CVEEPSS.valid_query_qualifier?("1,2,3")
    end
  end
end
