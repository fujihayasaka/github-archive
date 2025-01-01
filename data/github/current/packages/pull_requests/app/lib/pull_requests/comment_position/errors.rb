# typed: strict
# frozen_string_literal: true

module PullRequests
  module CommentPosition
    module Errors
      extend T::Helpers
      include Kernel

      abstract!
      sealed!

      sig { abstract.returns([Symbol, String]) }
      def to_error_tuple; end

      sig { returns(String) }
      def to_error_message = to_error_tuple.join(" ")

      # Internal failure when the order of operations resulted in a diff/path not being batch loaded.
      class DiffNotLoaded < T::Struct
        include Errors

        const :base_commit_oid, String
        const :head_commit_oid, String

        sig { override.returns([Symbol, String]) }
        def to_error_tuple = [:base, "could not resolve diff"]
      end

      class DiffEntryTooBig < T::Struct
        include Errors

        const :path, String

        sig { override.returns([Symbol, String]) }
        def to_error_tuple = [:diff_entry, "#{path} is too big"]
      end

      # Error resolving the given path.
      class Path < T::Struct
        include Errors

        const :path, T.nilable(String)

        sig { override.returns([Symbol, String]) }
        def to_error_tuple = [:path, "could not be resolved"]
      end

      # Error with a given parameter value.
      class Parameter
        include Errors

        sig { returns(Symbol) }
        attr_reader :name

        sig { returns(T.untyped) }
        attr_reader :value

        sig { params(kwargs: T.untyped).void }
        def initialize(**kwargs)
          key, value = kwargs.first

          raise ArgumentError if kwargs.empty?
          raise ArgumentError if key.nil?

          @name = T.let(key, Symbol)
          @value = T.let(value, T.untyped)
        end

        sig { override.returns([Symbol, String]) }
        def to_error_tuple = [@name, "parameter is invalid: #{@value}"]
      end

      class DiffNotValid < T::Struct
        include Errors

        const :message, T.nilable(String)

        sig { override.returns([Symbol, String]) }
        def to_error_tuple = [:commit_range, "is invalid"]
      end

      class GitUnavailable < T::Struct
        include Errors

        const :message, T.nilable(String)

        sig { override.returns([Symbol, String]) }
        def to_error_tuple = [:git_service, "unavailable"]
      end

      # Error resolving the line number.
      class Line < T::Struct
        include Errors

        const :line, T.nilable(Integer)

        sig { override.returns([Symbol, String]) }
        def to_error_tuple = [:line, "could not be resolved"]
      end

      # Error resolving the diff-relative position.
      class Position < T::Struct
        include Errors

        const :position, T.nilable(Integer)

        sig { override.returns([Symbol, String]) }
        def to_error_tuple = [:position, "could not be resolved"]
      end

      # Error resolving the diff-relative start position offset.
      class StartPosition < T::Struct
        include Errors

        const :position, T.nilable(Integer)

        sig { override.returns([Symbol, String]) }
        def to_error_tuple = [:start_position, "could not be resolved"]
      end

      # Fallback error.
      class Unknown
        include Errors

        sig { override.returns([Symbol, String]) }
        def to_error_tuple = [:base, "unknown error occurred"]
      end
    end
  end
end
