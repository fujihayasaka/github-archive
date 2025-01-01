# frozen_string_literal: true

class ReserveCVEJob < ApplicationJob
  queue_as :default

  MINIMUM_CVE_AVAILABLE = 25
  CVE_RESERVATION_AMOUNT = 25
  MINIMUM_CVE_AVAILABLE_DECEMBER = 5
  CVE_RESERVATION_AMOUNT_DECEMBER = 5

  def perform(amount: nil, force: false)
    AdvisoryDB::Lock.new("reserve_cve_job").wrap do
      cveapi_client = CVEAPI::Client.new
      reserved_cves = []
      current_year = Time.zone.now.year

      # Reduce the number of CVE's that we keep on hand in December (and don't batch at all the last week)
      # to prevent having CVEs that need to be manually rejected
      if 7.days.from_now.year > Time.zone.now.year
        minimum_threshold = 1
        amount = 1
      elsif Time.zone.now.month == 12
        minimum_threshold = MINIMUM_CVE_AVAILABLE_DECEMBER
        amount = CVE_RESERVATION_AMOUNT_DECEMBER
      end

      amount ||= CVE_RESERVATION_AMOUNT
      minimum_threshold ||= MINIMUM_CVE_AVAILABLE

      # handle special case when we are at year's end
      year_in_three_days = 3.days.from_now.year
      if year_in_three_days != current_year && CVE.available.where(year: year_in_three_days).count <= MINIMUM_CVE_AVAILABLE
        reserved_cves.concat(
          cveapi_client.reserve_cve(amount: CVE_RESERVATION_AMOUNT, cve_year: year_in_three_days),
        )
      end

      if force || CVE.available.where(year: current_year).count <= minimum_threshold
        reserved_cves.concat(
          cveapi_client.reserve_cve(amount: amount, cve_year: current_year),
        )
      end

      reserved_cves.each do |reserved_cve|
        CVE.create!({
          cve_id: reserved_cve["cve_id"],
          year: reserved_cve["cve_year"],
        })
      end
    end
  end
end
