# typed: strict
# frozen_string_literal: true

require "packwerk"
require "packwerk/privacy/checker"

module GitHub
  module Packwerk
    class BuildMarkupOffensesFormatter
      extend T::Sig
      include ::Packwerk::OffensesFormatter

      sig { override.params(offenses: T::Array[T.nilable(::Packwerk::Offense)]).returns(String) }
      def show_offenses(offenses)
        return "No offenses detected 🎉" if offenses.empty?

        <<~EOS
          #{offenses_list(offenses)}

          #{offenses_summary(offenses)}
        EOS
      end

      sig { override.params(offense_collection: ::Packwerk::OffenseCollection, fileset: T::Set[String]).returns(String) }
      def show_stale_violations(offense_collection, fileset)
        "Stale violations detected. Message is WIP."
      end

      sig { override.params(strict_mode_violations: T::Array[::Packwerk::ReferenceOffense]).returns(String) }
      def show_strict_mode_violations(strict_mode_violations)
        "Strict mode violations detected. Message is WIP."
      end

      sig { override.returns(String) }
      def identifier
        "build_markup_offenses_formatter"
      end

      private

      sig { params(offenses: T::Array[T.nilable(::Packwerk::Offense)]).returns(String) }
      def offenses_list(offenses)
        offenses
          .compact
          .map { |offense| format_offense(offense) }
          .join("\n")
      end

      sig { params(offense: ::Packwerk::Offense).returns(String) }
      def format_offense(offense)
        message = offense.message
        message = reference_offense_message(offense) if offense.is_a?(::Packwerk::ReferenceOffense)

        fingerprint_elements = [offense.file, offense.location&.line, offense.message]

        hash = {
          suite: offense.file,
          name: "line #{offense.location&.line}",
          location: "#{offense.file}:#{offense.location&.line}",
          message: message,
          fingerprint: ::Digest::SHA256.hexdigest(fingerprint_elements.join("|")),
          flake: false
        }

        "===FAILURE===\n#{::JSON.pretty_generate(hash)}\n===END FAILURE===\n"
      end

      sig { params(offense: ::Packwerk::ReferenceOffense).returns(String) }
      def reference_offense_message(offense)
        if offense.violation_type == ::Packwerk::Privacy::Checker::VIOLATION_TYPE
          privacy_violation_message(offense.reference)
        else
          dependency_violation_message(offense.reference)
        end
      end

      sig { params(reference: ::Packwerk::Reference).returns(String) }
      def privacy_violation_message(reference)
        constant = reference.constant

        <<~EOS
          `#{constant.name}` is private to the `#{constant.package.name}` package but referenced in this file which belongs to
          the `#{reference.package.name}` package. To resolve this error, please do one of the following:

          * Switch to using a public method for the `#{constant.package.name}` package.
          * Run `bin/packwerk update-todo` to accept this privacy violation for now.
          * Move this file to the `#{constant.package.name}` package.

          More info available at https://github.com/github/app-core/blob/master/app-partitioning/index.md
        EOS
      end

      sig { params(reference: ::Packwerk::Reference).returns(String) }
      def dependency_violation_message(reference)
        constant = reference.constant

        <<~EOS
          `#{constant.name}` is part of the `#{constant.package.name}` package but this file belongs to the `#{reference.package.name}` package
          which does not have `#{constant.package.name}` as a dependency. To resolve this error, please do one of the following:

          * Add `#{constant.package.name}` as a dependency in `#{reference.package.name}/package.yml`
          * Run `bin/packwerk update-todo` to accept this dependency violation for now
          * Move this file to the `#{constant.package.name}` package

          More info available at https://github.com/github/app-core/blob/master/app-partitioning/index.md
        EOS
      end

      sig { params(offenses: T::Array[T.nilable(::Packwerk::Offense)]).returns(String) }
      def offenses_summary(offenses)
        offenses_string = offenses.length == 1 ? "offense" : "offenses"
        "#{offenses.length} #{offenses_string} detected"
      end
    end
  end
end
