# typed: strict
# frozen_string_literal: true

# Report Packwerk stats. See script/report_code_stats.rb for more info

require "code_stats"
require "parse_packwerk"
require "github/packwerk/metrics"
require "gh/dev/code_stats/base"

module GH
  module Dev
    class CodeStats
      class Package < Base
        extend T::Helpers

        sig { override.void }
        def report_data!
          metrics = GitHub::Packwerk::Metrics.new
          metrics.violation_counts.each do |package_name, violations|
            package_yml_path = ParsePackwerk.find(package_name)&.yml
            spec = serviceowners.spec_for_path(package_yml_path.to_s)

            team_name = nil
            service_name = nil

            if spec
              team_name = spec.teams.first&.name
              service_name = spec.service&.name
            end

            display_package_name = package_name == "." ? ". (root)" : package_name

            tags = [
              "package:#{display_package_name}",
              "team:#{team_name}",
              "service:#{service_name}",
              "repo:github/github"
            ]

            %i(privacy dependency).each do |violation_type|
              violation_counts = T.must(violations[violation_type])

              violation_counts.each do |direction, count|
                report.gauge("app_partitioning.#{direction}_violations.#{violation_type}", count, tags)
              end
            end

            report.gauge("app_partitioning.enforces_dependencies", violations[:dependency_enforcement], tags)
            report.gauge("app_partitioning.enforces_privacy", violations[:privacy_enforcement], tags)
          end
        end
      end
    end
  end
end
