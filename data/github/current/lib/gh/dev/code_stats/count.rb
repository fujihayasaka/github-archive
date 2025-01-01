# typed: strict
# frozen_string_literal: true

require "code_stats"
require "parse_packwerk"
require "gh/dev/code_stats/base"

module GH
  module Dev
    class CodeStats
      class Count < Base
        sig { override.void }
        def report_data!
          service_counts, package_counts = build_counts

          report_service_data(service_counts)
          report_package_data(package_counts)
        end

        private

        Counts = T.type_alias { { test_files: Integer, prod_files: Integer, test_lines: Integer, prod_lines: Integer } }
        PackageOrService = T.type_alias { T.any(ParsePackwerk::Package, Serviceowners::Service) }

        sig { returns([T::Hash[Serviceowners::Service, Counts], T::Hash[ParsePackwerk::Package, Counts]]) }
        def build_counts
          json = `~/.cargo/bin/tokei -f -t=Ruby -o=json`
          counts = JSON.parse(json)
          service_counts = Hash.new { |h, k| h[k] = { test_files: 0, prod_files: 0, test_lines: 0, prod_lines: 0 } }
          package_counts = Hash.new { |h, k| h[k] = { test_files: 0, prod_files: 0, test_lines: 0, prod_lines: 0 } }

          counts["Ruby"]["reports"].each do |report|
            path = report["name"].delete_prefix("./")

            lines = report["stats"]["code"]
            test = path.end_with?("_test.rb")
            spec = ::CodeStats::SERVICEOWNERS.spec_for_path(path)
            service = spec&.service

            increment_counts(service, lines, service_counts, test) if service

            package = ParsePackwerk.package_from_path(path)
            increment_counts(package, lines, package_counts, test) if package
          end

          [service_counts, package_counts]
        end

        sig { params(service_counts: T::Hash[Serviceowners::Service, Counts]).void }
        def report_service_data(service_counts)
          service_counts.each do |service, counts|
            tags = ["repo:github/github", "language:ruby"]
            if service
              tags << "service:#{service.name}"
              team = service.maintainers
              tags << "team:#{team.name}" if team
            end

            report_counts(type: "service", counts:, tags:)
          end
        end

        sig { params(package_counts: T::Hash[ParsePackwerk::Package, Counts]).void }
        def report_package_data(package_counts)
          package_counts.each do |package, counts|
            tags = ["repo:github/github", "package:#{package.name}", "language:ruby"]
            spec = ::CodeStats::SERVICEOWNERS.spec_for_path(package.yml.to_s)

            service = spec&.service&.name
            tags << "service:#{service}" if service

            team = spec&.service&.maintainers&.name
            tags << "team:#{team}" if team

            report_counts(type: "package", counts:, tags:)
          end
        end

        sig { params(type: String, counts: Counts, tags: T::Array[String]).void }
        def report_counts(type:, counts:, tags:)
          report.gauge("code_stats.#{type}.lines", counts[:test_lines], tags + ["file_type:test"])
          report.gauge("code_stats.#{type}.lines", counts[:prod_lines], tags + ["file_type:prod"])
          report.gauge("code_stats.#{type}.files", counts[:test_files], tags + ["file_type:test"])
          report.gauge("code_stats.#{type}.files", counts[:prod_files], tags + ["file_type:prod"])
        end

        sig { params(group: PackageOrService, lines: Integer, counts: T::Hash[PackageOrService, Counts], test: T::Boolean).void.checked(:never) }
        def increment_counts(group, lines, counts, test)
          if test
            T.must(counts[group])[:test_lines] += lines
            T.must(counts[group])[:test_files] += 1
          else
            T.must(counts[group])[:prod_lines] += lines
            T.must(counts[group])[:prod_files] += 1
          end
        end
      end
    end
  end
end
