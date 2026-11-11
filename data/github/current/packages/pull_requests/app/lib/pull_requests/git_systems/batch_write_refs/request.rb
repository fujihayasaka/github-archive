# typed: strict
# frozen_string_literal: true

module PullRequests
  module GitSystems
    module BatchWriteRefs
      class Request < T::Struct
        prop :outcome, Outcome, default: Outcome::Pending.new
        const :ref_name, String
        const :before_oid, T.nilable(String)
        const :after_oid, String

        sig { returns(T::Boolean) }
        def pending?
          outcome.is_a?(Outcome::Pending)
        end

        # Determine if ref is considered "public" where branch rules would apply.
        sig { returns(T::Boolean) }
        def internal_refspec?
          GitSystems::RefSpecs::INTERNAL.any? { _1 =~ ref_name }
        end

        sig { returns(T::Boolean) }
        def public_refspec?
          !internal_refspec?
        end

        # Generate a ref update object used in branch rules.
        sig { params(repository: Repository).returns(T.nilable(Git::Ref::Update)) }
        def to_git_ref_update(repository:)
          return unless before_oid = self.before_oid

          Git::Ref::Update.new(
            repository:,
            refname: ref_name,
            before_oid:,
            after_oid:,
            wiki: false
          )
        end

        # Generate a tuple of [refname, before, after] for use with write_batch_refs.
        sig { returns([String, T.nilable(String), String]) }
        def to_batch_write_refs_tuple
          [ref_name, before_oid, after_oid]
        end

        # Mark the request as having been successfully updated.
        sig { void }
        def mark_successful!
          self.outcome = Outcome::Success.new
        end

        # Mark the request as failing to update.
        sig { params(message: String, reason: FailureReason, exception: T.nilable(Exception)).void }
        def mark_failed!(message:, reason:, exception: nil)
          self.outcome = Outcome::Failed.new(message:, exception:, reason:)
        end
      end
    end
  end
end
