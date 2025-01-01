# typed: true
# frozen_string_literal: true

module Codespaces
  # This command is called when a user's repository access is changed (GlobalEvents::User::REPOSITORY_ACCESS_CHANGED)

  # For this event, we need to:
  #   1. find any codespaces for this user and repository
  #   2. send them to ProcessSystemEventJob
  #   3. send them to CleanUpStaleGpgAuthorizationJob
  class FindAffectedCodespacesByRepositoryAccessChange < Command
    attr_reader :deletion_reason

    # Perform the job after the waiting period to allow for codespaces which
    # were inaccessible to become accessible again.
    STALE_GPG_AUTHORIZATION_CLEAN_UP_WAITING_PERIOD = 7.days

    def initialize(user:, repository_ids:, deletion_reason:)
      @user = user
      @repository_ids = repository_ids
      @deletion_reason = deletion_reason
    end

    def perform
      org_ids = Repository.where(id: @repository_ids).pluck(:organization_id).compact

      Organization.where(id: org_ids).each do |org|
        has_org_access = org.member?(@user) || org.user_is_outside_collaborator?(@user)
        unless has_org_access
          CodespacesRemoveOrgMemberAccessJob.perform_later(org, @user)
        end
      end

      codespaces = Codespace.where(owner: @user, repository: @repository_ids)
      codespaces.in_batches do |codespace_batch|
        CodespacesProcessSystemEventJob.perform_later(codespaces: codespace_batch.to_a, deletion_reason: deletion_reason)
      end

      authorizations = Codespaces::TrustedRepositoryAuthorization.where(user: @user, repository: @repository_ids)

      # find_each uses find_in_batches under the hood
      authorizations.find_each do |authorization|
        repository = authorization.repository
        if repository.nil? # repository deletion is final thus we can clean up immediately
          Codespaces::CleanUpStaleGpgAuthorizationJob.perform_later(gpg_authorization: authorization)
        elsif !repository.pushable_by?(authorization.user)
          Codespaces::CleanUpStaleGpgAuthorizationJob.perform_after_waiting_period(waiting_period: STALE_GPG_AUTHORIZATION_CLEAN_UP_WAITING_PERIOD, gpg_authorization: authorization)
        end
      end
    end
  end
end
