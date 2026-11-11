# typed: strict
# frozen_string_literal: true

module PullRequests
  module PageData
    module Files
      module FileTree
        class ThreadSummaryLoader
          sig { params(pull_request: PullRequest, threads: T::Enumerable[PullRequestReviewThread], base_oid: String, head_oid: String).void }
          def initialize(pull_request:, threads:, base_oid:, head_oid:)
            @threads = threads
            @pull_request = pull_request
            @base_oid = base_oid
            @head_oid = head_oid
          end

          sig { returns(T::Hash[String, T::Array[Loader::ThreadSummary]]) }
          def load
            result = T.let({}, T::Hash[String, T::Array[Loader::ThreadSummary]])

            PullRequests::CommentPosition.from_pull_request_threads(
              pull_request: @pull_request,
              threads: @threads.to_a,
              destination_base_commit_oid: @base_oid,
              destination_head_commit_oid: @head_oid,
              position_only: true, # Reduce GitRPC traffic as much as we can!
            ).each do |thread, value|
              position = begin
                case value
                when PullRequests::CommentPosition::Errors
                  outdated_reason = "errors"
                  Loader::MarkerPosition::File.instance
                else
                  case positioning = value.positioning
                  when PullRequests::CommentPosition::Positions::Line
                    Loader::MarkerPosition::Line.line(
                      positioning.line,
                      left_sided: positioning.left_sided?,
                    )
                  when PullRequests::CommentPosition::Positions::Multiline
                    Loader::MarkerPosition::LineRange.new(
                      start_line: Loader::MarkerPosition::Line.line(
                        positioning.start_line,
                        left_sided: positioning.left_sided_start?,
                      ),
                      end_line: Loader::MarkerPosition::Line.line(
                        positioning.end_line,
                        left_sided: positioning.left_sided_end?,
                      ),
                    )
                  when PullRequests::CommentPosition::Positions::File
                    Loader::MarkerPosition::File.instance
                  when PullRequests::CommentPosition::Positions::Indeterminate
                    outdated_reason = positioning.reason.to_s
                    Loader::MarkerPosition::File.instance
                  when PullRequests::CommentPosition::Positions::Errored
                    outdated_reason = "positioning errored"
                    Loader::MarkerPosition::File.instance
                  else
                    T.absurd(positioning)
                  end
                end
              end

              (result[thread.path] ||= []) << Loader::ThreadSummary.new(
                id: thread.id,
                created_at: thread.created_at,
                outdated_reason: outdated_reason,
                position:,
              )
            end

            result
          end
        end
      end
    end
  end
end
