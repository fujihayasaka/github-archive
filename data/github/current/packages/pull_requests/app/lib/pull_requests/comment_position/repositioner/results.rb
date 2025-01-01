# typed: strict
# frozen_string_literal: true

module PullRequests
  module CommentPosition
    module Repositioner
      # Structures describing the resulting data points determined across the lifecycle of the processor. Enables logging
      # all relevant data used in the business logic processing.
      module Results
        extend T::Helpers

        abstract!
        sealed!

        sig { abstract.returns(Positions) }
        def to_position; end

        sig { abstract.returns(String) }
        def base_commit_oid; end

        sig { abstract.returns(String) }
        def head_commit_oid; end

        sig { params(reason: Symbol).returns(Positions::Indeterminate) }
        def indeterminate(reason) = Positions::Indeterminate.new(reason:, base_commit_oid:, head_commit_oid:)

        # Shared helper to convert blob states in to human readable invalid reasons.
        sig { params(state: Blob::State).returns(T.nilable(Positions::Indeterminate)) }
        def indeterminate_from_state(state)
          case state
          when Blob::State::Current         then nil
          when Blob::State::Repositioned    then nil
          when Blob::State::NotRequested    then indeterminate(:cannot_resolve_path)
          when Blob::State::RemovedLine     then indeterminate(:cannot_reposition_line)
          when Blob::State::RemovedPath     then indeterminate(:cannot_resolve_path)
          when Blob::State::InvalidPath     then indeterminate(:cannot_resolve_path)
          when Blob::State::ContentTooLarge then indeterminate(:blob_contents_too_large)
          when Blob::State::Unknown         then indeterminate(:unknown_error)
          end
        end

        class File < T::Struct
          include Results

          const :base_commit_oid, String
          const :head_commit_oid, String
          const :commit_oid, String
          const :path, T.nilable(String)
          const :state, Blob::State

          sig { override.returns(T.any(Positions::File, Positions::Indeterminate)) }
          def to_position
            position = indeterminate_from_state(state)

            return position if position
            return indeterminate(:cannot_resolve_path) unless path = self.path

            Positions::File.new(path:, commit_oid:, base_commit_oid:, head_commit_oid:)
          end
        end

        class Line < T::Struct
          include Results

          const :base_commit_oid, String
          const :head_commit_oid, String
          const :commit_oid, String
          const :path, T.nilable(String)
          const :line, T.nilable(Integer)
          const :state, Blob::State

          sig { override.returns(T.any(Positions::Line, Positions::Indeterminate)) }
          def to_position
            position = indeterminate_from_state(state)

            return position if position
            return indeterminate(:cannot_resolve_path) unless path = self.path
            return indeterminate(:cannot_resolve_line) unless line = self.line

            Positions::Line.new(commit_oid:, path:, line:, base_commit_oid:, head_commit_oid:)
          end
        end

        class Multiline < T::Struct
          include Results

          const :base_commit_oid, String
          const :head_commit_oid, String
          const :start_commit_oid, String
          const :start_path, T.nilable(String)
          const :start_line, T.nilable(Integer)
          const :start_state, Blob::State
          const :end_commit_oid, String
          const :end_path, T.nilable(String)
          const :end_line, T.nilable(Integer)
          const :end_state, Blob::State

          sig { override.returns(T.any(Positions::Multiline, Positions::Indeterminate)) }
          def to_position
            start_position_indeterminate = indeterminate_from_state(start_state)
            end_position_indeterminate = indeterminate_from_state(end_state)

            return start_position_indeterminate if start_position_indeterminate
            return end_position_indeterminate if end_position_indeterminate
            return indeterminate(:cannot_resolve_start_path) unless start_path = self.start_path
            return indeterminate(:cannot_resolve_end_path) unless end_path = self.end_path
            return indeterminate(:cannot_resolve_start_line) unless start_line = self.start_line
            return indeterminate(:cannot_resolve_end_line) unless end_line = self.end_line

            Positions::Multiline.new(
              start_commit_oid:, start_path:, start_line:,
              end_commit_oid:, end_path:, end_line:,
              base_commit_oid:, head_commit_oid:
            )
          end
        end

        class Ineligible < T::Struct
          include Results

          const :base_commit_oid, String
          const :head_commit_oid, String
          const :position, T.any(Positions::Indeterminate, Positions::Errored)

          alias to_position position
        end
      end
    end
  end
end
