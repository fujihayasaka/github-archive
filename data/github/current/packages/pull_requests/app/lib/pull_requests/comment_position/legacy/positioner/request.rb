# typed: strict
# frozen_string_literal: true

module PullRequests
  module CommentPosition
    module Legacy
      module Positioner
        class Request
          sig { params(position: T.any(Positions::File, Positions::Line, Positions::Multiline)).void }
          def initialize(position:)
            @position = position
          end

          sig { returns(T.any(Positions::File, Positions::Line, Positions::Multiline)) }
          attr_reader :position

          sig { returns(Symbol) }
          def subject_type
            case @position
            when Positions::File      then :file
            when Positions::Line      then :line
            when Positions::Multiline then :line
            else T.absurd(@position)
            end
          end

          sig { returns(T.nilable(Integer)) }
          def line
            case @position
            when Positions::File      then nil
            when Positions::Line      then @position.line
            when Positions::Multiline then @position.end_line
            else T.absurd(@position)
            end
          end

          sig { returns(T.nilable(Integer)) }
          def start_line
            case @position
            when Positions::File      then nil
            when Positions::Line      then nil
            when Positions::Multiline then @position.start_line - 1
            else T.absurd(@position)
            end
          end

          sig { returns(String) }
          def path
            case @position
            when Positions::File      then @position.path
            when Positions::Line      then @position.path
            when Positions::Multiline then @position.end_path
            else T.absurd(@position)
            end
          end

          sig { returns(T::Array[String]) }
          def paths
            case @position
            when Positions::File      then [@position.path]
            when Positions::Line      then [@position.path]
            when Positions::Multiline then [@position.start_path, @position.end_path]
            else T.absurd(@position)
            end
          end

          sig { returns(String) }
          def blob_path = path

          sig { returns(T.nilable(Integer)) }
          def blob_position
            case @position
            when Positions::File      then nil
            when Positions::Line      then @position.line - 1
            when Positions::Multiline then @position.end_line - 1
            else T.absurd(@position)
            end
          end

          sig { returns(T::Boolean) }
          def left_blob?
            case @position
            when Positions::File      then range.start_commit_oid == @position.commit_oid
            when Positions::Line      then range.start_commit_oid == @position.commit_oid
            when Positions::Multiline then range.start_commit_oid == @position.end_commit_oid
            else T.absurd(@position)
            end
          end

          sig { returns(T::Boolean) }
          def start_left_blob?
            case @position
            when Positions::File      then false
            when Positions::Line      then false
            when Positions::Multiline then range.start_commit_oid == @position.start_commit_oid
            else T.absurd(@position)
            end
          end

          sig { returns(String) }
          def commit_id = range.end_commit_oid

          sig { returns(String) }
          def blob_commit_oid = left_blob? ? range.start_commit_oid : range.end_commit_oid

          sig { returns(Positions::DiffRange) }
          def range = @position.range
        end
      end
    end
  end
end
