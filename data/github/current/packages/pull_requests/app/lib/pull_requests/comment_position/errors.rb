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
        def to_error_tuple = [:diff_entry, "#{path} diff is too large"]
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

      # Error when path is missing (nil/blank) from input.
      class MissingPath < T::Struct
        include Errors

        sig { override.returns([Symbol, String]) }
        def to_error_tuple = [:path, "is required"]
      end

      # Error when positioning is missing from input.
      class MissingPositioning < T::Struct
        include Errors

        sig { override.returns([Symbol, String]) }
        def to_error_tuple = [:positioning, "is required"]
      end

      # Error resolving the start line in a multiline comment.
      class StartLine < T::Struct
        include Errors

        const :start_line, T.nilable(Integer)

        sig { override.returns([Symbol, String]) }
        def to_error_tuple = [:start_line, "could not be resolved"]
      end

      # Error when start_line is greater than line in multiline comment.
      class LineRange < T::Struct
        include Errors

        const :start_line, T.nilable(Integer)
        const :line, T.nilable(Integer)

        sig { override.returns([Symbol, String]) }
        def to_error_tuple = [:start_line, "must be less than or equal to line"]
      end

      # Error when start_side doesn't match side in multiline comment.
      class SideMismatch < T::Struct
        include Errors

        const :start_side, T.nilable(String)
        const :side, T.nilable(String)

        sig { override.returns([Symbol, String]) }
        def to_error_tuple = [:start_side, "must match side"]
      end

      # Converts a Positioning::Enums::Outcome to an appropriate error.
      sig do
        params(
          outcome: Positioning::Enums::Outcome,
          path: T.nilable(String),
          line: T.nilable(Integer),
          position: T.nilable(Integer),
        ).returns(Errors)
      end
      def self.from_outcome(outcome:, path: nil, line: nil, position: nil)
        case outcome
        when Positioning::Enums::Outcome::PathNotFound,
             Positioning::Enums::Outcome::PathRemoved,
             Positioning::Enums::Outcome::DiffNotLoaded
          Path.new(path:)
        when Positioning::Enums::Outcome::LineRemoved
          if line
            Line.new(line:)
          elsif position
            Position.new(position:)
          else
            Unknown.new
          end
        when Positioning::Enums::Outcome::ContentTooLarge
          DiffEntryTooBig.new(path: path || "")
        when Positioning::Enums::Outcome::DiffInvalid
          DiffNotValid.new(message: nil)
        when Positioning::Enums::Outcome::GitUnavailable
          GitUnavailable.new(message: nil)
        else
          Unknown.new
        end
      end
    end
  end
end
