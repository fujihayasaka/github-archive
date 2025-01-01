# typed: true
# frozen_string_literal: true

require "secret_scanning_proto"

class Api::Internal::Twirp
  module Secretscanning
    module V1
      class IssuesAPIHandler < SecretScanningAPIHandler
        handles_service(GitHub::Proto::SecretScanning::Issues::V1::IssueAPIService)

        allow_access_for :client

        BATCH_SIZE = 100

        resolve_tenant_context only: %i[
          get_issue,
          get_issue_body_history,
          get_issue_title_history,
          list_issues,
          list_issue_comments
        ] do |req, _env|
          ::Repositories::Public.resolve_tenant(id: req.repo_id)
        rescue ActiveRecord::RecordNotFound => err
          Twirp::Error.not_found(err.message)
        end

        exempt_from_tenant_context_requirement only: %i[
          get_issue_comment,
          get_issue_comment_history
        ]

        sig do
          params(
            req: GitHub::Proto::SecretScanning::Issues::V1::GetIssueRequest,
            env: T::Hash[String, T.untyped]
            )
          .returns(T.any(GitHub::Proto::SecretScanning::Issues::V1::GetIssueResponse, Twirp::Error))
        end
        def get_issue(req, env)
          unless req.issue.present?
            return Twirp::Error.invalid_argument("must be non-empty", argument: "issue")
          end

          unless req.repository.present?
            return Twirp::Error.invalid_argument("must be non-empty", argument: "repository")
          end

          unless req.issue == :issue_number
            return Twirp::Error.invalid_argument("the issue number is not a valid input", argument: "issue")
          end

          unless req.repository == :repo_id
            return Twirp::Error.invalid_argument("the repository is not a valid input", argument: "repository")
          end

          issue = Issue.find_by(repository_id: req.repo_id, number: req.issue_number) # domain-isolation-query-violation:ignore:packages/issues (SELECT)

          unless issue.present?
            return Twirp::Error.not_found("the issue was not found", argument: "issue")
          end

          result = GitHub::Proto::SecretScanning::Issues::V1::Issue.new(
            title: issue.title&.b,
            body: issue.body&.b,
          )

          GitHub::Proto::SecretScanning::Issues::V1::GetIssueResponse.new(
            issue: result
          )
        end

        sig do
          params(
            req: GitHub::Proto::SecretScanning::Issues::V1::GetIssueBodyHistoryRequest,
            env: T::Hash[String, T.untyped]
            )
          .returns(T.any(GitHub::Proto::SecretScanning::Issues::V1::GetIssueBodyHistoryResponse, Twirp::Error))
        end
        def get_issue_body_history(req, env)
          unless req.repo_id.present?
            return Twirp::Error.invalid_argument("must be non-empty", argument: "repo_id")
          end
          unless req.issue_number.present?
            return Twirp::Error.invalid_argument("must be non-empty", argument: "issue_number")
          end

          issue = Issue.find_by(repository_id: req.repo_id, number: req.issue_number) # domain-isolation-query-violation:ignore:packages/issues (SELECT)

          unless issue.present?
            return Twirp::Error.not_found("the issue was not found", argument: "issue_number")
          end

          next_cursor = nil
          last_processed_edit_id = 0
          if req.cursor.present?
            last_processed_edit_id = req.cursor.unpack("Q")[0]
          end

          issue_body_history = []

          has_edits = issue.user_content_edits.exists?
          if has_edits
            edit_batch = issue.user_content_edits.where("id > ?", last_processed_edit_id)
            .order(id: :asc).limit(BATCH_SIZE)

            if edit_batch.any?
              edit_batch.each do |edit|
                issue_body_history.push({
                  body: edit&.diff&.b,
                })
              end

              next_cursor = [T.must(edit_batch.last).id].pack("Q")
            end
          else
            issue_body_history.push({
              body: issue.body&.b
            })
          end

          GitHub::Proto::SecretScanning::Issues::V1::GetIssueBodyHistoryResponse.new(
            issue_body_history: issue_body_history, next_cursor: next_cursor
          )
        end

        sig do
          params(
            req: GitHub::Proto::SecretScanning::Issues::V1::GetIssueTitleHistoryRequest,
            env: T::Hash[String, T.untyped]
            )
          .returns(T.any(GitHub::Proto::SecretScanning::Issues::V1::GetIssueTitleHistoryResponse, Twirp::Error))
        end
        def get_issue_title_history(req, env)
          unless req.repo_id.present?
            return Twirp::Error.invalid_argument("must be non-empty", argument: "repo_id")
          end
          unless req.issue_number.present?
            return Twirp::Error.invalid_argument("must be non-empty", argument: "issue_number")
          end

          issue = Issue.find_by(repository_id: req.repo_id, number: req.issue_number) # domain-isolation-query-violation:ignore:packages/issues (SELECT)

          unless issue.present?
            return Twirp::Error.not_found("the issue was not found", argument: "issue_number")
          end

          next_cursor = nil
          batch = BATCH_SIZE
          last_processed_edit_id = 0
          if req.cursor.present?
            last_processed_edit_id = req.cursor.unpack("Q")[0]
          end

          issue_title_history = []

          first_rename_event = last_processed_edit_id == 0

          # batch size is decremented because the old title counts as 1 item
          if first_rename_event then batch -= 1 end

          has_renames = !issue.events.where(event: "renamed").empty?
          if has_renames
            rename_event_batch = issue.events.where(event: "renamed").where("id > ?", last_processed_edit_id)
              .order(id: :asc).limit(batch)

            if rename_event_batch.any?
              rename_event_batch.each do |event|
                # For the first rename event, include the old title as well
                if first_rename_event
                  issue_title_history.push({
                    title: event&.title_was&.b,
                  })
                end

                issue_title_history.push({
                  title: event&.title_is&.b,
                })
              end
              next_cursor = [T.must(rename_event_batch.last).id].pack("Q")
            end
          else
            issue_title_history.push({
              title: issue.title&.b
            })
          end

          GitHub::Proto::SecretScanning::Issues::V1::GetIssueTitleHistoryResponse.new(
            issue_title_history: issue_title_history, next_cursor: next_cursor
          )
        end

        sig do
          params(
            req: GitHub::Proto::SecretScanning::Issues::V1::GetIssueCommentRequest,
            env: T::Hash[String, T.untyped]
            )
          .returns(T.any(GitHub::Proto::SecretScanning::Issues::V1::GetIssueCommentResponse, Twirp::Error))
        end
        def get_issue_comment(req, env)
          unless req.issue_comment.present?
            return Twirp::Error.invalid_argument("must be non-empty", argument: "issue_comment")
          end

          unless req.issue_comment == :issue_comment_id
            return Twirp::Error.invalid_argument("the issue comment is not a valid input", argument: "issue_comment")
          end

          issue_comment = IssueComment.find_by(id: req.issue_comment_id)

          unless issue_comment.present?
            return Twirp::Error.not_found("the issue comment was not found", argument: "issue_comment")
          end

          result = GitHub::Proto::SecretScanning::Issues::V1::IssueComment.new(
            body: issue_comment.body&.b,
          )

          GitHub::Proto::SecretScanning::Issues::V1::GetIssueCommentResponse.new(
            issue_comment: result
          )
        end

        sig do
          params(
            req: GitHub::Proto::SecretScanning::Issues::V1::GetIssueCommentHistoryRequest,
            env: T::Hash[String, T.untyped]
            )
          .returns(T.any(GitHub::Proto::SecretScanning::Issues::V1::GetIssueCommentHistoryResponse, Twirp::Error))
        end
        def get_issue_comment_history(req, env)
          unless req.issue_comment_id.present?
            return Twirp::Error.invalid_argument("must be non-empty", argument: "issue_comment_id")
          end

          issue_comment = IssueComment.find_by(id: req.issue_comment_id)

          unless issue_comment.present?
            return Twirp::Error.not_found("the issue comment was not found", argument: "issue_comment_id")
          end

          next_cursor = nil
          last_processed_edit_id = 0
          if req.cursor.present?
            last_processed_edit_id = req.cursor.unpack("Q")[0]
          end

          results = []

          has_edits = !issue_comment.user_content_edits.empty?
          if has_edits
            edit_batch = issue_comment.user_content_edits.where("id > ?", last_processed_edit_id)
            .order(id: :asc).limit(BATCH_SIZE)

            if edit_batch.any?
              edit_batch.each do |edit|
                results.push({
                  body: edit&.diff&.b,
                })
              end

              next_cursor = [T.must(edit_batch.last).id].pack("Q")
            end
          else
            results.push({
              body: issue_comment.body&.b,
            })
          end

          GitHub::Proto::SecretScanning::Issues::V1::GetIssueCommentHistoryResponse.new(
            issue_comment_history: results, next_cursor: next_cursor
          )
        end

        sig do
          params(
            req: GitHub::Proto::SecretScanning::Issues::V1::ListIssuesRequest,
            env: T::Hash[String, T.untyped]
            )
          .returns(T.any(GitHub::Proto::SecretScanning::Issues::V1::ListIssuesResponse, Twirp::Error))
        end
        def list_issues(req, env)
          unless req.repo_id.present?
            return Twirp::Error.invalid_argument("must be non-empty", argument: "repo_id")
          end

          repository = T.cast(::Repositories.domain.by_id(req.repo_id), T.nilable(Repository)) # rubocop:todo GitHub/AvoidCast

          unless repository.present?
            return Twirp::Error.not_found("the repository was not found", argument: "repo_id")
          end

          next_cursor = nil
          last_processed_issue_number = 0
          if req.cursor.present?
            unpacked_cursor = req.cursor.unpack("Q")
            last_processed_issue_number = unpacked_cursor[0]
          end

          results = []

          has_issues = !repository.issues.empty? # domain-isolation-query-violation:ignore:packages/issues (SELECT)
          if has_issues
            issue_batch = repository.issues.select(:id, :number).where("number > ?", last_processed_issue_number).where(pull_request_id: nil)
            .order(number: :asc).limit(BATCH_SIZE)

            if issue_batch.any? # domain-isolation-query-violation:ignore:packages/issues (SELECT)
              issue_batch.each do |issue| # domain-isolation-query-violation:ignore:packages/issues (SELECT)
                results.push({
                  issue_number: issue.number,
                  issue_id: issue.id,
                })
              end

              next_cursor = [issue_batch.last&.number, "n"].pack("QA")
            end
          end

          GitHub::Proto::SecretScanning::Issues::V1::ListIssuesResponse.new(
            identifiers: results, next_cursor: next_cursor
          )
        end

        sig do
          params(
            req: GitHub::Proto::SecretScanning::Issues::V1::ListIssueCommentsRequest,
            env: T::Hash[String, T.untyped]
            )
          .returns(T.any(GitHub::Proto::SecretScanning::Issues::V1::ListIssueCommentsResponse, Twirp::Error))
        end
        def list_issue_comments(req, env)
          unless req.repo_id.present?
            return Twirp::Error.invalid_argument("must be non-empty", argument: "repo_id")
          end
          unless req.issue_number.present?
            return Twirp::Error.invalid_argument("must be non-empty", argument: "issue_number")
          end

          issue = Issue.find_by(repository_id: req.repo_id, number: req.issue_number) # domain-isolation-query-violation:ignore:packages/issues (SELECT)

          unless issue.present?
            return Twirp::Error.not_found("the issue was not found", argument: "issue_number")
          end

          next_cursor = nil
          last_processed_issue_comment_id = 0
          if req.cursor.present?
            last_processed_issue_comment_id = req.cursor.unpack("Q")[0]
          end

          results = []

          has_comments = !issue.comments.empty?
          if has_comments
            comment_batch = issue.comments.where("id > ?", last_processed_issue_comment_id)
            .order(id: :asc).limit(BATCH_SIZE)

            if comment_batch.any?
              comment_batch.each do |comment|
                results.push(comment.id)
              end

              next_cursor = [T.must(comment_batch.last).id].pack("Q")
            end
          end

          GitHub::Proto::SecretScanning::Issues::V1::ListIssueCommentsResponse.new(
            issue_comment_ids: results, next_cursor: next_cursor
          )
        end
      end
    end
  end
end
