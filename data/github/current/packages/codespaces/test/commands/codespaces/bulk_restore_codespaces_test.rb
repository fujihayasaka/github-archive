# typed: true
# frozen_string_literal: true

require "test_helper"

module Codespaces
  class BulkRestoreCodespacesTest < GitHub::TestCase

    setup do
      FakeVSOServer.reset!
    end

    fixtures do
      @org = create(:codespaces_organization, plan: "business")
      @org_repo = create(:repository, owner: @org)

      @user = create(:user)
      @user_repo = create(:repository, owner: @user)
    end

    context "bulk restore codespaces billable to an org" do
      test "restores all deleted codespaces", skip_enterprise: true do
        perform_enqueued_jobs(only: CodespacesRestoreJob) do
          # Create a bunch of (deleted) codespaces billable to the org
          10.times do
            member = create(:user)
            @org.add_member(member)
            create(:codespace, :deprovisioned, owner: member, repository: @org_repo, deleted_at: Time.now)
          end

          deleted_codespaces = Codespace.deleted.where(billable_owner: @org.id)
          FakeVSOServer.environments = deleted_codespaces.map { |codespace| build_vso_environment_payload(codespace) }

          assert_equal 10, deleted_codespaces.count

          Codespaces::BulkRestoreCodespaces.call(user_id: @org.id)

          deleted_codespaces.each do |codespace|
            assert_performed_with(job: CodespacesRestoreJob, args: [{ codespace: codespace }])
          end

          assert_performed_jobs 10, only: CodespacesRestoreJob

          deleted_codespaces.each(&:reload)
          assert_equal 10, Codespace.where(billable_owner: @org.id).count
        end
      end

      test "restores all deleted codespaces with deletion reason", skip_enterprise: true do
        GitHub.flipper[:codespaces_bulk_restore_deletion_reason].enable

        perform_enqueued_jobs(only: CodespacesRestoreJob) do
          # Create a bunch of (deleted) codespaces billable to the org
          2.times do
            member = create(:user)
            @org.add_member(member)
            create(
              :codespace,
              :deprovisioned,
              owner: member,
              repository: @org_repo,
              deleted_at: Time.now,
              deletion_reason: Codespace.deletion_reasons[:stafftools_requested]
            )
          end

          5.times do
            member = create(:user)
            @org.add_member(member)
            create(
              :codespace,
              :deprovisioned,
              owner: member,
              repository: @org_repo,
              deleted_at: Time.now,
              deletion_reason: Codespace.deletion_reasons[:user_requested]
            )
          end

          5.times do
            member = create(:user)
            @org.add_member(member)
            create(
              :codespace,
              :deprovisioned,
              owner: member,
              repository: @org_repo,
              deleted_at: Time.now,
              deletion_reason: Codespace.deletion_reasons[:bulk_dependent_deletion]
            )
          end

          deleted_codespaces_to_restore = Codespace.deleted.where(billable_owner: @org.id, deletion_reason: [Codespace.deletion_reasons[:bulk_dependent_deletion], Codespace.deletion_reasons[:user_requested]])
          stafftools_deleted_codespaces = Codespace.deleted.where(billable_owner: @org.id, deletion_reason: Codespace.deletion_reasons[:stafftools_requested])
          FakeVSOServer.environments = deleted_codespaces_to_restore.map { |codespace| build_vso_environment_payload(codespace) }

          assert_equal 10, deleted_codespaces_to_restore.count
          assert_equal 2, stafftools_deleted_codespaces.count

          Codespaces::BulkRestoreCodespaces.call(user_id: @org.id, deletion_reasons: [Codespace.deletion_reasons[:bulk_dependent_deletion], Codespace.deletion_reasons[:user_requested]])

          deleted_codespaces_to_restore.each do |codespace|
            assert_performed_with(job: CodespacesRestoreJob, args: [{ codespace: codespace }])
          end

          assert_performed_jobs 10, only: CodespacesRestoreJob

          deleted_codespaces_to_restore.each(&:reload)
          stafftools_deleted_codespaces.each(&:reload)
          assert_equal 10, Codespace.where(billable_owner: @org.id).count
          assert_equal 0, Codespace.deleted.where(billable_owner: @org.id, deletion_reason: [Codespace.deletion_reasons[:bulk_dependent_deletion], Codespace.deletion_reasons[:user_requested]]).count

          assert_equal 2, Codespace.deleted.where(billable_owner: @org.id, deletion_reason: Codespace.deletion_reasons[:stafftools_requested]).count
        end
      end

      test "does not restore codespaces if the org has been deleted", skip_enterprise: true do
        GitHub.flipper[:codespaces_pause_deletions_bulk_dependent_deletion].disable
        perform_enqueued_jobs(only: [CodespacesDeleteJob, DeleteDependentCodespacesJob, CodespacesRestoreJob]) do
          # Create a bunch of codespaces billable to the org
          10.times do
            member = create(:user)
            @org.add_member(member)
            create(:codespace, owner: member, repository: @org_repo)
          end

          assert_equal 10, Codespace.where(billable_owner: @org.id).count

          @org.destroy

          # No jobs should be enqueued because the org has been deleted
          CodespacesRestoreJob.expects(:perform_later).never

          Codespaces::BulkRestoreCodespaces.call(user_id: @org.id)
          assert_equal 0, Codespace.where(billable_owner: @org.id).count
        end
      end
    end

    context "bulk restore codespaces for user" do
      test "restores all deleted codespaces", skip_enterprise: true do
        perform_enqueued_jobs(only: CodespacesRestoreJob) do
          deleted_codespaces = create_list(:codespace, 2, :deprovisioned, owner: @user, deleted_at: Time.now)
          FakeVSOServer.environments = deleted_codespaces.map { |codespace| build_vso_environment_payload(codespace) }

          assert_equal 2, @user.codespaces.deleted.count

          Codespaces::BulkRestoreCodespaces.call(user_id: @user.id)

          deleted_codespaces.each do |codespace|
            assert_performed_with(job: CodespacesRestoreJob, args: [{ codespace: codespace }])
          end

          assert_performed_jobs 2, only: CodespacesRestoreJob

          deleted_codespaces.each(&:reload)
          assert_equal 2, @user.codespaces.count
        end
      end

      test "restores all deleted codespaces with a deletion reason", skip_enterprise: true do
        perform_enqueued_jobs(only: CodespacesRestoreJob) do
          stafftools_deleted_codespaces = create_list(:codespace, 2, :deprovisioned, owner: @user, deleted_at: Time.now, deletion_reason: Codespace.deletion_reasons[:stafftools_requested])
          user_deleted_codespaces = create_list(:codespace, 2, :deprovisioned, owner: @user, deleted_at: Time.now, deletion_reason: Codespace.deletion_reasons[:user_requested])
          FakeVSOServer.environments = user_deleted_codespaces.map { |codespace| build_vso_environment_payload(codespace) }

          assert_equal 4, @user.codespaces.deleted.count

          Codespaces::BulkRestoreCodespaces.call(user_id: @user.id, deletion_reasons: [Codespace.deletion_reasons[:user_requested]])

          user_deleted_codespaces.each do |codespace|
            assert_performed_with(job: CodespacesRestoreJob, args: [{ codespace: codespace }])
          end

          assert_performed_jobs 2, only: CodespacesRestoreJob

          user_deleted_codespaces.each(&:reload)
          assert_equal 2, @user.codespaces.count
        end
      end

      test "does not restore codespaces if the user has been deleted", skip_enterprise: true do
        GitHub.flipper[:codespaces_pause_deletions_bulk_dependent_deletion].disable
        perform_enqueued_jobs(only: [CodespacesDeleteJob, DeleteDependentCodespacesJob, CodespacesRestoreJob]) do
          codespaces = create_list(:codespace, 3, owner: @user, repository: @user_repo)

          assert_equal 3, @user.codespaces.count
          @user.destroy
          codespaces.map(&:reload)
          assert_equal 3, codespaces.map(&:is_deleted?).count

          # No jobs should be enqueued because the user has been deleted
          CodespacesRestoreJob.expects(:perform_later).never

          Codespaces::BulkRestoreCodespaces.call(user_id: @user.id)
          assert_equal 0, Codespace.where(billable_owner: @user.id).count
        end
      end
    end

    private

    def build_vso_environment_payload(codespace)
      {
        "id" => codespace.guid,
        "friendlyName" => codespace.name,
        "updated" => Time.current
      }
    end
  end
end
