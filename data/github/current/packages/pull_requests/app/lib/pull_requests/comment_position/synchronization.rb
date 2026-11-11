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

      private

      # TODO: This could potentially be replaced with a direct call to rpc.rev_list instead. See if there are diff reuse
      # options if the diff is already loaded.
      sig { returns(T::Array[String]) }
      memoize def current_rev_list = @pull_request.changed_commit_oids

      sig { returns(T.nilable(String)) }
      memoize def current_merge_base = @pull_request.merge_base
    end
  end
end
