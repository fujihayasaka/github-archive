# frozen_string_literal: true

require "test_helper"

class CVETest < ActiveSupport::TestCase
  test "requires a CVE id" do
    cve = build(:cve, cve_id: nil)
    refute cve.save
  end

  test "does not accept an invalid CVE id" do
    cve = build(:cve, cve_id: "INVALID-2022-1234")
    refute cve.save
  end

  test "requires a year" do
    cve = build(:cve, year: nil)
    refute cve.save
  end

  test "requires the year match the CVE id" do
    cve = build(:cve, cve_id: "CVE-2021-1234", year: 2022)
    refute cve.save
  end

  test "belongs to a CVE review" do
    cve_id = "CVE-2022-1234"
    cve_review = create(:cve_review, assigned_cve_id: cve_id)
    cve = create(:cve, cve_id: cve_id, year: 2022)
    assert_equal cve_review, cve.cve_review
  end

  test "#first_available_cve_id_for_year returns nil if there is not an available CVE for a specific year" do
    assert_equal 0, CVE.count

    refute CVE.first_available_cve_id_for_year(2022)
  end

  test "#first_available_cve_id_for_year returns the CVE ID when available" do
    create(:cve, cve_id: "CVE-2022-0004", year: 2022)
    create(:cve, cve_id: "CVE-2022-0006", year: 2022)
    create(:cve, cve_id: "CVE-2022-0005", year: 2022)
    assert_equal "CVE-2022-0004", CVE.first_available_cve_id_for_year(2022)

    create(:cve, cve_id: "CVE-2022-0003", year: 2022)
    assert_equal "CVE-2022-0003", CVE.first_available_cve_id_for_year(2022)
  end
end
