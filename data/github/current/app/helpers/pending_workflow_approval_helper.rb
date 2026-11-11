# typed: true
# frozen_string_literal: true

module PendingWorkflowApprovalHelper
  extend T::Helpers

  # Public: Determines if all workflow runs in the collection are expired.
  #
  # workflows_pending_approval - Array of CheckSuite objects
  #
  # Returns Boolean.
  sig { params(workflows_pending_approval: T::Array[CheckSuite]).returns(T::Boolean) }
  def all_expired?(workflows_pending_approval)
    workflows_pending_approval.all?(&:expired_workflow_run?)
  end

  # Public: Determines if any workflow runs in the collection are expired.
  #
  # workflows_pending_approval - Array of CheckSuite objects
  #
  # Returns Boolean.
  sig { params(workflows_pending_approval: T::Array[CheckSuite]).returns(T::Boolean) }
  def any_expired?(workflows_pending_approval)
    workflows_pending_approval.any?(&:expired_workflow_run?)
  end

  # Public: Determines if a viewer can approve workflow runs.
  #
  # workflows_pending_approval - Array of CheckSuite objects
  # repository - Repository object (can be nil)
  # viewer - User object (can be nil)
  #
  # Returns Boolean.
  sig do
    params(
      workflows_pending_approval: T::Array[CheckSuite],
      repository: T.nilable(Repository),
      viewer: T.nilable(User)
    ).returns(T::Boolean)
  end
  def viewer_can_approve?(workflows_pending_approval, repository, viewer)
    !all_expired?(workflows_pending_approval) && !!repository&.writable_by?(viewer)
  end

  # Public: Returns the approval required message based on repository privacy.
  #
  # repository - Repository object (can be nil)
  #
  # Returns String.
  sig { params(repository: T.nilable(Repository)).returns(String) }
  def approval_message(repository)
    if repository&.private?
      "Workflows will not run until approved by a user with write permissions."
    else
      "This workflow requires approval from a maintainer."
    end
  end

  # Public: Returns the help link based on repository privacy.
  #
  # repository - Repository object (can be nil)
  #
  # Returns String.
  sig { params(repository: T.nilable(Repository)).returns(String) }
  def approval_help_link(repository)
    if repository&.private?
      "#{GitHub.help_url}/actions/managing-workflow-runs/approving-workflow-runs-from-private-forks"
    else
      "#{GitHub.help_url}/actions/managing-workflow-runs/approving-workflow-runs-from-public-forks"
    end
  end
end
