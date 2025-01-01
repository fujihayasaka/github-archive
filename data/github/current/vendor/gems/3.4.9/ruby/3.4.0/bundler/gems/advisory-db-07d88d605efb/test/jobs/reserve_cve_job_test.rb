# frozen_string_literal: true

require "test_helper"

class ReserveCVEJobTest < ActiveJob::TestCase
  MINIMUM_CVE_AVAILABLE = 25
  CVE_RESERVATION_AMOUNT = 25
  MINIMUM_CVE_AVAILABLE_DECEMBER = 5
  CVE_RESERVATION_AMOUNT_DECEMBER = 5

  test "does not reserve CVE if there are enough available for the current year" do
    Timecop.freeze(2022, 6, 1) do
      create_list(:cve, MINIMUM_CVE_AVAILABLE + 1)
      assert_equal MINIMUM_CVE_AVAILABLE + 1, CVE.count

      assert_difference -> { CVE.count }, 0 do
        ReserveCVEJob.new.perform
      end
    end
  end

  test "Reserves fewer CVEs in december" do
    Timecop.freeze(2022, 12, 10) do
      create_list(:cve, MINIMUM_CVE_AVAILABLE_DECEMBER - 1)
      assert_equal MINIMUM_CVE_AVAILABLE_DECEMBER - 1, CVE.count

      assert_difference -> { CVE.count }, CVE_RESERVATION_AMOUNT_DECEMBER do
        VCR.use_cassette("reserve_cve_job_december_amount") do
          ReserveCVEJob.new.perform
        end
      end

      create_list(:cve, 2)

      assert CVE.count < MINIMUM_CVE_AVAILABLE

      assert_difference -> { CVE.count }, 0 do
        ReserveCVEJob.new.perform
      end
    end
  end

  test "Doesn't batch reservations the last week of december" do
    Timecop.freeze(2022, 12, 25) do
      create(:cve)
      assert_equal 1, CVE.count

      assert_difference -> { CVE.count }, 1 do
        VCR.use_cassette("reserve_cve_job_last_week_amount") do
          ReserveCVEJob.new.perform
        end
      end

      create_list(:cve, 2)

      assert CVE.count < MINIMUM_CVE_AVAILABLE_DECEMBER

      assert_difference -> { CVE.count }, 0 do
        ReserveCVEJob.new.perform
      end
    end
  end

  test "reserves CVE for the new year if it is close" do
    Timecop.freeze(2022, 12, 29) do
      create_list(:cve, MINIMUM_CVE_AVAILABLE + 1, year: 2022)
      assert_equal 0, CVE.available.where(year: 2023).count

      assert_difference -> { CVE.available.where(year: 2023).count }, CVE_RESERVATION_AMOUNT do
        VCR.use_cassette("reserve_cve_job_new_year") do
          ReserveCVEJob.new.perform
        end
      end
    end
  end

  test "reserves CVE IDs if quantity falls below the limit" do
    Timecop.freeze(2022, 6, 1) do
      create_list(:cve, MINIMUM_CVE_AVAILABLE - 1)

      last_cve_number = CVE.last.cve_id.split("-").last.to_i
      CVEAPI::Client.any_instance
        .stubs(:reserve_cve)
        .with(amount: CVE_RESERVATION_AMOUNT, cve_year: 2022)
        .returns(Array.new(CVE_RESERVATION_AMOUNT) do |index|
          n = (last_cve_number + index + 1).to_s
          { "cve_id" => "CVE-2022-#{n}", "cve_year" => "2022" }
        end)

      assert_difference -> { ::CVE.count }, CVE_RESERVATION_AMOUNT do
        ReserveCVEJob.new.perform
      end
    end
  end

  test "it reserves the amount of CVEs specified" do
    Timecop.freeze(2022, 6, 1) do
      VCR.use_cassette("reserve_cve_job_specific_amount") do
        ReserveCVEJob.new.perform(amount: 5)
      end

      assert_equal 5, CVE.count
    end
  end

  test "reserves 25 CVEs by default" do
    Timecop.freeze(2022, 6, 1) do
      VCR.use_cassette("reserve_cve_job_default_amount") do
        ReserveCVEJob.new.perform
      end

      assert_equal 25, CVE.count
    end
  end

  test "can be forced to reserve even if enough CVEs are available" do
    Timecop.freeze(2022, 6, 1) do
      create_list(:cve, MINIMUM_CVE_AVAILABLE + 1)
      assert_equal MINIMUM_CVE_AVAILABLE + 1, CVE.count

      assert_difference -> { CVE.count }, CVE_RESERVATION_AMOUNT do
        VCR.use_cassette("reserve_cve_job_default_amount") do
          ReserveCVEJob.new.perform(force: true)
        end
      end
    end
  end
end
