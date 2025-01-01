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

      # Ensure that all OIDs are valid and belong to the submitted commit range.
      sig { params(base_commit_oid: String, head_commit_oid: String, oids: String).returns(T.nilable(CommentPosition::Errors::Parameter)) }
      def self.parse_oids(base_commit_oid:, head_commit_oid:, **oids)
        unless GitRPC::Util.valid_full_oid?(base_commit_oid)
          return CommentPosition::Errors::Parameter.new(base_commit_oid: "is not a valid oid")
        end

        unless GitRPC::Util.valid_full_oid?(head_commit_oid)
          return CommentPosition::Errors::Parameter.new(head_commit_oid: "is not a valid oid")
        end

        oids.each do |key, oid|
          unless GitRPC::Util.valid_full_oid?(oid)
            return CommentPosition::Errors::Parameter.new(key => "is not a valid oid")
          end

          unless oid == base_commit_oid || oid == head_commit_oid
            return CommentPosition::Errors::Parameter.new(key => "not included in base or head commit")
          end
        end

        nil
      end

      sig { returns(T::Hash[String, T.untyped]) }
      def serialize
        # Spokes/GitRPC will respond with Encoding::ASCII_8BIT for path names in API responses. All of our persistence
        # and APIs are encoded with UTF-8. This forces the encoding at the "convert this to JSON" layer to ensure
        # persistence and API serialization conform to the right encoding.
        super.merge("type" => type.to_s.upcase).transform_values do |value|
          next value unless value.is_a?(String)
          next value if value.encoding == Encoding::UTF_8
          value = value.dup if value.frozen?
          value.force_encoding(Encoding::UTF_8).scrub!
        end
      end

      sig { abstract.returns(Symbol) }
      def type; end

      sig { abstract.returns(String) }
      def base_commit_oid; end

      sig { abstract.returns(String) }
      def head_commit_oid; end

      class Line < T::Struct
        include Positions

        const :path, String
        const :commit_oid, String
        const :line, Integer
        const :base_commit_oid, String
        const :head_commit_oid, String

        sig { override.returns(Symbol) }
        def type = :line

        sig { params(positioning: T::Hash[Symbol, T.untyped]).returns(T.any(Line, CommentPosition::Errors)) }
        def self.parse(positioning)
          commit_oid = T.let(positioning[:commit_oid].to_s, String)
          line = T.let(positioning[:line].to_i, Integer)
          path = T.let(positioning[:path].to_s, String)
          base_commit_oid = T.let(positioning[:base_commit_oid].to_s, String)
          head_commit_oid = T.let(positioning[:head_commit_oid].to_s, String)

          if error = Positions.parse_oids(commit_oid:, base_commit_oid:, head_commit_oid:)
            error
          elsif path.blank?
            CommentPosition::Errors::Parameter.new(path: "must not be blank")
          elsif line <= 0
            CommentPosition::Errors::Parameter.new(line: "must be an integer greater than 0")
          else
            new(path:, commit_oid:, line:, base_commit_oid:, head_commit_oid:)
          end
        end
      end

      class File < T::Struct
        include Positions

        const :path, String
        const :commit_oid, String
        const :base_commit_oid, String
        const :head_commit_oid, String

        sig { override.returns(Symbol) }
        def type = :file

        sig { params(positioning: T::Hash[Symbol, T.untyped]).returns(T.any(File, CommentPosition::Errors)) }
        def self.parse(positioning)
          commit_oid = T.let(positioning[:commit_oid].to_s, String)
          path = T.let(positioning[:path].to_s, String)
          base_commit_oid = T.let(positioning[:base_commit_oid].to_s, String)
          head_commit_oid = T.let(positioning[:head_commit_oid].to_s, String)

          if error = Positions.parse_oids(commit_oid:, base_commit_oid:, head_commit_oid:)
            error
          elsif path.blank?
            CommentPosition::Errors::Parameter.new(path: "must not be blank")
          else
            new(path:, commit_oid:, base_commit_oid:, head_commit_oid:)
          end
        end
      end

      class Multiline < T::Struct
        include Positions

        const :start_path, String
        const :start_line, Integer
        const :start_commit_oid, String
        const :end_path, String
        const :end_line, Integer
        const :end_commit_oid, String
        const :base_commit_oid, String
        const :head_commit_oid, String

        sig { override.returns(Symbol) }
        def type = :multiline

        sig { params(positioning: T::Hash[Symbol, T.untyped]).returns(T.any(Multiline, CommentPosition::Errors)) }
        def self.parse(positioning)
          start_commit_oid = T.let(positioning[:start_commit_oid].to_s, String)
          end_commit_oid = T.let(positioning[:end_commit_oid].to_s, String)
          start_line = T.let(positioning[:start_line].to_i, Integer)
          end_line = T.let(positioning[:end_line].to_i, Integer)
          start_path = T.let(positioning[:start_path].to_s, String)
          end_path = T.let(positioning[:end_path].to_s, String)
          base_commit_oid = T.let(positioning[:base_commit_oid].to_s, String)
          head_commit_oid = T.let(positioning[:head_commit_oid].to_s, String)

          if error = Positions.parse_oids(start_commit_oid:, end_commit_oid:, base_commit_oid:, head_commit_oid:)
            error
          elsif start_path.blank?
            CommentPosition::Errors::Parameter.new(start_path: "must not be blank")
          elsif end_path.blank?
            CommentPosition::Errors::Parameter.new(end_path: "must not be blank")
          elsif start_line <= 0
            CommentPosition::Errors::Parameter.new(start_line: "must be an integer greater than 0")
          elsif end_line <= 0
            CommentPosition::Errors::Parameter.new(end_line: "must be an integer greater than 0")
          elsif start_line >= end_line && start_commit_oid == end_commit_oid
            CommentPosition::Errors::Parameter.new(end_line: "must be greater than start_line")
          elsif start_line > end_line && start_commit_oid != end_commit_oid
            CommentPosition::Errors::Parameter.new(end_line: "must be greater than start_line")
          elsif start_commit_oid == end_commit_oid && start_path != end_path
            # When commits match, paths must also match. The opposite scenario (paths match but commits differ) is validated with Spokes during creation.
            CommentPosition::Errors::Parameter.new(end_path: "must match start_path when commits are the same")
          else
            new(start_path:, start_commit_oid:, start_line:, end_path:, end_commit_oid:, end_line:, base_commit_oid:, head_commit_oid:)
          end
        end
      end

      # Signals inability to reposition the positional data.
      class Indeterminate < T::Struct
        include Positions

        sig { override.returns(Symbol) }
        def type = :indeterminate

        const :base_commit_oid, String
        const :head_commit_oid, String
        const :reason, Symbol

        sig { params(positioning: T::Hash[Symbol, T.untyped]).returns(Indeterminate) }
        def self.parse(positioning)
          base_commit_oid = T.let(positioning[:base_commit_oid].to_s, String)
          head_commit_oid = T.let(positioning[:head_commit_oid].to_s, String)
          reason = positioning[:reason]&.to_sym || :deserialization_failure

          new(reason:, base_commit_oid:, head_commit_oid:)
        end
      end

      # Signals an error occurred while attempting to produce the new positional data.
      class Errored < T::Struct
        include Positions

        const :base_commit_oid, String
        const :head_commit_oid, String
        const :exception, T.nilable(Exception)

        sig { returns(Indeterminate) }
        def to_indeterminate
          Indeterminate.new(reason: :unknown_error, base_commit_oid:, head_commit_oid:)
        end

        sig { override.returns(Symbol) }
        def type = :errored
      end
    end
  end
end
