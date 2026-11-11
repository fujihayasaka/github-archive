# frozen_string_literal: true

require "csv"

namespace :advisory_db do
  desc "Re-import CVEs"
  task :reimport_cves, [:all, :cve_id] => :environment do |_task, args|
    if args[:cve_id].nil?
      # Get a list of all CVE IDs from Advisories
      cve_ids = Advisory.where.not(cve_id: nil).where.not(summary: nil).pluck(:cve_id)
      cve_ids = cve_ids.sample(1) unless args[:all]
    else
      cve_ids = args[:cve_id]
    end

    number_of_cves_to_reimport = cve_ids.count

    GitHub::Telemetry::Logs.logger.info(
      "Reimporting CVEs",
      "gh.advisory_inbox.cve_reimport_count": number_of_cves_to_reimport,
    )

    # Re-import the CVEs
    cve_ids.each_slice(100).each do |cve_slice|
      cve_slice.each do |cve|
        ImportJob.perform_now(NVDImporter.source, cve_id: cve, report_to_slack: false)
      end
    end
  end

  desc "Backfill nvd_published_at timestamp for advisories."
  task :backfill_nvd_published_at, [:dry_run] => :environment do |_task, args|
    puts "Backfilling nvd_published_at timestamp for advisories."
    dry_run = args[:dry_run]
    puts "Running as dryrun" if dry_run

    advisories = Advisory.where(nvd_published_at: nil)
    puts "Found #{advisories.count} advisories that need updating"

    updated_count = 0
    advisories.find_each do |advisory|
      nvd_published_at = advisory.advisory_review.nvd_published_at
      next unless nvd_published_at

      advisory.update_column(:nvd_published_at, nvd_published_at) unless dry_run # rubocop:disable Rails/SkipsModelValidations
      updated_count += 1
    end

    puts "Finished backfilling nvd_published_at timestamp for reviewed advisories."
    puts "Updated #{updated_count} advisories with an nvd_published_at time"
    advisories = Advisory.where(nvd_published_at: nil)
    puts "#{advisories.count} advisories did not get backfilled."
  end
end
