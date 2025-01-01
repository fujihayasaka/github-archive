# typed: strict
# frozen_string_literal: true

module GitHub
  module Packwerk
    class CircularDependencies
      extend T::Sig

      IGNORED_PACKAGES = T.let([
        "lib/github/transitions",
        "vendor",
        "test",
      ], T::Array[String])

      sig { params(reset: T::Boolean, package_of_interest: T.nilable(String)).void }
      def self.run(reset:, package_of_interest: nil)
        return self.reset if reset

        # enforce all privacy settings
        enforce_privacy
        update_todos
        # turn implicit dependencies from biolations into explicit dependencies to build full graph
        realize_implicit_dependencies(package_of_interest:)
        # output packwerks built in circular validator
        validate
        update_todos
        # output counts of constant:file pairs
        count_violations(package_of_interest)
      end

      sig { void }
      def self.reset
        puts "Resetting all package config/todo files"
        `git checkout -- 'package*.yml' '**/package*.yml' '**/privacy_todo.yml'`
        update_todos
        puts "Done"
      end

      sig { void }
      def self.enforce_privacy
        puts "Enforcing strict policies in all packages"
        updated_count = 0
        packages.each do |package|
          next unless update_package?(package)

          updated_count += 1
          updated = update_package(
            package,
            "enforce_privacy" => true,
            "enforce_dependencies" => true,
            "private_constants" => nil
          )
          ParsePackwerk.write_package_yml!(updated)
        end
        puts "Updated #{updated_count} of #{packages.count} packages"
        ParsePackwerk.bust_cache!
      end

      sig { params(package_of_interest: T.nilable(String)).void }
      def self.realize_implicit_dependencies(package_of_interest: nil)
        puts "Realizing implicit dependencies"
        packages.each do |package|
          dependencies = (package.dependencies + package.violations.select(&:dependency?).map(&:to_package_name)).uniq.sort
          if package_of_interest && package.name != package_of_interest
            if dependencies.include?(package_of_interest)
              dependencies = [package_of_interest]
            else
              dependencies = []
            end
          end
          updated = update_package(package, "dependencies" => dependencies)
          ParsePackwerk.write_package_yml!(updated)
        end
        ParsePackwerk.bust_cache!
      end

      sig { params(package: ParsePackwerk::Package, config: T::Hash[String, T.untyped]).returns(ParsePackwerk::Package) }
      def self.update_package(package, config)
        hash = package.serialize.deep_merge(config.merge("config" => config))
        ParsePackwerk::Package.from_hash(hash)
      end

      sig { params(package: ParsePackwerk::Package).returns(T::Boolean) }
      def self.update_package?(package)
        return true if package.config["enforce_privacy"].blank?
        return true if package.config["enforce_dependencies"].blank?
        return true if package.config["private_constants"].present?

        false
      end

      sig { params(package_of_interest: String).void }
      def self.limit_to_package_of_interest(package_of_interest)
        puts "Limiting to package of interest: #{package_of_interest}"
        packages.each do |package|
          next if package.name == package_of_interest

          package.config["dependencies"] = package.config["dependencies"].select { |dep| dep == package_of_interest }
          ParsePackwerk.write_package_yml!(package)
        end
        ParsePackwerk.bust_cache!
      end

      sig { params(package_of_interest: T.nilable(String)).void }
      def self.count_violations(package_of_interest)
        violations = T.let({}, T::Hash[String, { to: Integer, from: Integer }])
        packages.flat_map(&:violations).compact.select(&:dependency?).each do |violation|
          to_package_name = violation.to_package_name
          violations[to_package_name] ||= {
            to: 0,
            from: 0,
          }
          violation.files.each do |file|
            from_package_name = ParsePackwerk.package_from_path(file).name

            next unless package_of_interest && [from_package_name, to_package_name].include?(package_of_interest)

            violations[from_package_name] ||= {
              to: 0,
              from: 0,
            }
            T.must(violations[to_package_name])[:to] += 1
            T.must(violations[from_package_name])[:from] += 1
          end
        end

        puts "Number of constant:file violations per package:\n"
        violations.to_a.select do |_, counts|
          counts[:to].positive? && counts[:from].positive?
        end.sort do |a, b|
          a = a[1]
          b = b[1]

          [0 - a[:to], 0 - a[:from]] <=> [0 - b[:to], 0 - b[:from]]
        end.each do |package_name, counts|
          puts " - #{counts[:to]} → #{package_name} → #{counts[:from]}"
        end


        # TODO: Fix this. Maybe a cache issue?
        puts "For some reason you currently have to run the script twice for accurate results"
      end

      sig { void }
      def self.update_todos
        puts "Running `bin/packwerk update`"
        `bin/packwerk update`
      end

      sig { void }
      def self.validate
        puts "Running `bin/packwerk validate`"
        puts `bin/packwerk validate`
      end

      sig { returns(T::Array[::ParsePackwerk::Package]) }
      def self.packages
        ParsePackwerk.all.reject do |package|
          IGNORED_PACKAGES.any? { |ignored| package.name.start_with?(ignored) }
        end
      end
    end
  end
end
