# typed: strict
# frozen_string_literal: true

module PullRequests
  module CommentPosition
    # Sealed module describing the git file blob specific Position types.
    module Positions
      extend T::Helpers
      include Kernel

      requires_ancestor { T::Struct }

      abstract!
      sealed!

      sig { returns(T::Hash[String, T.untyped]) }
      def serialize = super.merge("type" => type.to_s.upcase)

      sig { abstract.returns(Symbol) }
      def type; end

      # Track the git diff range used in positioning. Allows tracking the "side" of the diff the position is on
      # as well as enabling caching/reuse of positions given the immutability of a git object id.
      sig { abstract.returns(DiffRange) }
      def range; end

      sig { abstract.params(new_range: DiffRange).returns(DiffRange) }
      def range=(new_range); end

      # Duplicate the position, but utilizing a specific range for reusing positional data in different diff ranges.
      sig { params(range: DiffRange).returns(Positions) }
      def clone_with_new_range(range:)
        instance = dup
        instance.range = range
        instance
      end

      sig { abstract.returns(T::Hash[String, T.untyped]) }
      def as_json; end

      # The commit-tuple describing the diff range requested when viewing Pull Request related state. Not a part of the
      # public API schema, but used internally.
      class DiffRange < T::Struct
        const :base_commit_oid, String
        const :start_commit_oid, String
        const :end_commit_oid, String

        sig { params(other: T.untyped).returns(T::Boolean) }
        def ==(other)
          case other
          when self.class then other.serialize == serialize
          else super
          end
        end
      end

      class Line < T::Struct
        include Positions

        # Public
        const :path, String
        const :commit_oid, String
        const :line, Integer


        # Internal
        prop :range, DiffRange

        sig { override.returns(Symbol) }
        def type = :line

        sig { override.returns(T::Hash[String, T.untyped]) }
        def as_json
          serialize.slice("type", "path", "line", "commit_oid")
        end
      end

      class File < T::Struct
        include Positions

        # Public
        const :path, String
        const :commit_oid, String

        # Internal
        prop :range, DiffRange

        sig { override.returns(Symbol) }
        def type = :file

        sig { override.returns(T::Hash[String, T.untyped]) }
        def as_json
          serialize.slice("type", "path", "commit_oid")
        end
      end

      class Multiline < T::Struct
        include Positions

        # Public
        const :start_path, String
        const :start_line, Integer
        const :start_commit_oid, String
        const :end_path, String
        const :end_line, Integer
        const :end_commit_oid, String

        # Internal
        prop :range, DiffRange

        sig { override.returns(Symbol) }
        def type = :multiline

        sig { override.returns(T::Hash[String, T.untyped]) }
        def as_json
          serialize.slice(
            "type",
            "start_path",
            "start_line",
            "start_commit_oid",
            "end_path",
            "end_line",
            "end_commit_oid"
          )
        end
      end

      class Invalid < T::Struct
        include Positions

        prop :range, DiffRange
        const :reason, Symbol

        sig { override.returns(Symbol) }
        def type = :invalid

        sig { override.returns(T::Hash[String, T.untyped]) }
        def as_json
          serialize.slice("type", "reason")
        end
      end
    end
  end
end
