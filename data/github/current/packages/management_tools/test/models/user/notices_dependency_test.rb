# typed: true
# frozen_string_literal: true

require "test_helper"

class UserNotificationsDependencyTest < GitHub::TestCase
  fixtures do
    @free_user = create(:user, login: "free-user", email: "free-user@example.com")
  end

  setup_once do
    ApplicationRecord::Domain::KeyValues.connection.execute <<~SQL
    CREATE TABLE `test_key_values` (
      `id` bigint NOT NULL AUTO_INCREMENT,
      `key` varchar(255) NOT NULL,
      `value` blob NOT NULL,
      `created_at` datetime(6) NOT NULL,
      `updated_at` datetime(6) NOT NULL,
      `expires_at` datetime(6) DEFAULT NULL,
      PRIMARY KEY (`id`),
      UNIQUE KEY `index_test_key_values_on_key` (`key`),
      KEY `index_test_key_values_on_expires_at` (`expires_at`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3;
    SQL
  end

  teardown_once do
    ApplicationRecord::Domain::KeyValues.connection.execute <<~SQL
      DROP TABLE `test_key_values`;
    SQL
  end

  setup do
    cfg = GitHub::KV::Config.new
    cfg.table_name = :test_key_values
    @custom_kv_instance = GitHub::KV.new(config: cfg) { ApplicationRecord::Domain::KeyValues.connection }
  end

  context "dismiss key values" do
    test "sets the key value" do
      user = create(:user)

      Timecop.freeze do
        user.dismiss_notice("bootcamp")
        # rubocop:todo GitHub/DoNotUseGlobalKv
        assert_equal Time.now.utc.iso8601, GitHub.kv.get("user.dismissed_notice.bootcamp.#{user.id}").value!
        # rubocop:enable GitHub/DoNotUseGlobalKv
      end
    end

    test "sets the repository key value" do
      user = create(:user)
      user.dismiss_repository_notice("cta_marketplace_ci", repository_id: 1)

      key = "user.dismissed_repository_notice.cta_marketplace_ci.1.#{user.id}"
      assert_equal "cta_marketplace_ci", GitHub.kv.get(key).value! # rubocop:todo GitHub/DoNotUseGlobalKv
    end

    test "does not set the key value if the notice is invalid" do
      user = create(:user)

      assert_raises(ArgumentError) do
        user.dismiss_notice("invalid")
      end

      assert_nil GitHub.kv.get("user.dismissed_notice.invalid.#{user.id}").value! # rubocop:todo GitHub/DoNotUseGlobalKv
    end

    test "does not set the repository key value if the notice is invalid" do
      user = create(:user)
      user.dismiss_repository_notice("invalid", repository_id: 1)

      # rubocop:todo GitHub/DoNotUseGlobalKv
      assert_nil GitHub.kv.get("user.dismissed_repository_notice.invalid.1.#{user.id}").value!
      # rubocop:enable GitHub/DoNotUseGlobalKv
    end

    test "deletes the key value" do
      user = create(:user)

      Timecop.freeze do
        user.dismiss_notice("bootcamp")
        # rubocop:todo GitHub/DoNotUseGlobalKv
        assert_equal Time.now.utc.iso8601, GitHub.kv.get("user.dismissed_notice.bootcamp.#{user.id}").value!
        # rubocop:enable GitHub/DoNotUseGlobalKv

        user.reset_notice("bootcamp")

        # rubocop:todo GitHub/DoNotUseGlobalKv
        assert_nil GitHub.kv.get("user.dismissed_notice.bootcamp.#{user.id}").value!
        # rubocop:enable GitHub/DoNotUseGlobalKv
      end
    end

    test "deletes the repository key value" do
      user = create(:user)
      user.dismiss_repository_notice("cta_marketplace_ci", repository_id: 1)
      assert_equal "cta_marketplace_ci",
        # rubocop:todo GitHub/DoNotUseGlobalKv
        GitHub.kv.get("user.dismissed_repository_notice.cta_marketplace_ci.1.#{user.id}").value!
      # rubocop:enable GitHub/DoNotUseGlobalKv

      user.reset_repository_notice("cta_marketplace_ci", repository_id: 1)

      key = "user.dismissed_repository_notice.cta_marketplace_ci.1.#{user.id}"
      assert_nil GitHub.kv.get(key).value! # rubocop:todo GitHub/DoNotUseGlobalKv
    end

    context "with a custom KV store" do
      test "sets the key value" do
        user = create(:user)

        Timecop.freeze do
          user.dismiss_notice("bootcamp", kv_store: @custom_kv_instance)
          assert_equal Time.now.utc.iso8601, @custom_kv_instance.get("user.dismissed_notice.bootcamp.#{user.id}").value!
        end
      end

      test "deletes the key value" do
        user = create(:user)

        Timecop.freeze do
          user.dismiss_notice("bootcamp", kv_store: @custom_kv_instance)
          assert_equal Time.now.utc.iso8601, @custom_kv_instance.get("user.dismissed_notice.bootcamp.#{user.id}").value!

          user.reset_notice("bootcamp", kv_store: @custom_kv_instance)

          assert_nil @custom_kv_instance.get("user.dismissed_notice.bootcamp.#{user.id}").value!
        end
      end
    end
  end

  test "dashboard notices know what to show" do
    @free_user.activate_notice :orgs_newbie
    assert @free_user.notices_for_dashboard.include?("orgs_newbie")
  end

  test "dashboard notices knows when to hide a notification" do
    @free_user.activate_notice :orgs_newbie
    @free_user.deactivate_notice :orgs_newbie
    assert !@free_user.notices_for_dashboard.include?("orgs_newbie")
  end

  test "dashboard notices doesn't activate a notice that the user has previously hidden" do
    @free_user.activate_notice :orgs_newbie
    @free_user.deactivate_notice :orgs_newbie
    @free_user.activate_notice :orgs_newbie
    refute @free_user.notices_for_dashboard.include?("orgs_newbie")
  end

  test "dashboard notices can forcefully activate a hidden notification" do
    @free_user.activate_notice :orgs_newbie
    @free_user.deactivate_notice :orgs_newbie
    @free_user.activate_notice! :orgs_newbie
    assert @free_user.notices_for_dashboard.include?("orgs_newbie")
  end

  test "dashboard notices deletes a notice properly" do
    @free_user.activate_notice :orgs_newbie
    assert @free_user.notices_for_dashboard.include?("orgs_newbie")
    @free_user.delete_notice :orgs_newbie
    assert !@free_user.notices_for_dashboard.include?("orgs_newbie")
  end

  test "dashboard notices reports to failbot if error occurs fetching notices" do
    DashboardNoticesStore.
      stubs(:get_for_user_id).
      returns(GitHub::Result.new { raise(DashboardNoticesStore::UnavailableError, "some error") })

    @free_user.notices_for_dashboard

    assert_equal 1, Failbot.reports.count { |report|
      report["app"] == "github-user" &&
        Failbot.exception_classname_from_hash(report) == "DashboardNoticesStore::UnavailableError" &&
        report["operation"] == ":notices_for_dashboard"
    }
  end

  test "dashboard notices reports to failbot if error occurs activating notice" do
    DashboardNoticesStore.
      stubs(:add).
      returns(GitHub::Result.new { raise(DashboardNoticesStore::UnavailableError, "some error") })

    @free_user.activate_notice! :orgs_newbie

    assert_equal 1, Failbot.reports.count { |report|
      report["app"] == "github-user" &&
        Failbot.exception_classname_from_hash(report) == "DashboardNoticesStore::UnavailableError" &&
        report["operation"] == ":activate_notice" &&
        report["notice_name"] == "orgs_newbie"
    }
  end

  test "dashboard notices reports to failbot if error occurs deactivating notice" do
    DashboardNoticesStore.
      stubs(:deactivate).
      returns(GitHub::Result.new { raise(DashboardNoticesStore::UnavailableError, "some error") })

    @free_user.deactivate_notice :orgs_newbie

    assert_equal 1, Failbot.reports.count { |report|
      report["app"] == "github-user" &&
        Failbot.exception_classname_from_hash(report) == "DashboardNoticesStore::UnavailableError" &&
        report["operation"] == ":deactivate_notice" &&
        report["notice_name"] == "orgs_newbie"
    }
  end

  test "dashboard notices reports to failbot if error occurs deleting notice" do
    DashboardNoticesStore.
      stubs(:delete).
      returns(GitHub::Result.new { raise(DashboardNoticesStore::UnavailableError, "some error") })

    @free_user.delete_notice :orgs_newbie

    assert_equal 1, Failbot.reports.count { |report|
      report["app"] == "github-user" &&
        Failbot.exception_classname_from_hash(report) == "DashboardNoticesStore::UnavailableError" &&
        report["operation"] == ":delete_notice" &&
        report["notice_name"] == "orgs_newbie"
    }
  end

  context "#dismissed_notice?" do
    context "missing notice" do
      test "when configured :failbot, reports to failbot" do
        GitHub.stubs(:missing_user_notice_behavior).returns(:failbot)
        user = create(:user)

        user.dismissed_notice?("invalid")

        assert_equal 1, Failbot.reports.count { |report|
          report["app"] == "github-user" &&
            Failbot.exception_classname_from_hash(report) == "ArgumentError" &&
            report["operation"].end_with?("dismissed_notice?")
        }
      end

      test "when configured :raise, raises" do
        GitHub.stubs(:missing_user_notice_behavior).returns(:raise)
        user = create(:user)

        ex = assert_raises(ArgumentError) do
          user.dismissed_notice?("invalid")
        end

        assert_equal("unregistered notice: \"invalid\"", ex.message)
      end

      test "when not configured, raises" do
        GitHub.stubs(:missing_user_notice_behavior).returns(nil)
        user = create(:user)

        ex = assert_raises(ArgumentError) do
          user.dismissed_notice?("invalid")
        end

        assert_equal("unregistered notice: \"invalid\"", ex.message)
      end
    end

    test "returns true if the user was created after notice effective date and notice is hide_from_new_user" do
      future_user = create(:user, created_at: 1.year.from_now)

      assert future_user.dismissed_notice?("release_only_subscription_notice")
    end

    test "returns false if the user was created after notice effective date and notice is not hide_from_new_user" do
      future_user = create(:user, created_at: 1.year.from_now)

      refute future_user.dismissed_notice?("whats_new_check_in_dash_2019_q1")
    end

    test "returns true if the user has dismissed the notice" do
      old_user = create(:user, created_at: 1.year.ago)
      old_user.dismiss_notice("bootcamp")

      assert old_user.dismissed_notice?("bootcamp")
    end

    test "returns false if the user has not dismissed the notice" do
      old_user = create(:user, created_at: 1.year.ago)

      refute old_user.dismissed_notice?("bootcamp")
    end

    context "using custom KV store" do
      test "returns true if the user has dismissed the notice" do
        old_user = create(:user, created_at: 1.year.ago)
        old_user.dismiss_notice("bootcamp", kv_store: @custom_kv_instance)

        assert old_user.dismissed_notice?("bootcamp", kv_store: @custom_kv_instance)
      end

      test "returns false if the user has not dismissed the notice" do
        old_user = create(:user, created_at: 1.year.ago)

        refute old_user.dismissed_notice?("bootcamp", kv_store: @custom_kv_instance)
      end
    end
  end

  context "#notice_dismissed_at" do
    test "returns nil for string values" do
      user = create(:user)
      GitHub.kv.set("user.dismissed_notice.bootcamp.#{user.id}", "bootcamp") # rubocop:todo GitHub/DoNotUseGlobalKv

      assert_nil user.notice_dismissed_at("bootcamp")
    end

    test "returns nil when notice has not been dismissed" do
      user = create(:user)

      assert_nil user.notice_dismissed_at("bootcamp")
    end

    test "returns nil if user was never shown the notice" do
      future_user = create(:user, created_at: 1.year.from_now)

      assert_nil future_user.notice_dismissed_at("release_only_subscription_notice")
    end

    test "returns time user dismissed notice" do
      Timecop.freeze do
        user = create(:user)
        user.dismiss_notice("bootcamp")

        assert_equal Time.now.utc.to_i, user.notice_dismissed_at("bootcamp").to_i
      end
    end

    test "returns time using custom KV store" do
      Timecop.freeze do
        user = create(:user)
        user.dismiss_notice("bootcamp", kv_store: @custom_kv_instance)

        assert_equal Time.now.utc.to_i, user.notice_dismissed_at("bootcamp",  kv_store: @custom_kv_instance).to_i
      end
    end
  end

  context "business notices" do
    test "dismissing business notice" do
      @free_user.dismiss_business_notice("invoiced_customer_set_spending_limit", business_id: 5000)
      key = "user.dismissed_business_notice.invoiced_customer_set_spending_limit.5000.#{@free_user.id}"
      # rubocop:todo GitHub/DoNotUseGlobalKv
      assert_equal "invoiced_customer_set_spending_limit", GitHub.kv.get(key).value!
      # rubocop:enable GitHub/DoNotUseGlobalKv
    end

    test "dismissing unknown business notice" do
      @free_user.dismiss_business_notice("unknown", business_id: 5000)
      key = "user.dismissed_business_notice.unknown.5000.#{@free_user.id}"
      assert_nil GitHub.kv.get(key).value! # rubocop:todo GitHub/DoNotUseGlobalKv
    end

    test "checking if business notice is dismissed" do
      refute @free_user.dismissed_business_notice?("invoiced_customer_set_spending_limit", business_id: 5000)
      @free_user.dismiss_business_notice("invoiced_customer_set_spending_limit", business_id: 5000)
      assert @free_user.dismissed_business_notice?("invoiced_customer_set_spending_limit", business_id: 5000)
      refute @free_user.dismissed_business_notice?("invoiced_customer_set_spending_limit", business_id: 6600)
    end

    test "resetting business notice" do
      @free_user.dismiss_business_notice("invoiced_customer_set_spending_limit", business_id: 5000)
      assert @free_user.dismissed_business_notice?("invoiced_customer_set_spending_limit", business_id: 5000)
      @free_user.reset_business_notice("invoiced_customer_set_spending_limit", business_id: 5000)
      refute @free_user.dismissed_business_notice?("invoiced_customer_set_spending_limit", business_id: 5000)
    end
  end

  context "organization notices" do
    test "dismissing organization notice" do
      Timecop.freeze do
        organization = create(:organization)
        admin = organization.admins.first
        admin.dismiss_organization_notice("invoiced_customer_set_spending_limit", organization)

        key = "user.dismissed_organization_notice.invoiced_customer_set_spending_limit.#{organization.id}.#{admin.id}"
        assert admin.dismissed_organization_notice?("invoiced_customer_set_spending_limit", organization)
        assert_equal Time.now.utc.to_i, admin.notice_dismissed_at("invoiced_customer_set_spending_limit", organization).to_i
      end
    end

    test "dismissing organization notice for whole org" do
      Timecop.freeze do
        organization = create(:organization)
        admin = organization.admins.first
        admin.dismiss_organization_notice("invoiced_customer_set_spending_limit", organization, for_whole_org: true)

        key = "user.dismissed_organization_notice.invoiced_customer_set_spending_limit.#{organization.id}."
        assert_equal Time.now.utc.to_i, organization.notice_dismissed_at("invoiced_customer_set_spending_limit", organization, for_whole_org: true).to_i
      end
    end

    test "dismissing unknown organization notice" do
      organization = create(:organization)
      admin = organization.admins.first
      admin.dismiss_organization_notice("unknown", organization)

      key = "user.dismissed_organization_notice.unknown.#{organization.id}.#{admin.id}"
      assert_nil GitHub.kv.get(key).value! # rubocop:todo GitHub/DoNotUseGlobalKv
    end

    test "checking if organization notice is dismissed" do
      organization = create(:organization)
      other_organization = create(:organization)
      admin = organization.admins.first

      refute admin.dismissed_organization_notice?("invoiced_customer_set_spending_limit", organization)
      admin.dismiss_organization_notice("invoiced_customer_set_spending_limit", organization)
      assert admin.dismissed_organization_notice?("invoiced_customer_set_spending_limit", organization)
      refute admin.dismissed_organization_notice?("invoiced_customer_set_spending_limit", other_organization)
    end

    test "resetting organization notice" do
      organization = create(:organization)
      other_organization = create(:organization)
      admin = organization.admins.first

      admin.dismiss_organization_notice("invoiced_customer_set_spending_limit", organization)
      assert admin.dismissed_organization_notice?("invoiced_customer_set_spending_limit", organization)
      admin.reset_organization_notice("invoiced_customer_set_spending_limit", organization)
      refute admin.dismissed_organization_notice?("invoiced_customer_set_spending_limit", organization)
    end

    test "resetting organization notice for whole org" do
      organization = create(:organization)
      other_organization = create(:organization)
      admin = organization.admins.first

      admin.dismiss_organization_notice("invoiced_customer_set_spending_limit", organization, for_whole_org: true)
      assert admin.dismissed_organization_notice?("invoiced_customer_set_spending_limit", organization, for_whole_org: true)
      admin.reset_organization_notice("invoiced_customer_set_spending_limit", organization, for_whole_org: true)
      refute admin.dismissed_organization_notice?("invoiced_customer_set_spending_limit", organization, for_whole_org: true)
    end

    context "with custom kv store" do
      test "dismissing organization notice" do
        Timecop.freeze do
          organization = create(:organization)
          admin = organization.admins.first
          admin.dismiss_organization_notice("invoiced_customer_set_spending_limit", organization, kv_store: @custom_kv_instance)

          key = "user.dismissed_organization_notice.invoiced_customer_set_spending_limit.#{organization.id}.#{admin.id}"
          assert admin.dismissed_organization_notice?("invoiced_customer_set_spending_limit", organization, kv_store: @custom_kv_instance)
          assert_equal Time.now.utc.to_i, admin.notice_dismissed_at("invoiced_customer_set_spending_limit", organization, kv_store: @custom_kv_instance).to_i
        end
      end

      test "dismissing organization notice for whole org" do
        Timecop.freeze do
          organization = create(:organization)
          admin = organization.admins.first
          admin.dismiss_organization_notice("invoiced_customer_set_spending_limit", organization, for_whole_org: true, kv_store: @custom_kv_instance)

          key = "user.dismissed_organization_notice.invoiced_customer_set_spending_limit.#{organization.id}."
          assert_equal Time.now.utc.to_i, organization.notice_dismissed_at("invoiced_customer_set_spending_limit", organization, for_whole_org: true, kv_store: @custom_kv_instance).to_i
        end
      end

      test "resetting organization notice" do
        organization = create(:organization)
        other_organization = create(:organization)
        admin = organization.admins.first

        admin.dismiss_organization_notice("invoiced_customer_set_spending_limit", organization, kv_store: @custom_kv_instance)
        assert admin.dismissed_organization_notice?("invoiced_customer_set_spending_limit", organization, kv_store: @custom_kv_instance)
        admin.reset_organization_notice("invoiced_customer_set_spending_limit", organization, kv_store: @custom_kv_instance)
        refute admin.dismissed_organization_notice?("invoiced_customer_set_spending_limit", organization, kv_store: @custom_kv_instance)
      end

      test "resetting organization notice for whole org" do
        organization = create(:organization)
        other_organization = create(:organization)
        admin = organization.admins.first

        admin.dismiss_organization_notice("invoiced_customer_set_spending_limit", organization, for_whole_org: true, kv_store: Memex::KV.store)
        assert admin.dismissed_organization_notice?("invoiced_customer_set_spending_limit", organization, for_whole_org: true, kv_store: Memex::KV.store)
        admin.reset_organization_notice("invoiced_customer_set_spending_limit", organization, for_whole_org: true, kv_store: Memex::KV.store)
        refute admin.dismissed_organization_notice?("invoiced_customer_set_spending_limit", organization, for_whole_org: true, kv_store: Memex::KV.store)
      end
    end
  end

  context "enterprise announcement dismissals" do
    test "dismissing enterprise announcement given correct uuid" do
      # Setup
      org = create :organization
      admin = org.admins.first
      business = create :business, owners: [admin], organizations: [org]

      # Announcement
      GitHub::EnterpriseAnnouncement.set_announcement \
        announcement: "Do or do not. There is no try.",
        user_dismissible: true
      announcement = GitHub::EnterpriseAnnouncement.get_announcement

      # Dismissal
      admin.dismiss_global_enterprise_announcement(uuid: announcement.uuid)

      # Equality check
      key = "enterprise:announcement:dismiss:#{admin.id}"
      assert_equal announcement.uuid, GitHub.kv.get(key).value! # rubocop:todo GitHub/DoNotUseGlobalKv
    end

    test "fails dismissing enterprise announcement given incorrect uuid" do
      # Setup
      org = create :organization
      admin = org.admins.first
      business = create :business, owners: [admin], organizations: [org]

      # Announcement
      GitHub::EnterpriseAnnouncement.set_announcement \
        announcement: "Do or do not. There is no try.",
        user_dismissible: true
      announcement = GitHub::EnterpriseAnnouncement.get_announcement

      # Dismissal
      admin.dismiss_global_enterprise_announcement(uuid: "big-ol-fake-uuid")

      # Equality check
      key = "enterprise:announcement:dismiss:#{admin.id}"
      refute_equal announcement.uuid, GitHub.kv.get(key).value! # rubocop:todo GitHub/DoNotUseGlobalKv
    end

    test "fails dismissing enterprise announcement that is not user dismissible" do
      # Setup
      org = create :organization
      admin = org.admins.first
      business = create :business, owners: [admin], organizations: [org]

      # Announcement
      GitHub::EnterpriseAnnouncement.set_announcement \
        announcement: "Do or do not. There is no try.",
        user_dismissible: false
      announcement = GitHub::EnterpriseAnnouncement.get_announcement

      # Dismissal
      admin.dismiss_global_enterprise_announcement(uuid: "big-ol-fake-uuid")

      # Key check
      key = "enterprise:announcement:dismiss:#{admin.id}"
      assert GitHub.kv.get(key).value!.blank? # rubocop:todo GitHub/DoNotUseGlobalKv
    end
  end

  context "project notices" do
    test "dimissing project migration notice" do
      user = create(:user)
      project = create(:project, owner: user, name: "test")
      user.dismiss_project_notice("project_migration_notice", project_id: project.id)

      key = "user.dismissed_project_notice.project_migration_notice.#{project.id}.#{user.id}"
      assert_equal "project_migration_notice", GitHub.kv.get(key).value! # rubocop:todo GitHub/DoNotUseGlobalKv
    end

    test "dimissing project migration complete notice" do
      user = create(:user)
      project = create(:project, owner: user, name: "test")
      user.dismiss_project_notice("project_migration_complete_notice", project_id: project.id)

      key = "user.dismissed_project_notice.project_migration_complete_notice.#{project.id}.#{user.id}"
      assert_equal "project_migration_complete_notice", GitHub.kv.get(key).value! # rubocop:todo GitHub/DoNotUseGlobalKv
    end

    test "does not dismiss a project notice if the notice does not exist in the allowed list" do
      user = create(:user)
      project = create(:project, owner: user, name: "test")
      user.dismiss_project_notice("project_migration", project_id: project.id)

      key = "user.dismissed_project_notice.project_migration_notice.#{project.id}.#{user.id}"
      assert_nil GitHub.kv.get(key).value! # rubocop:todo GitHub/DoNotUseGlobalKv
    end

    test "checking if project migration notice is dismissed" do
      user = create(:user)
      project = create(:project, owner: user, name: "test")

      refute user.dismissed_project_notice?("project_migration_notice", project_id: project.id)
      user.dismiss_project_notice("project_migration_notice", project_id: project.id)
      assert user.dismissed_project_notice?("project_migration_notice", project_id: project.id)
    end

    test "checking if project migration complete notice is dismissed" do
      user = create(:user)
      project = create(:project, owner: user, name: "test")

      refute user.dismissed_project_notice?("project_migration_complete_notice", project_id: project.id)
      user.dismiss_project_notice("project_migration_complete_notice", project_id: project.id)
      assert user.dismissed_project_notice?("project_migration_complete_notice", project_id: project.id)
    end

    test "resetting project notices" do
      user = create(:user)
      project = create(:project, owner: user, name: "test")

      user.dismiss_project_notice("project_migration_notice", project_id: project.id)
      assert user.dismissed_project_notice?("project_migration_notice", project_id: project.id)
      user.reset_project_notice("project_migration_notice", project_id: project.id)
      refute user.dismissed_project_notice?("project_migration_notice", project_id: project.id)

      user.dismiss_project_notice("project_migration_complete_notice", project_id: project.id)
      assert user.dismissed_project_notice?("project_migration_complete_notice", project_id: project.id)
      user.reset_project_notice("project_migration_complete_notice", project_id: project.id)
      refute user.dismissed_project_notice?("project_migration_complete_notice", project_id: project.id)
    end

    test "using Memex KV store" do
      user = create(:user)
      project = create(:project, owner: user, name: "test")

      # dismiss
      user.dismiss_project_notice("project_migration_notice", project_id: project.id, kv_store: Memex::KV.store)
      # dismissed?
      key = "user.dismissed_project_notice.project_migration_notice.#{project.id}.#{user.id}"
      assert_equal "project_migration_notice", Memex::KV.store.get(key).value! # rubocop:todo GitHub/DoNotUseGlobalKv
      assert user.dismissed_project_notice?("project_migration_notice", project_id: project.id, kv_store: Memex::KV.store)
      # reset
      user.reset_project_notice("project_migration_notice", project_id: project.id, kv_store: Memex::KV.store)
      refute user.dismissed_project_notice?("project_migration_notice", project_id: project.id, kv_store: Memex::KV.store)
    end
  end
end
