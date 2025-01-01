# typed: true
# frozen_string_literal: true

require "secret_scanning_proto"

class Api::Internal::Twirp
  module Secretscanning
    module V1
      class PullRequestsAPIHandler < SecretScanningAPIHandler
        include SecretScanning::Features::FeatureFlagHelper

        handles_service(GitHub::Proto::SecretScanning::PullRequests::V1::PullRequestsAPIService)

        allow_access_for :client

        BATCH_SIZE = 75
        CursorValue = GitHub::Proto::SecretScanning::PullRequests::V1::StreamPullRequestCursorValue
        PullRequestContent = GitHub::Proto::SecretScanning::PullRequests::V1::PullRequestContent
        PullRequestContentType = GitHub::Proto::SecretScanning::PullRequests::V1::PullRequestContentType

        resolve_tenant_context only: %i[
          list_pull_requests,
          stream_pull_request_content
        ] do |req, _env|
          ::Repositories::Public.resolve_tenant(id: req.repo_id)
        rescue ActiveRecord::RecordNotFound => err
          Twirp::Error.not_found(err.message)
        end

        sig do
          params(
            req: GitHub::Proto::SecretScanning::PullRequests::V1::StreamPullRequestContentRequest,
            env: T::Hash[String, T.untyped]
            )
          .returns(T.any(GitHub::Proto::SecretScanning::PullRequests::V1::StreamPullRequestContentResponse, Twirp::Error))
        end
        def stream_pull_request_content(req, env)
          # validate request
          unless req.repo_id.present?
            return Twirp::Error.invalid_argument("must be non-empty", argument: "repo_id")
          end
          unless req.pull_request_number.present?
            return Twirp::Error.invalid_argument("must be non-empty", argument: "pull_request_number")
          end

          issue = Issue.find_by(repository_id: req.repo_id, number: req.pull_request_number)
          unless issue.present?
            return Twirp::Error.not_found("the pull request was not found", argument: "pull_request_number")
          end

          # initialize cursor variables
          content_type = T.let(:BODY, Symbol)
          pr_cursor = CursorValue.new # PR cursor navigates the direct children of the PR (body, title, comment, review)
          comment_edits_cursor = CursorValue.new # these cursors navigate the edits/review comments
          review_edits_cursor = CursorValue.new
          review_comment_cursor = CursorValue.new
          review_comment_edits_cursor = CursorValue.new

          # extract cursor variables from request
          if req.cursor.present?
            # in practice, content_type is already a symbol, but since the RBI Sorbet suggests it could be an integer
            # we want to convert it just in case to prevent complete failure of all the if conditions here
            content_type = ensure_is_symbol(T.must(req.cursor).content_type, content_type)
            pr_cursor = T.must(req.cursor).cursors[0]

            # index 1 (for nesting level 2) can be one of several cursors depending on the content type
            comment_edits_cursor = get_cursor_id(req.cursor, 1) if req.cursor&.cursors.present?
            review_edits_cursor = get_cursor_id(req.cursor, 1) if content_type == :REVIEW
            if content_type == :REVIEW_COMMENT
              review_comment_cursor = get_cursor_id(req.cursor, 1)
              # index 2 (for nesting level 3) will be present if we're iterating a review comment's edits
              review_comment_edits_cursor = get_cursor_id(req.cursor, 2)
            end
          end

          results = []

          # Get the Body and any edits
          if content_type == :BODY && results.size < BATCH_SIZE
            new_results, completed, pr_cursor = get_body_edits(issue, pr_cursor, BATCH_SIZE - results.size)
            results.concat(new_results)

            if completed
              content_type = :TITLE
              pr_cursor = CursorValue.new(last_id: 0, revision: 0)
            end
          end

          # Get the Title and any edits
          if content_type == :TITLE && results.size < BATCH_SIZE
            new_results, completed, pr_cursor = get_title_edits(issue, pr_cursor, BATCH_SIZE - results.size)
            results.concat(new_results)
            if completed
              content_type = :COMMENT
              pr_cursor = CursorValue.new
            end
          end

          # Iterate each Comment
          if content_type == :COMMENT && results.size < BATCH_SIZE
            loop do
              next_issue_comment_id_clause = issue.comments.select(:id).where("id > ?", pr_cursor.last_id).order(id: :asc).limit(1).to_sql
              comment = IssueComment.where("id = (#{next_issue_comment_id_clause})").first
              # get the Comment and any edits
              if comment.present?
                new_results, completed, comment_edits_cursor = get_comment_edits(comment, comment_edits_cursor, BATCH_SIZE - results.size)
                results.concat(new_results)

                # if we've finished processing a comment, advance to the next one
                if completed
                  pr_cursor.last_id = comment.id
                  pr_cursor.created_at = nil
                  comment_edits_cursor = CursorValue.new
                end
              else
                # if there are no more comments to scan, we're done
                content_type = :REVIEW
                pr_cursor = CursorValue.new
              end
              break unless comment.present? && results.size < BATCH_SIZE
            end
          end

          # iterate each Review
          review_completed = T.let(false, T::Boolean)
          pull_request = issue.pull_request
          if pull_request.present?
            if (content_type == :REVIEW || content_type == :REVIEW_COMMENT) && results.size < BATCH_SIZE
              loop do
                created_at_target = to_time(pr_cursor.created_at)
                next_pr_review_id_clause = pull_request.reviews.select(:id).where("created_at >= ?", created_at_target)
                  .where("not (created_at = ? AND id <= ?)", created_at_target, pr_cursor.last_id)
                  .order(created_at: :asc, id: :asc).limit(1).to_sql

                # Fallback for no timestamp on the cursor for backwards compatibility
                # Can remove on next update
                if pr_cursor.last_id > 0 && !pr_cursor.created_at.present?
                  next_pr_review_id_clause = pull_request.reviews.select(:id).where("id > ?", pr_cursor.last_id).order(id: :asc).limit(1).to_sql
                end

                review = PullRequestReview.where("id = (#{next_pr_review_id_clause})").first

                if review.present?
                  # get the Review body and any edits
                  if content_type == :REVIEW
                    new_results, review_history_completed, review_edits_cursor = get_review_edits(
                      review,
                      review_edits_cursor,
                      BATCH_SIZE - results.size
                    )
                    results.concat(new_results)
                    if review_history_completed # if the review history is completed...
                      content_type = :REVIEW_COMMENT # start on review comments
                      review_edits_cursor = CursorValue.new
                    end # otherwise we'll pick back up with the review history on the same review in the next call
                  end

                  # iterate each Review Comment
                  review_comment_completed = T.let(false, T::Boolean)
                  if content_type == :REVIEW_COMMENT && results.size < BATCH_SIZE
                    loop do
                      next_comment_id_clause = review.review_comments.select(:id).where("id > ?", review_comment_cursor.last_id).order(id: :asc).limit(1).to_sql
                      review_comment = PullRequestReviewComment.where("id = (#{next_comment_id_clause})").first

                      #  get the Review Comment and any edits
                      if review_comment.present?
                        new_results, review_comment_history_completed, review_comment_edits_cursor = get_review_comment_edits(
                          review_comment,
                          review_comment_edits_cursor,
                          BATCH_SIZE - results.size
                        )
                        results.concat(new_results)
                        if review_comment_history_completed
                          # if we've finished processing a review comment...
                          review_comment_cursor.last_id = T.must(review_comment.id) # advance to the next one
                          review_comment_edits_cursor = CursorValue.new
                        end
                      else
                        # if we've finished the last review comment...
                        content_type = :REVIEW # back to review bodies
                        pr_cursor.last_id = review.id # but on the next review
                        pr_cursor.created_at = proto_time(review.created_at)
                        review_comment_cursor = CursorValue.new
                        review_comment_completed = true
                      end # otherwise we'll pick back up with review comments on the same review in the next call
                      break if review_comment_completed || results.size >= BATCH_SIZE
                    end
                  end
                else
                  # Finished last review, we're done
                  review_completed = true
                end
                break if review_completed || results.size >= BATCH_SIZE # end this API call if we're done or the batch is full
              end
            end
          else
            GitHub.logger.info(
              "Issue had a pull request id that did not exist",
              "code.namespace": self.class.name,
              "gh.repo.id": req.repo_id,
              "gh.pull_request.number": req.pull_request_number
            )

            review_completed = true
          end

          # build the serializable cursor from the variables
          next_cursor = nil
          unless review_completed
            cursors = [pr_cursor]
            cursors.push(comment_edits_cursor) if content_type == :COMMENT
            cursors.push(review_edits_cursor) if content_type == :REVIEW
            if content_type == :REVIEW_COMMENT
              cursors.push(review_comment_cursor)
              cursors.push(review_comment_edits_cursor)
            end

            next_cursor = GitHub::Proto::SecretScanning::PullRequests::V1::StreamPullRequestContentResponseCursor.new(
              content_type: content_type,
              cursors: cursors
            )
          end

          GitHub::Proto::SecretScanning::PullRequests::V1::StreamPullRequestContentResponse.new(
            contents: results, next_cursor: next_cursor
          )
        end

        sig do
          params(
            req: GitHub::Proto::SecretScanning::PullRequests::V1::ListPullRequestsRequest,
            env: T::Hash[String, T.untyped]
            )
          .returns(T.any(GitHub::Proto::SecretScanning::PullRequests::V1::ListPullRequestsResponse, Twirp::Error))
        end
        def list_pull_requests(req, env)
          unless req.repo_id.present?
            return Twirp::Error.invalid_argument("must be non-empty", argument: "repo_id")
          end

          repository = Repository.find_by(id: req.repo_id)

          unless repository.present?
            return Twirp::Error.not_found("the repository was not found", argument: "repo_id")
          end

          next_cursor = nil
          last_processed_pull_request_id = 0
          if req.cursor.present?
            unpacked_cursor = req.cursor.unpack("Q")
            last_processed_pull_request_id = unpacked_cursor[0]
          end

          results = []

          has_issues = repository.issues.count > 0
          if has_issues
            issue_batch = repository.issues.select(:id, :number, :pull_request_id).from("issues FORCE INDEX(index_issues_on_repository_id_and_pull_request_id_and_created_at)")
            .where("pull_request_id > ?", last_processed_pull_request_id)
            .order(pull_request_id: :asc).limit(BATCH_SIZE)

            if issue_batch.any?
              issue_batch.each do |issue|
                results.push({
                  pull_request_number: issue.number,
                  pull_request_id: issue.id, # this is expected to be the issue id of the pull request as elsewhere in this file
                })
              end

              next_cursor = [issue_batch.last&.pull_request_id, "i"].pack("QA") # we paginate with the actual pull_request_id
            end
          end

          GitHub::Proto::SecretScanning::PullRequests::V1::ListPullRequestsResponse.new(
            identifiers: results, next_cursor: next_cursor
          )
        end

        # private
        sig do
          params(
            issue: Issue,
            cursor: CursorValue,
            remaining_batch_size: Integer
          ).returns([T::Array[PullRequestContent], T::Boolean, CursorValue])
        end
        def get_body_edits(issue, cursor, remaining_batch_size)
          results = []
          last_edit_id = nil
          completed = false

          has_edits = issue.user_content_edits.count > 0
          if has_edits
            revision = cursor.revision
            # query for the edits
            edit_batch = issue.user_content_edits.where("id > ?", cursor.last_id)
            .order(id: :asc).limit(remaining_batch_size)

            if edit_batch.any?
              # loop through them and build the response
              edit_batch.each do |edit|
                results.push({
                  content: edit&.diff&.b,
                  type: PullRequestContentType::BODY,
                  id: issue.id,
                  revision: revision
                })
                revision += 1 # keep track of the revision, starting at 0
              end

              last_edit_id = T.must(edit_batch.last).id
              completed = true if results.length < remaining_batch_size # if we couldn't fill the batch, we've done
            else
              completed = true # If there are no more edits, we're done. This is in case it exactly matches the batch size.
            end
          else
            # if the body has not been edited, the only copy is on the actual issue
            results.push({
              content: issue.body&.b,
              type: PullRequestContentType::BODY,
              id: issue.id,
              revision: 0
            })
            completed = true
          end

          [results, completed, CursorValue.new(last_id: last_edit_id, revision: revision)]
        end

        sig do
          params(
            issue: Issue,
            cursor: CursorValue,
            remaining_batch_size: Integer
          ).returns([T::Array[PullRequestContent], T::Boolean, CursorValue])
        end
        def get_title_edits(issue, cursor, remaining_batch_size)
          results = []
          last_edit_id = nil
          completed = false

          first_rename_event = T.let(cursor.last_id == 0, T::Boolean)

          # rename events each point to an old and a new value
          # we will count the first rename event as 2 items
          if first_rename_event then remaining_batch_size -= 1 end

          has_renames = issue.events.where(event: "renamed").count > 0
          if has_renames
            revision = cursor.revision
            # query for the rename events
            rename_event_batch = issue.events.where(event: "renamed").where("id > ?", cursor.last_id)
              .order(id: :asc).limit(remaining_batch_size)

            if rename_event_batch.any?
              # loop through the rename events and buld the response
              rename_event_batch.each do |event|
                # For the first rename event, include the old title as well
                if first_rename_event
                  first_rename_event = false
                  results.push({
                    content: event&.title_was&.b,
                    type: GitHub::Proto::SecretScanning::PullRequests::V1::PullRequestContentType::TITLE,
                    id: issue.id,
                    revision: 0
                  })
                end
                revision = 1 if revision == 0

                results.push({
                  content: event&.title_is&.b,
                  type: GitHub::Proto::SecretScanning::PullRequests::V1::PullRequestContentType::TITLE,
                  id: issue.id,
                  revision: revision
                })
                revision += 1
              end
              last_edit_id = T.must(rename_event_batch.last).id
              completed = true if results.length < remaining_batch_size
            else
              completed = true
            end
          else
            # if there are no rename events, simply include the current title instead
            results.push({
              content: issue.title&.b,
              type: GitHub::Proto::SecretScanning::PullRequests::V1::PullRequestContentType::TITLE,
              id: issue.id,
              revision: 0
            })
            completed = true
          end

          [results, completed, CursorValue.new(last_id: last_edit_id, revision: revision)]
        end

        sig do
          params(
            comment: IssueComment,
            cursor: CursorValue,
            remaining_batch_size: Integer
          ).returns([T::Array[PullRequestContent], T::Boolean, CursorValue])
        end
        def get_comment_edits(comment, cursor, remaining_batch_size)
          results = []
          last_edit_id = nil
          completed = false

          has_edits = comment.user_content_edits.count > 0
          if has_edits
            revision = cursor.revision
            # query for the comment edits
            edit_batch = comment.user_content_edits.where("id > ?", cursor.last_id)
            .order(id: :asc).limit(remaining_batch_size)

            if edit_batch.any?
              # loop through each edit and build the response
              edit_batch.each do |edit|
                results.push({
                  content: edit&.diff&.b,
                  type: GitHub::Proto::SecretScanning::PullRequests::V1::PullRequestContentType::COMMENT,
                  id: comment.id,
                  revision: revision
                })
                revision += 1
              end

              last_edit_id = T.must(edit_batch.last).id
              completed = true if results.length < remaining_batch_size
            else
              completed = true
            end
          else
            # if there are no edits, we need to use the value on the comment itself
            results.push({
              content: comment.body&.b,
              type: GitHub::Proto::SecretScanning::PullRequests::V1::PullRequestContentType::COMMENT,
              id: comment.id,
              revision: 0
            })
            completed = true
          end

          [results, completed, CursorValue.new(last_id: last_edit_id, revision: revision)]
        end

        sig do
          params(
            review: PullRequestReview,
            cursor: CursorValue,
            remaining_batch_size: Integer
          ).returns([T::Array[GitHub::Proto::SecretScanning::PullRequests::V1::PullRequestContent], T::Boolean, CursorValue])
        end
        def get_review_edits(review, cursor, remaining_batch_size)
          results = []
          last_edit_id = nil
          completed = false

          has_edits = review.user_content_edits.count > 0
          if has_edits
            revision = cursor.revision
            # query for the review edits
            edit_batch = review.user_content_edits.where("id > ?", cursor.last_id)
            .order(id: :asc).limit(remaining_batch_size)

            if edit_batch.any?
              # loop through each review edit and build a response
              edit_batch.each do |edit|
                results.push({
                  content: edit&.diff&.b,
                  type: GitHub::Proto::SecretScanning::PullRequests::V1::PullRequestContentType::REVIEW,
                  id: review.id,
                  revision: revision
                })
                revision += 1
              end

              last_edit_id = T.must(edit_batch.last).id
              completed = true if results.length < remaining_batch_size
            else
              completed = true
            end
          else
            # if there is no review edits, get the current value from the review itself
            results.push({
              content: review.body&.b,
              type: GitHub::Proto::SecretScanning::PullRequests::V1::PullRequestContentType::REVIEW,
              id: review.id,
              revision: 0
            })
            completed = true
          end

          [results, completed, CursorValue.new(last_id: last_edit_id, revision: revision)]
        end

        sig do
          params(
            review_comment: PullRequestReviewComment,
            cursor: CursorValue,
            remaining_batch_size: Integer
          ).returns([T::Array[GitHub::Proto::SecretScanning::PullRequests::V1::PullRequestContent], T::Boolean, CursorValue])
        end
        def get_review_comment_edits(review_comment, cursor, remaining_batch_size)
          results = []
          last_edit_id = nil
          completed = false

          has_edits = review_comment.user_content_edits.count > 0
          if has_edits
            revision = cursor.revision
            # query for the review comment edits
            edit_batch = review_comment.user_content_edits.where("id > ?", cursor.last_id)
            .order(id: :asc).limit(remaining_batch_size)

            if edit_batch.any?
              # loop through the edits and build the response
              edit_batch.each do |edit|
                results.push({
                  content: edit&.diff&.b,
                  type: GitHub::Proto::SecretScanning::PullRequests::V1::PullRequestContentType::REVIEW_COMMENT,
                  id: review_comment.id,
                  revision: revision
                })
                revision += 1
              end

              last_edit_id = T.must(edit_batch.last).id
              completed = true if results.length < remaining_batch_size
            else
              completed = true
            end
          else
            # if there are no edits, get the value from the review comment itself
            results.push({
              content: review_comment.body&.b,
              type: GitHub::Proto::SecretScanning::PullRequests::V1::PullRequestContentType::REVIEW_COMMENT,
              id: review_comment.id,
              revision: 0
            })
            completed = true
          end

          [results, completed, CursorValue.new(last_id: last_edit_id, revision: revision)]
        end


        # Utility Helpers

        sig do
          params(
            proto_time: T.nilable(Google::Protobuf::Timestamp)
          ).returns(Time)
        end
        def to_time(proto_time)
          unless proto_time.present?
            return Time.at(0)
          end

          Time.at(proto_time.nanos * 10**-9 + proto_time.seconds)
        end

        sig do
          params(
            time: Time
          ).returns(T.nilable(Google::Protobuf::Timestamp))
        end
        def proto_time(time)
          return nil if time == Time.at(0)
          seconds = time.to_i
          nanos = time.nsec
          Google::Protobuf::Timestamp.new(seconds: seconds, nanos: nanos)
        end

        sig do
          params(
            request_cursor: T.nilable(GitHub::Proto::SecretScanning::PullRequests::V1::StreamPullRequestContentResponseCursor),
            index: Integer
          ).returns(CursorValue)
        end
        def get_cursor_id(request_cursor, index)
          return CursorValue.new if request_cursor.nil?
          return CursorValue.new if request_cursor.cursors.nil?
          request_cursor.cursors[index] || CursorValue.new
        end

        sig do
          params(
            value: T.any(Symbol, Integer),
            default_value: Symbol
          ).returns(Symbol)
        end
        def ensure_is_symbol(value, default_value)
          return PullRequestContentType.lookup(value) || default_value if value.is_a?(Integer)
          value
        end
      end
    end
  end
end
