# typed: strict
# frozen_string_literal: true

require "code_stats"
require "parse_packwerk"
require "gh/dev/code_stats/base"

module GH
  module Dev
    class CodeStats
      class Query < Base
        sig { override.void }
        def report_data!
          report_package_data(counts_by_package)
        end

        private

        sig { returns(T::Hash[String, T::Hash[String, Integer]]) }
        def counts_by_package
          `GH_DEBUG=1 bundle exec ruby script/domain-isolation-query-violations --locations --audit`

          Dir["packages/**/domain_query_violations.yml"].each_with_object({}) do |file_name, counts_by_package|
            file = YAML.safe_load_file(file_name)

            counts_by_table_and_reason = Hash.new(0)
            file.each do |_, query|
              query["tables"].each do |table|
                query["violations"].each do |violation|
                  counts_by_table_and_reason[[table, violation["reason"]]] += 1
                end
              end
            end

            package = file_name.gsub("/domain_query_violations.yml", "")
            counts_by_package[package] = counts_by_table_and_reason
          end
        end

        sig { params(counts_by_package: T::Hash[String, T::Hash[String, Integer]]).void }
        def report_package_data(counts_by_package)
          counts_by_package.each do |package, counts_by_table_and_reason|
            tags = ["package:#{package}"]

            counts_by_table_and_reason.each do |(table, reason), count|
              report.gauge("code_stats.query.violations", count, tags + ["table:#{table}", "reason:#{reason}"])
            end
          end
        end
      end
    end
  end
end
