# typed: true
# frozen_string_literal: true

require "#{Rails.root}/config/environment"

# Load the initial set of compliance reports into a multi-tenant stamp.
module GitHub
  module Transitions
    class LoadMultiTenantComplianceReports < Base
      # The CSV file to iterate over as well as the report binaries
      # are placed in the following directory.
      DIR = "lib/github/transitions/20250217165833_load_multi_tenant_compliance_reports"

      def run
        unless GitHub.multi_tenant_enterprise?
          raise RuntimeError, "This transition may only be run in a multi-tenant environment"
        end

        super
      end

      iterate_over :csv, params: {
        csv_file: "#{DIR}/reports.csv",
        csv_read_opts: { headers: true },
      }

      sig { override.params(items: Iterators::Items).void }
      def process_batch(items)
        items.each do |(_, row)|
          blob = if row[:report_type] == "download"
            File.read("#{DIR}/#{row[:filename]}")
          end
          parent = if row[:parent_slug].present?
            ComplianceReport.find_by(slug: row[:parent_slug])
          end

          if ComplianceReport.find_by(slug: row[:slug])
            log "Existing report with slug #{row[:slug]} found, skipping creation of report."
            next
          end

          report = ComplianceReport.new(
            slug: row[:slug],
            title: row[:title],
            availability: row[:availability],
            coverage_period: row[:coverage_period],
            description: row[:description],
            report_type: row[:report_type],
            blob: blob,
            filename: row[:filename],
            url: row[:url],
            parent_id: parent&.id,
            display_order: row[:display_order],
            published: row[:published] == "true"
          )

          if dry_run?
            log "Would have created ComplianceReport with slug #{report.slug}."
          else
            write_to(model_class: ComplianceReport) do
              # The ComplianceReport model completely handles the storage upload of the blob we've set
              report.save!
            end
            log "Created ComplianceReport with slug #{report.slug}."
          end
        end
      end
    end
  end
end

# Run as a single process if this script is run directly
if $0 == __FILE__
  # See the transition arguments class for information about standard
  # arguments and their default values. If you require additional arguments,
  # pass them via `additional_arguments: %w(foo)` to the `parse` method.
  args = GitHub::Transitions::Arguments.parse(ARGV)

  GitHub::Transitions::LoadMultiTenantComplianceReports.new(args).run
end
