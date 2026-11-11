# typed: strict
# frozen_string_literal: true

module PullRequests
  module CommentPosition
    class Synchronization
      include GitHub::Memoizer

      sig { params(pull_request: PullRequest, repository: Repository).void }
      def initialize(pull_request:, repository:)
        @pull_request = pull_request
        @repository = repository
        @threads = T.let(nil, T.nilable(T::Array[PullRequestReviewThread]))
        @errored = T.let(false, T::Boolean)
      end

      sig { returns(T::Boolean) }
      def enabled? = FeatureFlag.vexi.enabled?(:prx_comment_outside_the_diff, @repository, @repository.owner, default: false)

      sig do
        params(
          from: [String, String],
          to: [String, String],
          threads: T::Array[PullRequestReviewThread],
        ).void
      end
      def reposition!(from:, to:, threads:)
        return unless repository = @pull_request.head_repository

        @threads = threads

        base_commit_oid, head_commit_oid = from

        inputs = Positioner::Loaders::ThreadColumns.new(
          pull_request: @pull_request,
          threads:,
          base_commit_oid:,
          head_commit_oid:,
        ).to_inputs

        base_commit_oid, head_commit_oid = to

        # Mark automated review comments suggestions as outdated when head commit changes
        if FeatureFlag.vexi.enabled?(:automated_review_comment_outdated, @repository, default: false)
          mark_outdated_suggestions!(new_head_commit_oid: head_commit_oid)
        end

        result = Positioner::Service.new(
          repository:,
          inputs:,
          base_commit_oid:,
          head_commit_oid:,
          diffs: @pull_request.loaded_diffs,
        ).call

        result.each do |input, value|
          case input
          when Positioner::Inputs::ThreadColumns
            raise "TODO: unable to resolve thread" unless thread = threads.find { _1.id == input.identifier }

            case value
            when Positioner::Result
              # Never override the immutable columns as they are immutable!
              without = [:immutable_columns]

              # TODO: This contains existing behavior around updating blob columns. I'm not sure why we do this, other than
              # for some sort of caching reasons around blob based artifacts? Tests start failing without this.

              # Never reposition if the current position is still in the PR's list of commits.
              #
              # See: packages/pull_requests/app/models/pull_request_review_thread.rb:1112
              commit_exists_in_history = current_rev_list.include?(thread.blob_commit_oid)

              # If targeting left blob, it's ok if we reference the merge_base, even though it isn't part of the changes.
              #
              # See: packages/pull_requests/app/models/pull_request_review_thread.rb:1117
              left_blob_commit_oid_matches_merge_base = thread.left_blob? && current_merge_base == thread.blob_commit_oid

              if commit_exists_in_history || left_blob_commit_oid_matches_merge_base
                # Skip persisting any blob specific column values.
                without << :blob_columns
              end

              # Generate the database columns as a Hash.
              attributes = value.to_database_columns(without:)

              # Don't override the original positioning if we have one.
              if thread.original_positioning
                attributes.delete(:original_positioning)
              end

              thread.assign_attributes(attributes)
            when CommentPosition::Errors
              # TODO: What should we do here? Nothing?
            end
          else
            raise "unexpected type"
          end
        end
      rescue => exception
        @errored = true

        Failbot.report(exception, {
          from:,
          to:,
          repository_id: @repository.id,
          pull_request_id: @pull_request.id
        })
      end

      # Borrowed from: packages/pull_requests/app/models/pull_request_review_thread.rb:1151
      sig { void }
      def save_threads!
        # In the scenario of a previous failure, don't attempt to save the thread data.
        return if @errored

        @threads&.each do |thread|
          next unless thread.has_changes_to_save?

          position = thread.position

          unless position.nil? || position.is_a?(Integer)
            next # must be nil or an Integer
          end

          # TODO: This is now validated by our end to end positioning.
          unless GitRPC::Util.valid_full_oid?(thread.commit_id)
            next # must be a 40 character SHA
          end

          # TODO: Since we're doing validate false there's no reason we can't do a big upsert. Callbacks I guess?
          PullRequestReviewThread.no_touching do
            thread.updated_at = thread.send(:current_time_from_proper_timezone)
            thread.save(validate: false)
          end
        end
      end

      sig { params(new_head_commit_oid: String).void }
      def mark_outdated_suggestions!(new_head_commit_oid:)
        start = Time.now
        log_context = {
          "gh.pull_request.id": @pull_request.id,
          "gh.repository.id": @repository.id,
          "gh.pull_request.new_head_commit_oid": new_head_commit_oid,
        }

        GitHub.logger.info("Syncing outdated suggestions", **log_context)

        # Find all AutomatedReviewComments for this PR that have a suggestion
        # whose commit SHA does not match the new head commit.
        candidates = @pull_request.automated_review_comments
          .suggestion_state_present
          .where.not(suggestion: nil)
          .where.not("suggestion ->> '$.commit_sha' = ?", new_head_commit_oid)

        GitHub.logger.info("Found candidate suggestions to sync", **log_context, "gh.candidate_count": candidates.count)
        GitHub.dogstats.distribution("pull_request.suggestions.sync.mark_outdated.candidates", candidates.length, tags: ["batch_size:#{batch_size_bucket(candidates.length)}"])

        outdated_comments = T.let([], T::Array[AutomatedReviewComment])

        candidates.each do |comment|
          comment.check_diff_appliable(new_head_commit_oid) => { status:, adjusted_diff_files: }

          result_tag = case status
          when AutomatedReviewComment::DiffAppliableStatus::Appliable
            # If the suggestion is still appliable, but the diff has changed, we can attempt to adjust the suggestion
            # to the new diff.
            if adjusted_diff_files.present? && comment.suggestion.present?
              original_files = comment.suggestion.files

              # Partially applied suggestions are no longer valid, as the adjusted diff may no longer represent the
              # full intent of the suggestion. Outdate them.
              if suggestion_partially_applied?(original_files, adjusted_diff_files)
                # The adjusted diff has fewer files or fewer hunks in a file,
                # meaning part of the suggestion was already applied. Outdate it.
                outdated_comments << comment
                "partially_applied"
              else
                comment.update!(suggestion: {
                  commit_sha: new_head_commit_oid,
                  files: adjusted_diff_files
                })
                "adjusted"
              end
            else
              "appliable"
            end
          when AutomatedReviewComment::DiffAppliableStatus::AlreadyApplied
            comment.suggestion_state_applied!
            resolve_thread_for_applied_comment!(comment)
            "already_applied"
          else
            outdated_comments << comment
            "outdated"
          end

          GitHub.logger.info(
            "Sync suggestion result",
            **log_context,
            "gh.automated_review_comment.id": comment.id,
            "gh.result": result_tag,
          )
          GitHub.dogstats.increment("pull_request.suggestions.sync.mark_outdated.result", tags: ["result:#{result_tag}"])
        end

        if outdated_comments.any?
          outdate_comments!(outdated_comments)
        end

        GitHub.logger.info(
          "Sync outdated suggestions complete",
          **log_context,
          "gh.candidate_count": candidates.length,
          "gh.outdated_count": outdated_comments.length,
        )
        GitHub.dogstats.distribution_timing_since("pull_request.suggestions.sync.mark_outdated.duration", start, tags: ["batch_size:#{batch_size_bucket(candidates.count)}"])
      end

      private

      sig { params(count: Integer).returns(String) }
      def batch_size_bucket(count)
        case count
        when 0 then "0"
        when 1 then "1"
        when 2..5 then "2-5"
        when 6..10 then "6-10"
        when 11..20 then "11-20"
        else "20+"
        end
      end

      # Checks whether the adjusted diff represents a partial application of the
      # original suggestion. This is true when:
      # - The adjusted diff has a different number of files (some file's changes were fully applied)
      # - Any file in the adjusted diff has fewer hunks (some hunks were applied)
      #
      # Notes:
      #
      # A 3-way merge can split a single hunk into multiple hunks when new
      # lines are inserted in the middle of the original range. This means
      # adjusted_hunks > original_hunks is possible without any partial application.
      # We only check for fewer hunks here, so the rare case where a hunk is applied
      # AND another hunk is split (cancelling out the count) will not be detected.
      #
      # Additionally, in a case where a change causes two hunks to merge into a single hunk
      # we could have adjusted_hunks < original_hunks even without any application.
      # We don't check for this case and err on the side of not marking as partially applied.
      sig do
        params(
          original_files: T::Array[::ReviewComments::Suggestion::File],
          adjusted_files: T::Array[::ReviewComments::Suggestion::File],
        ).returns(T::Boolean)
      end
      def suggestion_partially_applied?(original_files, adjusted_files)
        # Fewer files means at least one file was fully applied, so the suggestion is partially applied.
        # More files should not happen, but we should outdate if it does
        return true if adjusted_files.length != original_files.length

        adjusted_by_path = T.let(adjusted_files.index_by(&:path), T::Hash[String, ::ReviewComments::Suggestion::File])
        original_files.any? do |original_file|
          adjusted_file = adjusted_by_path[original_file.path]
          next true if adjusted_file.nil? # file was removed entirely, already caught by length check

          # Hunk splits are fine, but if we have fewer hunks something was applied or two hunks were merged.i
          # Since we can't easily check which it is, we err on the side of marking as partially applied.
          count_hunks(adjusted_file.diff_content) < count_hunks(original_file.diff_content)
        end
      end

      sig { params(diff_content: String).returns(Integer) }
      def count_hunks(diff_content)
        diff_content.scan(/^@@\s/).length
      end

      # TODO: This could potentially be replaced with a direct call to rpc.rev_list instead. See if there are diff reuse
      # options if the diff is already loaded.
      sig { returns(T::Array[String]) }
      memoize def current_rev_list = @pull_request.changed_commit_oids

      sig { returns(T.nilable(String)) }
      memoize def current_merge_base = @pull_request.merge_base

      sig { params(comment: AutomatedReviewComment).void }
      def resolve_thread_for_applied_comment!(comment)
        thread = comment.pull_request_review_comment&.pull_request_review_thread
        return unless thread
        return if thread.resolved?

        resolver = ::Apps::Privileged.integration(:copilot_pull_request_reviewer)&.bot
        return unless resolver

        thread.resolve(resolver: resolver)
      rescue PullRequestReviewThread::ResolveReviewThreadError
        # Thread may not be a conversation or is otherwise not resolvable; skip.
      end

      sig { params(outdated_comments: T::Array[AutomatedReviewComment]).void }
      def outdate_comments!(outdated_comments)
        AutomatedReviewComment.where(id: outdated_comments.map(&:id)).update_all(suggestion_state: :suggestion_state_outdated)

        review_comment_ids = outdated_comments
          .select(&:outdated_suggestion_outdates_thread?)
          .map(&:pull_request_review_comment_id)
          .compact
        return if review_comment_ids.empty?

        threads = PullRequestReviewThread
          .joins(:review_comments)
          .where(pull_request_review_comments: { id: review_comment_ids })
          .where(outdated: false)
          .distinct
        PullRequestReviewThread.transaction do
          threads.each do |thread|
            thread.update!(outdated: true)
          end
        end
      end
    end
  end
end
