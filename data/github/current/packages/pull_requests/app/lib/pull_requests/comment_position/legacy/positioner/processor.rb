# typed: strict
# frozen_string_literal: true

module PullRequests
  module CommentPosition
    module Legacy
      module Positioner
        class Processor
          include GitHub::Memoizer

          Result = T.type_alias { T::Hash[Positions, T.nilable(Results)] }

          sig { params(positions: T::Array[Positions], reader: IReader).void }
          def initialize(positions:, reader:)
            @positions = positions
            @reader = reader
          end

          sig { returns(Result) }
          def call
            requests.each { @reader.add_paths(paths: _1.paths, range: _1.range) }

            begin
              @reader.call
            rescue => exception # rubocop:disable Lint/GenericRescue
              # TODO: Error handling.
              raise exception
            end

            requests.to_h do |request|
              range = request.range
              path = request.path

              if line = request.blob_position
                position = @reader.position_for(left_blob: request.left_blob?, path:, range:, line:)

                if position
                  compressed_diff_hunk = @reader.diff_hunk_for(path:, position:, range:,)

                  if line = request.start_line
                    start_line_position = @reader.position_for(left_blob: request.start_left_blob?, path:, line:, range:)

                    if start_line_position
                      start_position_offset = position - start_line_position
                    end
                  end
                end
              end

              right_path = @reader.right_path_for(path:, range:)

              outdated = if request.position.is_a?(Positions::File)
                right_path.blank?
              else
                position.nil?
              end

              path = right_path || path

              columns = Results::Columns.new(
                path:,
                outdated:,
                position:,
                compressed_diff_hunk:,
                start_position_offset:,
                subject_type: request.subject_type,
                commit_id: request.commit_id,
                left_blob: request.left_blob?,
                blob_position: request.blob_position,
                blob_commit_oid: request.blob_commit_oid,
                blob_path: request.blob_path,
              )

              [request.position, columns]
            end
          end

          private

          sig { returns(T::Array[Request]) }
          memoize def requests
            @positions.filter_map do |position|
              case position
              when Positions::File,
                   Positions::Line,
                   Positions::Multiline
                Request.new(position:)
              when Positions::Indeterminate,
                   Positions::Errored
                nil
              else T.absurd(position)
              end
            end
          end
        end
      end
    end
  end
end
