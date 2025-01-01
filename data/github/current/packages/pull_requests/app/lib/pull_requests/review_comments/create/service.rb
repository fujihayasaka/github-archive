# typed: strict
# frozen_string_literal: true

module PullRequests
  module ReviewComments
    module Create
      class Service
        include GitHub::Memoizer
        include ActiveModel::Validations

        sig do
          params(
            pull_request: PullRequest,
            repository: Repository,
            actor: User,
            review: T.nilable(PullRequestReview),
            submit_review: T::Boolean,
            parameters: T::Array[T.any(HashWithIndifferentAccess, T::Hash[T.untyped, T.untyped])],
            destination_base_commit_oid: T.nilable(String),
            destination_head_commit_oid: T.nilable(String),
          ).void
        end
        def initialize(pull_request:, repository:, actor:, review:, submit_review:, parameters:, destination_base_commit_oid: nil, destination_head_commit_oid: nil)
          @pull_request = pull_request
          @repository = repository
          @actor = actor
          @review = review
          @destination_base_commit_oid = T.let(destination_base_commit_oid || pull_request.base_sha, String)
          @destination_head_commit_oid = T.let(destination_head_commit_oid || pull_request.head_sha, String)
          @submit = submit_review
          @parameters = T.let(parameters.map(&:with_indifferent_access).map(&:compact), T::Array[ActiveSupport::HashWithIndifferentAccess])
        end

        # Perform the creation for all the requested Comment/Threads. This is an all-or-nothing approach to creation
        # so if any fail, they all fail.
        sig { returns(T::Array[T.any(Success, Error)]) }
        def call
          # Validate related models - these checks apply to the entire batch
          if pull_request_review.pending? == false
            return @parameters.map { errored(:review, "must be pending") }
          elsif pull_request.issue&.locked? && repository.pushable_by?(actor)
            return @parameters.map { errored(:issue, "is locked") }
          elsif @submit && pull_request_review.body.blank? && @parameters.any? { _1[:body].blank? }
            return @parameters.map { errored(:body, "required when requesting changes") }
          end

          pull_request_review.skip_review_callbacks = true

          if @submit
            pull_request_review.submitted_at = Time.zone.now
          end

          inputs = @parameters.map do |params|
            base_commit_oid = params[:source_base_commit_oid] || destination_base_commit_oid
            head_commit_oid = params[:source_head_commit_oid] || destination_head_commit_oid

            if params.key?(:positioning)
              CommentPosition::Positioner::Inputs::Positioning.parse(
                positioning: params[:positioning],
                base_commit_oid:,
                head_commit_oid:
              )
            elsif params[:position] != nil && params[:line].nil?
              CommentPosition::Positioner::Inputs::DiffRelative.parse(
                base_commit_oid:,
                head_commit_oid:,
                path: params[:path],
                position: params[:position],
              )
            else
              CommentPosition::Positioner::Inputs::Blobs.parse(
                base_commit_oid:,
                head_commit_oid:,
                path: params[:path],
                line: params[:line],
                side: params[:side],
                start_line: params[:start_line],
                start_side: params[:start_side],
              )
            end
          end

          # If any of the inputs are invalid, mark the entire batch as invalid and halt execution. This reduces
          # unnecessary RPC calls.
          if inputs.any? { _1.is_a?(CommentPosition::Errors) }
            return inputs.map do
              if _1.is_a?(CommentPosition::Errors)
                errored(*_1.to_error_tuple)
              else
                errored(:base, "batch processing failed due to other errors")
              end
            end
          else
            inputs = inputs.filter_map { _1 unless _1.is_a?(CommentPosition::Errors) }
          end

          results = CommentPosition::Positioner::Service.new(
            inputs:,
            repository: head_repository,
            base_commit_oid: @destination_base_commit_oid,
            head_commit_oid: @destination_head_commit_oid,
            position_only: false,
            diffs: pull_request.loaded_diffs
          ).call.values

          # Generate a collection of database models to save in a transaction loop next.
          comments = @parameters.zip(results).map do |params, result|
            case result
            when CommentPosition::Errors
              next errored(*result.to_error_tuple)
            when nil
              next errored(:base, "unknown error occurred")
            end

            pull_request_review_thread = pull_request_review.review_threads.build(
              skip_create_callbacks: true,
              repository_id: repository.id,
              pull_request:,
            )

            pull_request_review_comment = pull_request_review.review_comments.build(
              skip_create_callbacks: true,
              body: params[:body],
              user:, repository:, pull_request:, pull_request_review_thread:,
            )

            if pull_request_review_comment.invalid?
              next errored_from(pull_request_review_comment)
            end

            if pull_request_review_thread.invalid?
              next errored_from(pull_request_review_comment)
            end

            # Generate the new computed columns to the PullRequestReviewThread model instance
            columns = result.to_database_columns
            # Use this custom setter method to automatically apply the database column size constraints
            columns[:truncated_diff_hunk] = columns.delete(:compressed_diff_hunk)
            # Set the column columns to be saved in the transaction
            pull_request_review_thread.assign_attributes(columns)

            pull_request_review_comment
          end

          if comments.any? { _1.is_a?(Create::Error) }
            return comments.map do
              if _1.is_a?(Create::Error)
                _1
              else
                errored(:base, "batch processing failed due to other errors")
              end
            end
          else
            comments = comments.filter_map { _1 if _1.is_a?(PullRequestReviewComment) }
          end

          begin
            ApplicationRecord::Domain::IssuesPullRequests.transaction do
              comments.each do |comment|
                # Save the thread.
                T.must(comment.pull_request_review_thread).save!

                # Save the comment.
                @submit ? comment.submit! : comment.save!
              end

              # After saving all the records, save the review.
              if @submit
                pull_request_review.comment!
              elsif pull_request_review.changes_to_save.any?
                pull_request_review.save!
              end
            end
          rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique, ActiveRecord::QueryCanceled,
                 *Resiliency::Response::UnavailableExceptions => exception
            Failbot.report(exception)
            return Array.new(@parameters.length, errored(:base, "failed to save"))
          end

          comments.zip(inputs).map do |comment, input|
            thread = T.must(comment.pull_request_review_thread)

            begin
              AfterCreatePullRequestReviewCommentOrchestration.create!(
                pull_request:,
                repository:,
                pull_request_review_comment: comment,
                review_submitted: @submit,
                new_reviewer_was_added: pull_request_review.new_reviewer_added?,
                importing: pull_request_review.importing?,
                position_is_used: input.is_a?(CommentPosition::Positioner::Inputs::DiffRelative),
              ).execute
            rescue => err
              # We've already persisted everything, if this fails, let's capture it for now. Worst case some telemetry
              # may not be emitted, but we're too far along to rollback and we don't want to make the DB transaction any bigger.
              Failbot.report(err)
            end

            Success.new(comment:, thread:)
          end
        end

        private

        sig { params(key: T.nilable(Symbol), message: T.nilable(String)).returns(Create::Error) }
        def errored(key = nil, message = nil)
          errors.add(key, message || "unknown") if key
          Create::Error.new(errors:)
        end

        sig { params(model: T.untyped).returns(Create::Error) }
        def errored_from(model)
          model.errors.each { errors.add(_1.attribute, _1.message) }
          Create::Error.new(errors:)
        end

        sig { returns(T::Array[GitHub::Diff]) }
        def diffs = @pull_request.loaded_diffs

        sig { returns(PullRequestReview) }
        memoize def pull_request_review
          @review || @pull_request.pending_review_for(user: @actor, head_sha: @destination_head_commit_oid)
        end

        sig { returns(String) }
        attr_reader :destination_base_commit_oid, :destination_head_commit_oid

        sig { returns(PullRequest) }
        attr_reader :pull_request

        sig { returns(Repository) }
        attr_reader :repository

        sig { returns(User) }
        attr_reader :actor
        alias user actor

        sig { returns(Repository) }
        def head_repository = pull_request.head_repository || repository
      end
    end
  end
end
