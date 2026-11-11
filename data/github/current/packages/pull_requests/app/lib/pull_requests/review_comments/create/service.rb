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
            actor: User,
            review: T.nilable(PullRequestReview),
            review_event: T.any(Symbol, String, NilClass),
            parameters: T::Array[T.any(HashWithIndifferentAccess, T::Hash[T.untyped, T.untyped])],
            only_changed_files: T::Boolean,
            destination_base_commit_oid: T.nilable(String),
            destination_head_commit_oid: T.nilable(String),
          ).void
        end
        def initialize(pull_request:, actor:, review:, review_event:, parameters:, only_changed_files:, destination_base_commit_oid: nil, destination_head_commit_oid: nil)
          @pull_request = pull_request
          @actor = actor
          @review = review
          @review_event = T.let(
            Enums::ReviewSubmitAction.deserialize_with_default(review_event, default: Enums::ReviewSubmitAction::CreatePendingComment),
            Enums::ReviewSubmitAction
          )
          @destination_base_commit_oid = T.let(destination_base_commit_oid || pull_request.base_sha, String)
          @destination_head_commit_oid = T.let(destination_head_commit_oid || pull_request.head_sha, String)
          @parameters = T.let(parameters.map(&:with_indifferent_access).map(&:compact), T::Array[ActiveSupport::HashWithIndifferentAccess])
          @only_changed_files = only_changed_files
        end

        # Perform the creation for all the requested Comment/Threads. This is an all-or-nothing approach to creation
        # so if any fail, they all fail.
        sig { returns(T.any(BulkSuccess, Error)) }
        def call
          # Validate related models - these checks apply to the entire batch
          if pull_request_review.pending? == false
            errored(:review, "must be pending")
            return Error.new(errors:)
          elsif pull_request.issue&.locked? && repository.pushable_by?(actor)
            errored(:issue, "is locked")
            return Error.new(errors:)
          elsif submitting_review? && requires_body? && pull_request_review.body.blank? && @parameters.any? { _1[:body].blank? }
            errored(:body, "required when requesting changes")
            return Error.new(errors:)
          end

          pull_request_review.skip_review_callbacks = true

          if submitting_review?
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
            # Loop over all inputs. If the input is an Error, pass it to the errored method. Otherwise skip it.
            inputs.each do
              next unless _1.is_a?(CommentPosition::Errors)
              errored(*_1.to_error_tuple)
            end
            return Error.new(errors:)
          else
            inputs = inputs.filter_map { _1 unless _1.is_a?(CommentPosition::Errors) }
          end

          results = with_named_tags({
            "gh.repo.id": repository.id,
            "gh.pull_request.id": @pull_request.id,
          }) do
            CommentPosition::Positioner::Service.new(
              inputs:,
              repository: head_repository,
              base_commit_oid: @destination_base_commit_oid,
              head_commit_oid: @destination_head_commit_oid,
              position_only: false,
              diffs: pull_request.loaded_diffs,
              only_changed_files: @only_changed_files,
            ).call.values
          end

          # Generate a collection of database models to save in a transaction loop next.
          comments = @parameters.zip(results).map do |params, result|
            case result
            when CommentPosition::Errors
              errored(*result.to_error_tuple)
              next nil
            when nil
              errored(:base, "unknown error occurred")
              next nil
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
              errored_from(pull_request_review_comment)
              next nil
            end

            if pull_request_review_thread.invalid?
              errored_from(pull_request_review_thread)
              next nil
            end

            # Generate the new computed columns to the PullRequestReviewThread model instance
            columns = result.to_database_columns
            # Use this custom setter method to automatically apply the database column size constraints
            columns[:truncated_diff_hunk] = columns.delete(:compressed_diff_hunk)
            # Set the column columns to be saved in the transaction
            pull_request_review_thread.assign_attributes(columns)

            pull_request_review_comment
          end

          if errors.any?
            return Error.new(errors:)
          else
            comments = comments.filter_map { _1 if _1.is_a?(PullRequestReviewComment) }
          end

          begin
            save_successful = ApplicationRecord::Domain::IssuesPullRequests.transaction do
              if pull_request_review.changes_to_save.any?
                pull_request_review.save!
              end

              comments.each do |comment|
                # Save the thread.
                T.must(comment.pull_request_review_thread).save!

                # Save the comment.
                submitting_review? ? comment.submit! : comment.save!
              end

              # After saving all the records, transition the review to the next stage
              if submitting_review?
                # All non-pending revies must be submitted via the trigger method to ensure all side effects are executed.
                unless pull_request_review.trigger(@review_event.serialize)
                  errored(:review, pull_request_review.halted_because) if pull_request_review.halted?
                  raise ActiveRecord::Rollback
                end
              end
              true
            end
            return Error.new(errors:) unless save_successful
          rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique => exception
            Failbot.report(exception)
            errored(:base, exception.message.delete_prefix("Validation failed: "))
            return Error.new(errors:)
          rescue ActiveRecord::QueryCanceled, *Resiliency::Response::UnavailableExceptions => exception
            Failbot.report(exception)
            errored(:base, "An internal error occurred, please try again.")
            return Error.new(errors:)
          end

          threads = comments.zip(inputs).map do |comment, input|
            thread = T.must(comment.pull_request_review_thread)

            GitHub.dogstats.increment("pull_request.comment.created", tags: ["outside_the_diff:#{thread.outside_diff?}"])

            begin
              AfterCreatePullRequestReviewCommentOrchestration.create!(
                pull_request:,
                repository:,
                pull_request_review_comment: comment,
                actor:,
                review_submitted: submitting_review?,
                new_reviewer_was_added: pull_request_review.new_reviewer_added?,
                importing: pull_request_review.importing?,
                position_is_used: input.is_a?(CommentPosition::Positioner::Inputs::DiffRelative),
              ).execute
            rescue => err
              # We've already persisted everything, if this fails, let's capture it for now. Worst case some telemetry
              # may not be emitted, but we're too far along to rollback and we don't want to make the DB transaction any bigger.
              Failbot.report(err)
            end

            thread
          end

          begin
            if submitting_review?
              AfterSubmitPullRequestReviewOrchestration.create!(
                pull_request:,
                repository:,
                pull_request_review: pull_request_review,
                new_reviewer_was_added: pull_request_review.new_reviewer_added?,
                importing: pull_request_review.importing?,
              ).execute
            end
          rescue => err
            # We've already persisted everything, if this fails, let's capture it for now. Worst case some telemetry
            # may not be emitted, but we're too far along to rollback and we don't want to make the DB transaction any bigger.
            Failbot.report(err)
          end

          BulkSuccess.new(comments: comments, threads: threads)
        end

        private

        sig { params(key: T.nilable(Symbol), message: T.nilable(String)).returns(ActiveModel::Errors) }
        def errored(key, message = nil)
          errors.add(key, message || "unknown")
          errors
        end

        sig { params(model: T.untyped).returns(ActiveModel::Errors) }
        def errored_from(model)
          model.errors.each { errors.add(_1.attribute, _1.message) }
          errors
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
        def repository = T.must(pull_request.repository)

        sig { returns(User) }
        attr_reader :actor
        alias user actor

        sig { returns(T::Boolean) }
        def submitting_review? = @review_event != Enums::ReviewSubmitAction::CreatePendingComment

        sig { returns(Repository) }
        memoize def head_repository = T.must(pull_request.head_repository || pull_request.repository)

        sig { type_parameters(:U).params(tags: T::Hash[T.untyped, T.untyped], block: T.proc.returns(T.type_parameter(:U))).returns(T.type_parameter(:U)) }
        def with_named_tags(tags, &block)
          GitHub.logger.with_named_tags(tags, &block)
        end

        sig { returns(T::Boolean) }
        def requires_body?
          case @review_event
          when Enums::ReviewSubmitAction::RequestChanges, Enums::ReviewSubmitAction::Comment
            true
          else
            false
          end
        end
      end
    end
  end
end
