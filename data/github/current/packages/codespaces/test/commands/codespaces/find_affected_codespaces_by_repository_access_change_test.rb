# typed: true
# frozen_string_literal: true

require "test_helper"

class Codespaces::FindAffectedCodespacesByRepositoryAccessChangeTest < GitHub::TestCase
  fixtures do
    @organization = create(:organization)
    @repository = create(:repository, owner: @organization)
    @codespace = create(:codespace, repository: @repository, billable_owner: @organization)
    @user = @codespace.owner
  end

  context "#call" do
    test "calls to process system event job" do
      expected = Codespace.where(owner: @user, repository: [@repository.id])
      expected.in_batches do |codespace_batch|
        CodespacesProcessSystemEventJob.expects(:perform_later).with(codespaces: codespace_batch, deletion_reason: Codespace.deletion_reasons[:lost_repo_access])
      end
      Codespaces::CleanUpStaleGpgAuthorizationJob.expects(:perform_later).never
      Codespaces::FindAffectedCodespacesByRepositoryAccessChange.call(user: @user, repository_ids: [@repository.id], deletion_reason: Codespace.deletion_reasons[:lost_repo_access])
    end

    test "calls to clean up gpg auths when repo destroyed" do
      repository_id = @repository.id
      expected = Codespace.where(owner: @user, repository: [repository_id])
      authorization = create(:codespace_trusted_repository_authorization, user: @user, repository: @repository)

      expected.in_batches do |codespace_batch|
        CodespacesProcessSystemEventJob.expects(:perform_later).with(codespaces: codespace_batch, deletion_reason: Codespace.deletion_reasons[:lost_repo_access])
      end
      Codespaces::CleanUpStaleGpgAuthorizationJob.expects(:perform_later).once.with(gpg_authorization: authorization)
      Codespaces::CleanUpStaleGpgAuthorizationJob.expects(:perform_after_waiting_period).never

      @repository.destroy!
      Codespaces::FindAffectedCodespacesByRepositoryAccessChange.call(user: @user, repository_ids: [repository_id], deletion_reason: Codespace.deletion_reasons[:lost_repo_access])
    end

    test "calls to clean up gpg auths when repo not pushable" do
      another_repository = create(:repository)
      repository_ids = [@repository.id, another_repository.id]
      expected = Codespace.where(owner: @user, repository: repository_ids)
      authorization = create(:codespace_trusted_repository_authorization, user: @user, repository: another_repository)

      expected.in_batches do |codespace_batch|
        CodespacesProcessSystemEventJob.expects(:perform_later).with(codespaces: codespace_batch, deletion_reason: Codespace.deletion_reasons[:lost_repo_access])
      end

      Codespaces::CleanUpStaleGpgAuthorizationJob.expects(:perform_later).never

      waiting_period = Codespaces::FindAffectedCodespacesByRepositoryAccessChange::STALE_GPG_AUTHORIZATION_CLEAN_UP_WAITING_PERIOD
      Codespaces::CleanUpStaleGpgAuthorizationJob.expects(:perform_after_waiting_period).once.with(waiting_period: waiting_period, gpg_authorization: authorization)

      Codespaces::FindAffectedCodespacesByRepositoryAccessChange.call(user: @user, repository_ids: repository_ids, deletion_reason: Codespace.deletion_reasons[:lost_repo_access])
    end

    test "enqueues a job only if org access is lost" do
      org_2 = create(:organization)
      repo_2 = create(:repository, owner: org_2)

      CodespacesRemoveOrgMemberAccessJob.expects(:perform_later).with(@organization, @user).never
      CodespacesRemoveOrgMemberAccessJob.expects(:perform_later).with(org_2, @user)

      Codespaces::FindAffectedCodespacesByRepositoryAccessChange.call(user: @user, repository_ids: [@repository.id, repo_2.id], deletion_reason: Codespace.deletion_reasons[:lost_repo_access])
    end
  end
end unless GitHub.enterprise?
