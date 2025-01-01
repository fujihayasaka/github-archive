# typed: true
# frozen_string_literal: true

require "test_helper"

class MigrationTest < GitHub::TestCase
  include UploadableTestHelpers

  fixtures do
    @mannequin = create(:mannequin)

    @migration = create(
      :migration,
      state: Migration.state_value(:failed),
      mannequins: [@mannequin],
    )
  end

  test "#destroy_file removes the file" do
    migration = create :migration, guid: "initial-guid"
    file = migration.build_file(uploader: migration.creator)
    save_file_for_uploadable(file, name: "export.tar.gz", content_type: "application/gzip")

    path = "/#{GitHub.migration_file_base_path}/#{migration.id}/#{file.id}"
    assert_storage_policy_delete(file, path) do
      migration.destroy_file
    end
  end

  test "#import can transition into retry importing state" do
    migration = create(:migration,
      state: Migration.state_value(:failed_import),
    )

    migration.retry_import!

    assert_equal(migration.state, Migration.state_value(:pending))
  end

  test "#export can transition into retry exporting state" do
    @migration.retry_export!

    assert_equal(@migration.state, Migration.state_value(:exporting))
  end

  test "#record_timing records a new MigrationTiming" do
    now = Time.now
    travel_proc = proc { Timecop.travel(now + 20.seconds) }

    MigrationTiming.expects(:record).with(@migration, :import, &travel_proc)

    Timecop.freeze(now) do
      @migration.record_timing(:import, &travel_proc)
    end
  end

  test "#mannequins retrieves Mannequin models" do
    assert_equal @migration.mannequins, [@mannequin]
  end

  test "#failed_import! cannot transition from READY to failed" do
    @migration.state = :ready
    refute @migration.can_failed_import?
  end

  test "#force_failed_import! doesn't care what your state is" do
    migration = @migration.clone
    migration.state = :ready
    migration.save

    migration.force_failed_import!

    assert_equal 10, migration.reload.state
  end

  test "#safely_change_migration_state! retries on workflow transition error" do
    migration = @migration.clone
    migration.state = :importing
    migration.save
    migration.expects(:begin_import!).raises(Workflow::NoTransitionAllowed).times(2).then.returns(true)
    migration.safely_change_migration_state!(:begin_import!)
  end

  test "#safely_change_migration_state! raises after retries are exhausted" do
    migration = @migration.clone
    migration.state = :pending
    migration.save
    migration.expects(:begin_import!).raises(Workflow::NoTransitionAllowed).at_least(5)

    assert_raises(Workflow::NoTransitionAllowed) do
      migration.safely_change_migration_state!(:begin_import!)
    end
  end

  test "$safely_change_migration_state! succeeds when migration is in pending state" do
    migration = @migration.clone
    migration.state = :pending
    migration.save
    assert migration.safely_change_migration_state!(:begin_import!)
  end
end

class MigrationInstrumentationTest < GitHub::TestCase
  include UploadableTestHelpers

  fixtures do
    @migration = create :migration, guid: "initial-guid"

    @org = create(:organization)
    @user = create(:user)
  end

  test "instruments destroy_file" do
    @file = @migration.build_file(uploader: @migration.creator)
    save_file_for_uploadable @file, name: "export.tar.gz"

    events = subscribe "migration.destroy_file"

    path = "/#{GitHub.migration_file_base_path}/#{@migration.id}/#{@file.id}"
    assert_storage_policy_delete(@file, path) do
      @migration.destroy_file
    end

    assert event = events.pop, "an event was expected"
    assert_equal "migration.destroy_file", event.name
  end

  context "#clean_up" do
    test "deletes related MigratableResource records with DeleteDependentRecordsJob" do
      # Create some records to clean up.
      5.times { create(:migratable_resource, guid: @migration.guid) }

      # Create some records that should not be cleaned up.
      3.times { create(:migratable_resource, guid: "other-guid") }

      # Migration#clean_up is implemented in a background job.
      perform_enqueued_jobs(only: [DeleteDependentRecordsJob]) do
        assert_difference("MigratableResource.count", -5) { @migration.clean_up }
      end
    end

    test "equeues DeleteDependentRecordsJob for a later time" do
      Timecop.freeze do
        @migration.clean_up

        assert_enqueued_with(at: Time.now + 6.hours, job: DeleteDependentRecordsJob)
      end
    end
  end
end

