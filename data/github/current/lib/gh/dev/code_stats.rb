# typed: strict
# frozen_string_literal: true

require "serviceowners"

module GH
  module Dev
    class CodeStats
      sig { params(serviceowners: Serviceowners::Main).void }
      def initialize(serviceowners)
        @serviceowners = serviceowners
      end

      sig { returns(Serviceowners::Main) }
      attr_reader :serviceowners

      sig { params(name: Symbol).void }
      def register_count_stats(name)
        ::CodeStats::Reporter.register_report(name:) do |report|
          require "gh/dev/code_stats/count"

          Count.new(report, serviceowners).report_data!
        end
      end

      sig { params(name: Symbol).void }
      def register_package_stats(name)
        ::CodeStats::Reporter.register_report(name:) do |report|
          require "gh/dev/code_stats/package"

          Package.new(report, serviceowners).report_data!
        end
      end

      sig { params(name: Symbol).void }
      def register_sorbet_stats(name)
        ::CodeStats::Reporter.register_report(name:) do |report|
          require "gh/dev/code_stats/sorbet"

          Sorbet.new(report, serviceowners).report_data!
        end
      end

      sig { params(name: Symbol).void }
      def register_query_stats(name)
        ::CodeStats::Reporter.register_report(name:) do |report|
          require "gh/dev/code_stats/query"

          Query.new(report, serviceowners).report_data!
        end
      end

      sig { params(name: Symbol).void }
      def register_circular_dependencies_stats(name)
        ::CodeStats::Reporter.register_report(name:) do |report|
          require "gh/dev/code_stats/circular_dependencies"

          CircularDependencies.new(report, serviceowners).report_data!
        end
      end

      sig { params(name: Symbol).void }
      def register_downcast_stats(name)
        ::CodeStats::Reporter.register_report(name:) do |report|
          require "gh/dev/code_stats/downcast"

          Downcast.new(report, serviceowners).report_data!
        end
      end
    end
  end
end
