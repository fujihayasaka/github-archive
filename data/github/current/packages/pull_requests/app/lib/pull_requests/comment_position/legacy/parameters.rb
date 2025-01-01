# typed: strict
# frozen_string_literal: true

module PullRequests
  module CommentPosition
    module Legacy
      class Parameters
        include GitHub::Memoizer

        class Attributes < T::Struct
          const :diff_base_commit_id, String
          const :diff_start_commit_id, String
          const :diff_end_commit_id, String
          const :path, String
          const :side, Symbol
          const :start_side, T.nilable(Symbol)
          const :line, T.nilable(Integer)
          const :start_line, T.nilable(Integer)
          const :subject_type, Symbol
          const :positioning, Positions
        end

        class Errors < T::Enum
          enums do
            MissingPositioning = new(:missing_positioning)
            InvalidPositioning = new(:invalid_positioning)
            InvalidSubjectType = new(:invalid_subject_type)
          end
        end

        sig do
          params(
            positioning: T.nilable(T::Hash[T.untyped, T.untyped]),
            start_commit_oid: String,
            end_commit_oid: String,
            base_commit_oid: String,
          ).returns(T.any(Attributes, Errors))
        end
        def self.call(positioning:, start_commit_oid:, end_commit_oid:, base_commit_oid:)
          if positioning.nil? || positioning.blank?
            Errors::MissingPositioning
          else
            new(positioning:, start_commit_oid:, end_commit_oid:, base_commit_oid:).call
          end
        end

        sig do
          params(
            positioning: T::Hash[T.untyped, T.untyped],
            start_commit_oid: String,
            end_commit_oid: String,
            base_commit_oid: String,
          ).void
        end
        def initialize(positioning:, start_commit_oid:, end_commit_oid:, base_commit_oid:)
          @positioning = T.let(positioning.with_indifferent_access, ActiveSupport::HashWithIndifferentAccess)
          @range = T.let(Positions::DiffRange.new(start_commit_oid:, end_commit_oid:, base_commit_oid:), Positions::DiffRange)
        end


        sig { returns(T.any(Attributes, Errors)) }
        def call
          # See: CreateNewPullRequestReviewCommentOrchestration
          diff_base_commit_id = @range.base_commit_oid
          diff_start_commit_id = @range.start_commit_oid
          diff_end_commit_id = @range.end_commit_oid

          case positioning = self.positioning
          when Errors
            positioning
          when Positions::File
            Attributes.new(
              diff_base_commit_id:,
              diff_start_commit_id:,
              diff_end_commit_id:,
              side: side_for(positioning.commit_oid),
              path: positioning.path,
              subject_type: :file,
              positioning:,
            )
          when Positions::Line
            Attributes.new(
              diff_base_commit_id:,
              diff_start_commit_id:,
              diff_end_commit_id:,
              path: positioning.path,
              side: side_for(positioning.commit_oid),
              line: positioning.line - 1,
              subject_type: :line,
              positioning:,
            )
          when Positions::Multiline
            Attributes.new(
              diff_base_commit_id:,
              diff_start_commit_id:,
              diff_end_commit_id:,
              path: positioning.end_path,
              side: side_for(positioning.end_commit_oid),
              start_side: side_for(positioning.end_commit_oid),
              line: positioning.end_line - 1,
              start_line: positioning.start_line - 1,
              subject_type: :line,
              positioning:,
            )
          end
        end

        private

        sig { params(commit_oid: String).returns(Symbol) }
        def side_for(commit_oid)
          commit_oid == range.start_commit_oid ? :left : :right
        end

        sig { returns(Positions::DiffRange) }
        attr_reader :range

        # TODO: This should be shared behavior somewhere.
        sig { returns(T.any(Positions::Valid, Errors)) }
        memoize def positioning
          begin
            case @positioning[:type]&.to_s&.downcase
            when "file"
              path, commit_oid = @positioning.values_at(:path, :commit_oid)

              Positions::File.new(
                path:,
                commit_oid:,
                range:
              )
            when "line"
              path, commit_oid, line = @positioning.values_at(:path, :commit_oid, :line)

              Positions::Line.new(
                path:,
                commit_oid:,
                range:,
                line: line&.to_i,
              )
            when "multiline"
              start_path, start_commit_oid, start_line = @positioning.values_at(:start_path, :start_commit_oid, :start_line)
              end_path, end_commit_oid, end_line = @positioning.values_at(:end_path, :end_commit_oid, :end_line)

              Positions::Multiline.new(
                start_path:,
                start_commit_oid:,
                start_line: start_line&.to_i,
                end_path:,
                end_commit_oid:,
                end_line: end_line&.to_i,
                range:
              )
            else
              Errors::InvalidSubjectType
            end
          rescue ArgumentError, TypeError
            Errors::InvalidPositioning
          end
        end
      end
    end
  end
end