class UserMigrationUrlWithTokenLogicTest < GitHub::TestCase
  include UploadableTestHelpers

  fixtures do
    @user = create(:user)

    GitHub.migrator.download_everything(@user)
    @migration = Migration.for_owner(@user).first
    file = T.must(@migration).build_file(uploader: T.must(@migration).creator)
    save_file_for_uploadable file, name: "export.tar.gz"

    @random_user = create(:user)
  end

  if GitHub.download_everything_button_enabled?
    test "migration.exported sends email with GitHub url" do
      perform_enqueued_jobs(only: [ApplicationDeliveryJob]) do
        @migration.exported!
      end

      mailer = ActionMailer::Base.deliveries.last

      # plain text version
      assert_includes mailer.body.parts.first.body, "github.com/settings/migration/download"
      refute_includes mailer.body.parts.first.body, @migration.file.download_url(actor: @user)

      # html version
      assert_includes mailer.body.parts.second.body, "github.com/settings/migration/download"
      refute_includes mailer.body.parts.second.body, @migration.file.download_url(actor: @user)
    end
  else
    test "migration.exported does not send email" do
      only = []
      perform_enqueued_jobs(only: only) do
        @migration.exported!
      end

      assert_empty ActionMailer::Base.deliveries
    end
  end

  test "send_user_migration_email sends GitHub url, not direct download url" do
    @migration.exported!

    perform_enqueued_jobs(only: [ApplicationDeliveryJob]) do
      @migration.send_user_migration_email
    end

    mailer = ActionMailer::Base.deliveries.last

    # plain text version
    assert_includes mailer.body.parts.first.body, "github.com/settings/migration/download"
    refute_includes mailer.body.parts.first.body, @migration.file.download_url(actor: @user)

    # html version
    assert_includes mailer.body.parts.second.body, "github.com/settings/migration/download"
    refute_includes mailer.body.parts.second.body, @migration.file.download_url(actor: @user)
  end

  test "token_to_url returns nil for correct user with bad token" do
    @migration.exported!

    token = @migration.owner.signed_auth_token \
          scope:   "UserMigration",
          expires: @migration.created_at - 1.day, #it's expired
          data:    { migration_id: @migration.id }

    assert_nil Migration.token_to_url(token.to_s, @user)
  end

  test "token_to_url returns nil for incorrect user with good token" do
    @migration.exported!

    token = @migration.owner.signed_auth_token \
          scope:   "UserMigration",
          expires: @migration.created_at + 7.days,
          data:    { migration_id: @migration.id }

    assert_nil Migration.token_to_url(token.to_s, @random_user)
  end

  test "token_to_url returns nil for deleted file" do
    token = @migration.owner.signed_auth_token \
          scope:   "UserMigration",
          expires: @migration.created_at + 7.days,
          data:    { migration_id: @migration.id }

    @migration.destroy_file

    assert_nil Migration.token_to_url(token.to_s, @user)
  end

  test "token_to_url returns s3 aws url for correct user with good token" do
    @migration.exported!

    token = @migration.owner.signed_auth_token \
          scope:   "UserMigration",
          expires: @migration.created_at + 7.days,
          data:    { migration_id: @migration.id }

    assert_match /github-dev.s3.amazonaws.com\/migration\//, Migration.token_to_url(token.to_s, @user)
  end
end

class NotificationUponExportTest < GitHub::TestCase
  include UploadableTestHelpers
  fixtures do
    @admin = create :user, login: "org-admin", email: "email@org.com"
    @user_repo = create :repository, owner: @admin, name: "personal-repo"
    @user_migration = create(:migration, {
      creator: @admin,
      owner: @admin,
      state: Migration.state_value(:pending),
    })
    @user_migration.repositories << @user_repo

    @org = create :organization, login: "the-org", admin: @admin
    @org_repo = create :repository, owner: @org, name: "org-repo"
    @org_migration = create(:migration, {
      creator: @admin,
      owner: @org,
      state: Migration.state_value(:pending),
    })
    @org_migration.repositories << @org_repo
  end

  if GitHub.download_everything_button_enabled?
    test "sends mailer to export owner" do
      assert_difference "ActionMailer::Base.deliveries.count", 1 do
        perform_enqueued_jobs(only: [ApplicationDeliveryJob]) do
          export @user_migration
        end
      end

      mailer = ActionMailer::Base.deliveries.last
      assert_equal mailer.subject, "[GitHub] Your data export is ready to download"
      assert_equal mailer.to.first, @admin.email
    end

    test "sends no mailer if export owner is an org" do
      assert_difference "ActionMailer::Base.deliveries.count", 0 do
        export @org_migration
      end
    end
  else
    test "sends no mailer if feature is disabled" do
      assert_difference "ActionMailer::Base.deliveries.count", 0 do
        perform_enqueued_jobs(only: [DeleteDependentRecordsJob]) do
          export @user_migration
        end
      end
    end
  end

  private

  def export(migration)
    assert_s3_client_upload(
      bucket: MigrationFile.storage_s3_bucket,
      key_regexp: %r{#{GitHub.migration_file_base_path}/#{migration.id}/\d+\z},
      acl: "private",
    ) do
      MigrationExportToArchiveJob.perform_now(migration)
    end
  end
end
