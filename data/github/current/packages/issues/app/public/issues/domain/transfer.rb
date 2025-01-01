# rubocop:disable Metrics/MethodLength
# typed: strict
# frozen_string_literal: true

module Issues
  class Domain
    class Transfer < GH::Domain::Base
      # Transfers an issue to a new repository. Returns a result object with the new issue if successful.
      sig { params(issue: IIssue, new_repository: Repositories::IRepository, actor: User).returns(GH::Result[IIssue]).checked(:always).on_failure(:raise) }
      def transfer(issue, new_repository, actor)
        old_issue = T.cast(issue, Issue)
        transfer = IssueTransfer.new(old_issue:, old_repository: old_issue.repository, new_repository:, actor:)
        transfer.transfer!
        GH::Result::Ok.new(transfer.new_issue)
      rescue => e
        GH::Result::Error.new(e.message, e)
      end

      # Transfers an issue to a new repository in a background job. Returns a result object with the new issue if successful.
      sig { params(issue: IIssue, new_repository: Repositories::IRepository, actor: User, create_labels_if_missing: T::Boolean).returns(GH::Result[IIssue]).checked(:always).on_failure(:raise) }
      def transfer_in_the_background(issue, new_repository, actor, create_labels_if_missing: false)
        old_issue = T.cast(issue, Issue)
        transfer = IssueTransfer.new(old_issue:, old_repository: old_issue.repository, new_repository:, actor:)
        transfer.async_transfer!(create_labels_if_missing: create_labels_if_missing)
        GH::Result::Ok.new(transfer.new_issue)
      rescue ActiveRecord::RecordInvalid => e
        if e.record.errors.include?(:actor)
          GH::Result::Error::Forbidden.new(e.record.errors.full_messages_for(:actor).first)
        else
          data_errors = e.record.errors
            .to_hash(true)
            .values_at(:old_issue, :old_repository, :new_repository)
            .compact.join(", ")

          GH::Result::Error::Unprocessable.new([], message: data_errors.empty? ? e.message : data_errors)
        end
      rescue => e
        GH::Result::Error.new(e.message, e)
      end
    end
  end
end
