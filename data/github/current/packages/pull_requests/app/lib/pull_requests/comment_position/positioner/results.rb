# typed: strict
# frozen_string_literal: true

module PullRequests
  module CommentPosition
    module Positioner
      # Structures describing the resulting data points determined across the lifecycle of the processor. Enables logging
      # all relevant data used in the business logic processing.
      module Results
        extend T::Helpers

        # Union type versus sealed! as this automatically allows methods that are defined on each type to work without
        # declaring them as an interface.
        Union = T.type_alias { T.any(File, Line, Multiline) }

        class File < T::Struct
          const :range, Positions::DiffRange
          const :commit_oid, String
          const :path, T.nilable(String)
          const :repositioned, T::Boolean, default: true

          sig { returns(T.any(Positions::File, Positions::Indeterminate)) }
          def to_position
            unless path = self.path
              return Positions::Indeterminate.new(reason: :cannot_resolve_path, range:)
            end

            Positions::File.new(path:, commit_oid:, range:)
          end
        end

        class Line < T::Struct
          const :range, Positions::DiffRange
          const :commit_oid, String
          const :path, T.nilable(String)
          const :line, T.nilable(Integer)
          const :repositioned, T::Boolean, default: true

          sig { returns(T.any(Positions::Line, Positions::Indeterminate)) }
          def to_position
            unless path = self.path
              return Positions::Indeterminate.new(reason: :cannot_resolve_path, range:)
            end

            unless line = self.line
              return Positions::Indeterminate.new(reason: :cannot_resolve_line, range:)
            end

            Positions::Line.new(
              commit_oid:,
              path:,
              line:,
              range:
            )
          end
        end

        class Multiline < T::Struct
          const :range, Positions::DiffRange
          const :start_commit_oid, String
          const :start_path, T.nilable(String)
          const :start_line, T.nilable(Integer)
          const :end_commit_oid, String
          const :end_path, T.nilable(String)
          const :end_line, T.nilable(Integer)
          const :repositioned, T::Boolean, default: true

          sig { returns(T.any(Positions::Multiline, Positions::Indeterminate)) }
          def to_position
            start_path = self.start_path
            end_path = self.end_path

            if start_path.nil? || end_path.nil?
              return Positions::Indeterminate.new(reason: :cannot_resolve_path, range:)
            end

            start_line = self.start_line
            end_line = self.end_line

            if start_line.nil? || end_line.nil?
              return Positions::Indeterminate.new(reason: :cannot_resolve_line, range:)
            end

            Positions::Multiline.new(
              start_commit_oid:,
              start_path:,
              start_line:,
              end_commit_oid:,
              end_path:,
              end_line:,
              range:
            )
          end
        end
      end
    end
  end
end
