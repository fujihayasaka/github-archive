# typed: strict
# frozen_string_literal: true

require "#{Rails.root}/config/environment"

module GitHub
  module Transitions
    class PopulateRvaSearchIndexUpdatedAt < Base

      class RepositoryVulnerabilityAlert < ApplicationRecord::Notify
        self.table_name = :repository_vulnerability_alerts
      end

      iterate_over :database_table, params: {
        model_class: RepositoryVulnerabilityAlert,
        # Make the transition idempotent by only selecting rows that weren't previously processed
        conditions: "active = TRUE AND search_index_updated_at IS NULL",
      }

      sig { override.params(items: Iterators::Items).void }
      def process_batch(items)
        ids = items.keys

        if dry_run?
          # SELECT rather than UPDATE... however, there are millions of alerts, so to prevent 10K SELECT queries, only
          # run the SQL every Nth batch
          unless ids.any? { |id| id % 100_000 == 0 }
            return
          end

          results = RepositoryVulnerabilityAlert.connection.execute(<<-SQL)
            SELECT
              rva.id,
              rva.updated_at AS rva_updated_at,
              vvr.updated_at AS vvr_updated_at,
              vuln.updated_at AS vuln_updated_at,
              epss.updated_at AS epss_updated_at,
              GREATEST(
                -- If any arg to GREATEST() is NULL, the result will be NULL, so we use COALESCE
                COALESCE(rva.updated_at, '1970-01-01 00:00:00'),
                COALESCE(vvr.updated_at, '1970-01-01 00:00:00'),
                COALESCE(vuln.updated_at, '1970-01-01 00:00:00'),
                COALESCE(epss.updated_at, '1970-01-01 00:00:00')
              ) AS greatest_updated_at
            FROM repository_vulnerability_alerts AS rva
            LEFT JOIN vulnerable_version_ranges AS vvr ON rva.vulnerable_version_range_id = vvr.id
            LEFT JOIN vulnerabilities AS vuln ON rva.vulnerability_id = vuln.id
            LEFT JOIN cve_epss AS epss ON vuln.cve_id = epss.cve_id
            WHERE rva.id IN (#{ids.join(',')})
            LIMIT 10 -- limit for dry run
            /* Disables a CI check that is not relevant for a transition that is only run once in prod: */
            /* cross-schema-domain-query-exempted */
          SQL
          log("results from the first 10 rows of this batch:\n#{results.to_a.inspect}")

        else
          write_to(model_class: RepositoryVulnerabilityAlert) do
            RepositoryVulnerabilityAlert.connection.execute(<<-SQL)
              UPDATE repository_vulnerability_alerts AS rva
              LEFT JOIN vulnerable_version_ranges AS vvr ON rva.vulnerable_version_range_id = vvr.id
              LEFT JOIN vulnerabilities AS vuln ON rva.vulnerability_id = vuln.id
              LEFT JOIN cve_epss AS epss ON vuln.cve_id = epss.cve_id
              SET rva.search_index_updated_at = GREATEST(
                -- If any arg to GREATEST() is NULL, the result will be NULL, so we use COALESCE
                COALESCE(rva.updated_at, '1970-01-01 00:00:00'),
                COALESCE(vvr.updated_at, '1970-01-01 00:00:00'),
                COALESCE(vuln.updated_at, '1970-01-01 00:00:00'),
                COALESCE(epss.updated_at, '1970-01-01 00:00:00')
              )
              WHERE rva.id IN (#{ids.join(',')})
              /* Disables a CI check that is not relevant for a transition that is only run once in prod: */
              /* cross-schema-domain-query-exempted */
            SQL
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

  GitHub::Transitions::PopulateRvaSearchIndexUpdatedAt.new(args).run
end
