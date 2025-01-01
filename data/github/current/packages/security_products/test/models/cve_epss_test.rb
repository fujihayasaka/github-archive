# typed: true
# frozen_string_literal: true

require "test_helper"

class CVEEPSSTest < GitHub::TestCase

  fixtures do
    @cve_epss = create(:cve_epss)
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

    test "should convert percentage to float if value is present" do
      @cve_epss.percentage = "0.123"
      assert_equal 0.123, @cve_epss.percentage

      @cve_epss.percentage = 0.456
      assert_equal 0.456, @cve_epss.percentage

      @cve_epss.percentage = nil
      refute_nil @cve_epss.percentage
    end

    test "should convert percentile to float if value is present" do
      @cve_epss.percentile = "0.123"
      assert_equal 0.123, @cve_epss.percentile

      @cve_epss.percentile = 0.456
      assert_equal 0.456, @cve_epss.percentile

      @cve_epss.percentile = nil
      refute_nil @cve_epss.percentile
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
    end
  end
end
