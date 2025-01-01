# typed: true
# frozen_string_literal: true

# This file is not strictly typed so that default checked level can be set prior to any sig blocks being evaluated.
# While harmless, it does produce a warning.
module GitHub
  module Sorbet
    class Runtime
      extend T::Sig

      # This error should only be thrown in tests (local and CI) to inform folks when runtime type checking
      # finds a problem. In production, it is reported to Sentry but will not block execution.
      class InformationalError < StandardError
        def failbot_context
          { app: "github-ruby-warnings" }
        end
      end

      # Any method signature type checking errors will be silently reported to Sentry without raising.
      # This will not apply to methods that explicitly declare on_failure(:raise).
      def self.silently_report_errors!
        return if @ignore_directives

        set_default_call_validation_handler

        @reporting_errors = true
      end

      def self.reporting_errors?
        !!@reporting_errors
      end

      # In this mode, type checking is disabled entirely by default. This is suitable for production
      # environments which may be sensitive to the small performance cost incurred by Sorbet.
      # Methods such as domain interface methods that explicitly declare their checked levels however
      # may still raise TypeErrors so we also override the default handler to ensure these are
      # properly redacted.
      def self.skip_type_checks_by_default!
        return if @ignore_directives

        set_default_call_validation_handler
        safe_set_default_checked_level(:never)
      end

      # A convenient wrapper method that sets the default checked level to ":tests" and then enables
      # type checking for tests, thus raising on type errors.
      def self.start_test_type_checking!
        return if @ignore_directives

        set_default_call_validation_handler(always_raise: true)
        safe_set_default_checked_level(:tests)
        T::Configuration.enable_checking_for_sigs_marked_checked_tests
      end

      # A wrapper equivalent to start_test_type_checking! but does not raise on type errors.
      # This is used in tests to model the behavior of silently_report_errors! in production.
      def self.start_test_type_checking_without_always_raise!
        return if @ignore_directives

        set_default_call_validation_handler(always_raise: false)
        safe_set_default_checked_level(:tests)
        T::Configuration.enable_checking_for_sigs_marked_checked_tests
      end

      # Sometimes tools that use Sorbet initialize the rails app, resulting in confusing warnings
      # when the default_checked_level is set after signatures have already been evaluated.
      # In these cases, it is useful to just ignore subsequent calls to this module.
      def self.ignore_directives!
        @ignore_directives = true
      end

      private_class_method def self.redacted_message(method_sig, opts)
        definition = definition_loc(method_sig)

        name = opts[:name]
        kind = opts[:kind]
        value = opts[:value]
        type = opts[:type]
        "#{kind}#{name ? " '#{name}'" : ''}: Expected type #{type}, got type #{value.class.name}.\n" \
          "Definition: #{definition}"
      end

      private_class_method def self.set_default_call_validation_handler(always_raise: false)
        T::Configuration.call_validation_error_handler = lambda do |sig, opts|
          error = build_error(sig, opts)

          if error.is_a?(TypeError) || always_raise
            raise error
          else
            Failbot.report(error)
          end
        end
      end

      private_class_method def self.definition_loc(method_sig)
        return unless method_sig

        definition_file, definition_line = method_sig.method.source_location
        definition_file = definition_file.delete_prefix("#{ENV["RAILS_ROOT"]}/")
        "#{definition_file}:#{definition_line}"
      end

      # If the method is marked as on_failure(:raise), we raise a TypeError because we want
      # to treat the Sorbet type checking as always being present and a valid part of the
      # application's logic. Otherwise, we raise a GitHub::Sorbet::Runtime::InformationalError which indicates
      # that the error cannot be relied on for production application logic but is rather
      # indicating an error in the signature for the benefit of CI tests or production sampling.
      #
      # If there is no sig, as is the case for T::Struct, we raise TypeError which is also
      # what happens when type checking is entirely disabled anyway.
      private_class_method def self.build_error(sig, opts)
        should_raise = sig.nil? || (sig.on_failure && sig.on_failure[0] == :raise)
        error_class = should_raise ? TypeError : InformationalError
        error = error_class.new(redacted_message(sig, opts))
        error.set_backtrace(caller.dup)
        error
      end

      private_class_method def self.safe_set_default_checked_level(level)
        T::Configuration.default_checked_level = level

      rescue RuntimeError
        # raise in prod so we know the expected default checked level is not being set.
        raise if Rails.env.production?

        # In non-production environments, swallow the error to avoid confusing people.
      end
    end
  end
end
