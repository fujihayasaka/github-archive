# frozen_string_literal: true

require "rails_helper"

RSpec.describe "ActiveRecord::RelationExtensions" do
  describe "#delete_all_with_dependents" do
    it "deletes records and their dependent associations without loading into memory" do
      pr = create(:pull_request, :closed)
      job = create(:autofix_suggestion_job, pull_request: pr)
      create(:suggested_fix, :with_suggested_fix_files, autofix_suggestion_job: job)

      # should delete 1 of each record
      expect { PullRequest.all.delete_all_with_dependents }.
        to change(PullRequest, :count).by(-1).
        and change(AutofixSuggestionJob, :count).by(-1).
        and change(SuggestedFix, :count).by(-1).
        and change(SuggestedFixFile, :count).by(-1).
        and change(PullRequestTransition, :count).by(-1).
        and change(UpdatedDependency, :count).by(-1)
    end

    it "does not delete records for associations without dependent options" do
      # Tenant has a `has_many :accounts` association
      # without a dependent option
      create(:tenant) { |tenant| create(:account, tenant: tenant) }

      expect { Tenant.all.delete_all_with_dependents }.
        to change(Tenant, :count).by(-1).
        and not_change(Account, :count)
    end

    it "scopes polymorphic dependent deletes by type column" do
      pending_pr = create(:pending_pull_request)
      pending_pr.message_data = { "commit_message" => "Bump business from 1.3.0 to 1.4.0" }

      pending_pr_update = create(:pending_pull_request_update, id: pending_pr.id)
      pending_pr_update.message_data = { "commit_message" => "Bump storefront from 2.1.0 to 2.2.0" }

      expect { PendingPullRequest.where(id: pending_pr.id).delete_all_with_dependents }.
        to change(ActiveStorage::Attachment, :count).by(-1).
        and change(ActiveStorage::Blob, :count).by(-1)

      expect(ActiveStorage::Attachment.where(record: pending_pr_update)).to exist
      expect(ActiveStorage::Blob.joins(:attachments).where(attachments: { record: pending_pr_update })).to exist
    end

    it "does not delete records outside the scope of the relation" do
      prs = create_list(:pull_request, 2, :closed) do |pr|
        job = create(:autofix_suggestion_job, pull_request: pr)
        create(:suggested_fix, :with_suggested_fix_files, autofix_suggestion_job: job)
      end

      # should only delete records associated with pr1
      expect { PullRequest.where(id: prs[0].id).delete_all_with_dependents }.
        to change(PullRequest, :count).by(-1).
        and change(AutofixSuggestionJob, :count).by(-1).
        and change(PullRequestTransition, :count).by(-1).
        and change(UpdatedDependency, :count).by(-1)

      # should not delete records associated with pr2
      expect(PullRequest.where(id: prs[1].id)).to exist
      expect(AutofixSuggestionJob.where(pull_request_id: prs[1].id)).to exist
      expect(PullRequestTransition.where(pull_request_id: prs[1].id)).to exist
      expect(UpdatedDependency.where(pull_request_id: prs[1].id)).to exist
    end
  end
end
