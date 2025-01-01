# typed: true
# frozen_string_literal: true

require "secret_scanning_proto"

class Api::Internal::Twirp
  module Secretscanning
    module V1
      class DiscussionsAPIHandler < SecretScanningAPIHandler
        handles_service(GitHub::Proto::SecretScanning::Discussions::V1::DiscussionAPIService)

        allow_access_for :client

        BATCH_SIZE = 100
        CursorValue = GitHub::Proto::SecretScanning::Discussions::V1::StreamDiscussionCursorValue
        DiscussionContent = GitHub::Proto::SecretScanning::Discussions::V1::DiscussionContent
        DiscussionContentType = GitHub::Proto::SecretScanning::Discussions::V1::DiscussionContentType

        resolve_tenant_context only: %i[
          list_discussions,
          stream_discussion_content
        ] do |req, _env|
          ::Repositories::Public.resolve_tenant(id: req.repo_id)
        rescue ActiveRecord::RecordNotFound => err
          Twirp::Error.not_found(err.message)
        end

        sig do
          params(
            req: GitHub::Proto::SecretScanning::Discussions::V1::StreamDiscussionContentRequest,
            env: T::Hash[String, T.untyped]
            )
          .returns(T.any(GitHub::Proto::SecretScanning::Discussions::V1::StreamDiscussionContentResponse, Twirp::Error))
        end
        def stream_discussion_content(req, env)
          # validate request
          unless req.repo_id.present?
            return Twirp::Error.invalid_argument("must be non-empty", argument: "repo_id")
          end
          unless req.discussion_number.present?
            return Twirp::Error.invalid_argument("must be non-empty", argument: "discussion_number")
          end

          discussion = Discussion.find_by(repository_id: req.repo_id, number: req.discussion_number)
          unless discussion.present?
            return Twirp::Error.not_found("the discussion was not found", argument: "discussion_number")
          end

          # initialize default cursor variables
          default_content_type = T.let(:TITLE, Symbol)
          content_type = default_content_type
          discussion_cursor = CursorValue.new # Navigates the direct children of the discussion (body, title, comments)
          comment_edits_cursor = CursorValue.new # Navigates edits to comments

          # extract cursor variables from request
          if req.cursor.present?
            # In practice, content_type is already a symbol, but since the RBI Sorbet suggests it could be an integer
            # we want to convert it just in case to prevent complete failure of all the if conditions here
            cursor_value = T.must(req.cursor).content_type
            if cursor_value.is_a?(Integer)
              content_type = DiscussionContentType.lookup(cursor_value) || default_content_type
            else
              content_type = cursor_value
            end
            discussion_cursor = T.must(req.cursor).cursors[0]
            comment_edits_cursor = get_cursor_id(req.cursor, 1) if req.cursor&.cursors.present?
          end

          results = []

          # Get title
          if content_type == :TITLE && results.size < BATCH_SIZE
            results.push({
              content: discussion.title&.b,
              type: DiscussionContentType::TITLE,
              id: discussion.id,
              revision: 0
            })

            # Note: Discussions do not store edit history for the title, so we can skip to the body
            content_type = :BODY
            discussion_cursor = CursorValue.new
          end

          # Get body and edits
          if content_type == :BODY && results.size < BATCH_SIZE
            new_results, completed, discussion_cursor = get_body_edits(discussion, discussion_cursor, BATCH_SIZE - results.size)
            results.concat(new_results)

            # If we are done with the body, set the cursor to comments
            if completed
              content_type = :COMMENT
              discussion_cursor = CursorValue.new
            end
          end

          # Iterate over each comment
          comments_completed = T.let(false, T::Boolean)
          if content_type == :COMMENT && results.size < BATCH_SIZE
            loop do
              next_discussion_comment_id_clause = discussion.comments.select(:id).where("id > ?", discussion_cursor.last_id).order(id: :asc).limit(1).to_sql
              comment = DiscussionComment.where("id = (#{next_discussion_comment_id_clause})").first
              # Get the comment and any edits
              if comment.present?
                new_results, completed, comment_edits_cursor = get_comment_edits(comment, comment_edits_cursor, BATCH_SIZE - results.size)
                results.concat(new_results)

                # If we've finished processing a comment, advance to the next one
                if completed
                  discussion_cursor.last_id = comment.id
                  comment_edits_cursor = CursorValue.new
                end
              else
                comments_completed = true
              end
              break if comments_completed || results.size >= BATCH_SIZE
            end
          end

          # build the serializable cursor from variables
          next_cursor = nil
          unless comments_completed
            cursors = [discussion_cursor]
            cursors.push(comment_edits_cursor) if content_type == :COMMENT
            next_cursor = GitHub::Proto::SecretScanning::Discussions::V1::StreamDiscussionContentResponseCursor.new(
              content_type: content_type,
              cursors: cursors
            )
          end

          GitHub::Proto::SecretScanning::Discussions::V1::StreamDiscussionContentResponse.new(
            contents: results, next_cursor: next_cursor
          )
        end

        sig do
          params(
            req: GitHub::Proto::SecretScanning::Discussions::V1::ListDiscussionsRequest,
            env: T::Hash[String, T.untyped]
            )
          .returns(T.any(GitHub::Proto::SecretScanning::Discussions::V1::ListDiscussionsResponse, Twirp::Error))
        end
        def list_discussions(req, env)
          unless req.repo_id.present?
            return Twirp::Error.invalid_argument("must be non-empty", argument: "repo_id")
          end

          repository = T.cast(::Repositories.domain.by_id(req.repo_id), T.nilable(Repository)) # rubocop:todo GitHub/AvoidCast

          unless repository.present?
            return Twirp::Error.not_found("the repository was not found", argument: "repo_id")
          end

          next_cursor = nil
          last_processed_discussion_number = 0
          if req.cursor.present?
            unpacked_cursor = req.cursor.unpack("Q")
            last_processed_discussion_number = unpacked_cursor[0]
          end

          results = []

          has_discussions = repository.discussions.count > 0
          if has_discussions
            discussion_batch = repository.discussions.select(:id, :number).where("number > ?", last_processed_discussion_number)
            .order(number: :asc).limit(BATCH_SIZE)

            if discussion_batch.any?
              discussion_batch.each do |discussion|
                results.push({
                  discussion_number: discussion.number,
                  discussion_id: discussion.id,
                })
              end

              next_cursor = [discussion_batch.last&.number, "n"].pack("QA")
            end
          end

          GitHub::Proto::SecretScanning::Discussions::V1::ListDiscussionsResponse.new(
            identifiers: results,
            next_cursor: next_cursor
          )
        end

        # private

        sig do
          params(
            request_cursor: T.nilable(GitHub::Proto::SecretScanning::Discussions::V1::StreamDiscussionContentResponseCursor),
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
            discussion: Discussion,
            cursor: CursorValue,
            remaining_batch_size: Integer
          ).returns([T::Array[DiscussionContent], T::Boolean, CursorValue])
        end
        def get_body_edits(discussion, cursor, remaining_batch_size)
          results = []
          last_edit_id = nil
          completed = false

          has_edits = discussion.user_content_edits.count > 0
          if has_edits
            revision = cursor.revision
            # query for the edits
            edit_batch = discussion.user_content_edits.where("id > ?", cursor.last_id)
            .order(id: :asc).limit(remaining_batch_size)

            if edit_batch.any?
              # loop through them and build the response
              edit_batch.each do |edit|
                results.push({
                  content: edit&.diff&.b,
                  type: DiscussionContentType::BODY,
                  id: discussion.id,
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
            # if the body has not been edited, the only copy is on the actual discussion
            results.push({
              content: discussion.body&.b,
              type: DiscussionContentType::BODY,
              id: discussion.id,
              revision: 0
            })
            completed = true
          end

          [results, completed, CursorValue.new(last_id: last_edit_id, revision: revision)]
        end

        sig do
          params(
            comment: DiscussionComment,
            cursor: CursorValue,
            remaining_batch_size: Integer
          ).returns([T::Array[DiscussionContent], T::Boolean, CursorValue])
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
                  type: DiscussionContentType::COMMENT,
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
              type: DiscussionContentType::COMMENT,
              id: comment.id,
              revision: 0
            })
            completed = true
          end

          [results, completed, CursorValue.new(last_id: last_edit_id, revision: revision)]
        end
      end
    end
  end
end
