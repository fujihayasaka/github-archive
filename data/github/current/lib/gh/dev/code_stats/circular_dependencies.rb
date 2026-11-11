# typed: strict
# frozen_string_literal: true

require "code_stats"
require "parse_packwerk"

require "gh/dev/code_stats/base"
require "github/packwerk/circular_dependencies"

module GH
  module Dev
    class CodeStats
      class CircularDependencies < Base
        sig { override.void }
        def report_data!
          GitHub::Packwerk::CircularDependencies.enforce_privacy
          GitHub::Packwerk::CircularDependencies.update_todos
          GitHub::Packwerk::CircularDependencies.realize_implicit_dependencies

          circular_dependencies_by_package_name(dependencies_by_package_name).sort_by { |package, _v| package }.each do |package, count|
            puts("#{package}: #{count}")
            tags = ["package:#{package}"]
            report.gauge("code_stats.dependencies.circular", count, tags)
          end

          GitHub::Packwerk::CircularDependencies.reset
        end

        sig { returns(T::Hash[String, T::Array[String]]) }
        def dependencies_by_package_name
          package_dependencies = {}

          GitHub::Packwerk::CircularDependencies.packages.each do |package|
            package_name = package.name == "." ? "_root" : package.name
            package_dependencies[package_name] = package.dependencies.map { |d| d == "." ? "_root" : d }
          end

          package_dependencies
        end

        sig  { params(package_dependencies: T::Hash[String, T::Array[String]]).returns(T::Hash[String, Integer]) }
        def circular_dependencies_by_package_name(package_dependencies)
          circular_dependencies = {}

          package_dependencies.each do |package, dependencies|
            circular_dependencies[package] = 0
            dependencies.each do |dependency|
              circular_dependencies[package] += 1 if T.must(package_dependencies[dependency]).include?(package)
            end
          end

          circular_dependencies
        end
      end
    end
  end
end
