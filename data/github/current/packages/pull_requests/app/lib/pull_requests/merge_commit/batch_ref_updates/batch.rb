# typed: strict
# frozen_string_literal: true

module PullRequests
  module MergeCommit
    module BatchRefUpdates
      # Object to collect various ref updates and serialize them in to data structures suitable for invoking
      # batch_ref_updates.
      class Batch
        sig { void }
        def initialize
          @collection = T.let([], T::Array[[Integer, String, String]])
        end

        sig { returns(T::Boolean) }
        def empty?
          @collection.empty?
        end

        # Convert the collection of updates in to the correct data structure for the ICommand#update_refs call.
        sig { returns(T::Array[ICommand::RefUpdate]) }
        def to_ref_updates
          @collection.map do |(pull_request_id, name, sha)|
            ICommand::RefUpdate.new(pull_request_id:, name:, sha:)
          end
        end

        sig { params(request: Request, commit: Entity::Commits::Created).void }
        def add_merge_ref_update(request:, commit:)
          append(request:, refname: request.merge_refname, sha: commit.sha)
        end

        sig { params(request: Request).void }
        def add_merge_ref_deletion(request:)
          append(request:, refname: request.merge_refname, sha: GitHub::NULL_OID)
        end

        sig { params(request: Request, commit: Entity::Commits::Created).void }
        def add_rebase_ref_update(request:, commit:)
          append(request:, refname: request.rebase_refname, sha: commit.sha)
        end

        sig { params(request: Request).void }
        def add_rebase_ref_deletion(request:)
          append(request:, refname: request.rebase_refname, sha: GitHub::NULL_OID)
        end

        private

        sig { params(request: IRequest, refname: String, sha: String).void }
        def append(request:, refname:, sha:)
          @collection << [request.pull_request_id, refname, sha]
        end
      end
    end
  end
end
