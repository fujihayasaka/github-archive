# typed: true
# frozen_string_literal: true

module Platform
  module Errors
    class Execution < GraphQL::ExecutionError
      attr_reader :type

      def initialize(type, *args, **options)
        @type = type.upcase
        if args.none? && options.none?
          super
        else
          super(*T.unsafe(args), **T.unsafe(options))
        end
      end

      def to_h
        extra_attrs = {
          "type" => type,
        }

        # In test and development, add the Ruby backtrace
        # to see where in the code this error was raised.
        #
        # Some errors are returned, not raised, so they don't have a backtrace.
        # This _could_ be improved by stashing `caller` during initialize,
        # but let's come add that if / when we need it.
        if !Rails.env.production? && backtrace.present?
          # Remove the redundant leading bits so it's easier to read
          trimmed_backtrace = T.must(backtrace).map do |line|
            line.split("github/github/").last
          end

          if extensions
            extensions["ruby_backtrace"] = trimmed_backtrace
          else
            extra_attrs["extensions"] = {
              "ruby_backtrace" => trimmed_backtrace,
            }
          end
        end

        super.merge(extra_attrs)
      end
    end
  end
end
