# typed: true
# frozen_string_literal: true

require "test_helper"

class BlockedSettingsTest < GitHub::TestCase
  fixtures do
    @org = create(:organization)
    @owner = create(:user)
    if GitHub.enterprise?
      @biz = create(:global_business)
      @user = create(:user)
    else
      @biz = create(:business, :enterprise_managed, organizations: [@org])
      @user = create(:emu, business: @biz)
    end
    @biz.mark_advanced_security_as_purchased_for_entity(actor: @owner)
  end

  setup do
    GitHub.stubs(:ghas_for_enterprise_users_enabled?).returns(true) if GitHub.enterprise?
  end

  context "#each" do
    test "yields each blocked setting" do
      setting = :auto_codeql_disable_all
      blocked = BlockedSettings::BLOCKING_SETTINGS[setting]

      SecurityProductsEnablement::JobStatus.create({ id: SecurityAnalysisSettingsUpdateJob.job_id(@org, setting) })
      SecurityProductsEnablement::JobStatus.create({ id: SecurityAnalysisSettingsUpdateJob.job_id(@user, setting) })

      [@biz, @org, @user].each do |owner|
        BlockedSettings.new(owner).each do |blocked_setting|
          assert_includes(blocked, blocked_setting)
        end
      end
    end
  end

  context "#entries", skip_enterprise: true do
    test "returns the blocked settings" do
      setting = :secret_scanning_enable_all
      blocked = BlockedSettings::BLOCKING_SETTINGS[setting]

      SecurityProductsEnablement::JobStatus.create({ id: SecurityAnalysisSettingsUpdateJob.job_id(@org, setting) })
      SecurityProductsEnablement::JobStatus.create({ id: SecurityAnalysisSettingsUpdateJob.job_id(@user, setting) })

      [@biz, @org, @user].each do |owner|
        assert_same_elements(blocked, BlockedSettings.new(owner).entries)
        assert_same_elements(blocked, BlockedSettings.new(owner).to_a)
      end
    end

    test "returns the blocked settings for repo counter" do
      setting = :secret_scanning_enable_all
      blocked = BlockedSettings::BLOCKING_SETTINGS[setting]

      BlockedSettings.new(@org).repo_counter.increment(setting)
      BlockedSettings.new(@user).repo_counter.increment(setting)

      [@biz, @org, @user].each do |owner|
        assert_same_elements(blocked, BlockedSettings.new(owner).entries)
        assert_same_elements(blocked, BlockedSettings.new(owner).to_a)
      end
    end

    test "returns the blocked settings for both enable-all and repo counter" do
      assert_empty BlockedSettings.new(@org).blockers

      BlockedSettings.new(@org).repo_counter.increment(:advanced_security_enable_all)
      SecurityProductsEnablement::JobStatus.create({ id: SecurityAnalysisSettingsUpdateJob.job_id(@org, :auto_codeql_enable_all) })

      [@biz, @org].each do |owner|
        assert_same_elements [:advanced_security_enable_all, :auto_codeql_enable_all], BlockedSettings.new(owner).blockers
      end
    end
  end

  context "#blockers", skip_enterprise: true do
    test "returns the settings causing the blockage" do
      setting = :auto_codeql_disable_all

      SecurityProductsEnablement::JobStatus.create({ id: SecurityAnalysisSettingsUpdateJob.job_id(@org, setting) })
      SecurityProductsEnablement::JobStatus.create({ id: SecurityAnalysisSettingsUpdateJob.job_id(@user, setting) })

      [@biz, @org, @user].each do |owner|
        assert_same_elements([setting], BlockedSettings.new(owner).blockers)
      end
    end

    test "returns the settings causing the blockage for repo counter" do
      setting = :auto_codeql_disable_all
      assert_empty BlockedSettings.new(@org).blockers

      BlockedSettings.new(@org).repo_counter.increment(setting)
      BlockedSettings.new(@user).repo_counter.increment(setting)

      [@biz, @org, @user].each do |owner|
        assert_same_elements([setting], BlockedSettings.new(owner).blockers)
      end
    end

    test "returns the settings causing the blockage for both enable-all and repo counter" do
      assert_empty BlockedSettings.new(@org).blockers

      BlockedSettings.new(@org).repo_counter.increment(:advanced_security_enable_all)
      SecurityProductsEnablement::JobStatus.create({ id: SecurityAnalysisSettingsUpdateJob.job_id(@org, :auto_codeql_enable_all) })

      [@biz, @org].each do |owner|
        assert_same_elements [:advanced_security_enable_all, :auto_codeql_enable_all], BlockedSettings.new(owner).blockers
      end
    end

    context "a new repo process is in progress" do
      test "returns :automatically_enable_for_new_repos" do
        SecurityProductsEnablement::JobStatus.create({ id: UpdateBusinessSecurityFeatureForNewReposJob.job_id(@biz) })

        [@biz, @org].each do |owner|
          assert_same_elements([:automatically_enable_for_new_repos], BlockedSettings.new(owner).blockers)
        end

        assert_empty(BlockedSettings.new(@user).blockers)
      end
    end
  end

  context "#inspect", skip_enterprise: true do
    test "returns a string representation of the object" do
      setting = :auto_codeql_disable_all
      blocked = BlockedSettings::BLOCKING_SETTINGS[setting]
      expected = "[:advanced_security_disable_all, :advanced_security_enable_all, :advanced_security_user_namespace_enable_all, :advanced_security_user_namespace_disable_all, :auto_codeql_disable_all, :auto_codeql_enable_all, :auto_codeql_enable_all_extended]"

      SecurityProductsEnablement::JobStatus.create({ id: SecurityAnalysisSettingsUpdateJob.job_id(@org, setting) })
      SecurityProductsEnablement::JobStatus.create({ id: SecurityAnalysisSettingsUpdateJob.job_id(@user, setting) })

      [@biz, @org, @user].each do |owner|
        assert_equal(expected, BlockedSettings.new(owner).inspect)
        assert_equal(expected, BlockedSettings.new(owner).to_s)
        assert_equal(expected, "#{BlockedSettings.new(owner)}")
      end
    end
  end

  context "#message" do
    context "owner is a business", skip_enterprise: true do
      test "returns the business-level message" do
        SecurityProductsEnablement::JobStatus.create({ id: SecurityAnalysisSettingsUpdateJob.job_id(@org, :auto_codeql_disable_all) })

        assert_equal(
          "A change has been made to a configuration at either the enterprise or organization level. Some features " \
          "under GitHub Advanced Security cannot be enabled or disabled until changes are propagated to all " \
          "organizations in this enterprise.",
          BlockedSettings.new(@biz).message
        )
      end
    end

    context "owner is an organization" do
      context "a single setting is being change" do
        test "returns the organization-level message" do
          SecurityProductsEnablement::JobStatus.create({ id: SecurityAnalysisSettingsUpdateJob.job_id(@org, :advanced_security_enable_all) })

          assert_equal(
            "GitHub Advanced Security is being enabled. Some features under GitHub Advanced Security cannot be enabled or " \
            "disabled until changes are propagated to all repositories in this organization.",
            BlockedSettings.new(@org).message
          )
        end
      end

      context "multiple settings are being changed" do
        test "returns the organization-level message" do
          SecurityProductsEnablement::JobStatus.create({ id: SecurityAnalysisSettingsUpdateJob.job_id(@org, :auto_codeql_disable_all) })
          SecurityProductsEnablement::JobStatus.create({ id: SecurityAnalysisSettingsUpdateJob.job_id(@org, :secret_scanning_enable_all) })

          assert_equal(
            "Code scanning is being disabled and secret scanning is being enabled. Some features under GitHub " \
            "Advanced Security cannot be enabled or disabled until changes are propagated to all repositories in " \
            "this organization.",
            BlockedSettings.new(@org).message
          )
        end
      end

      context "a setting without a preface is being changed" do
        test "returns the organization-level message" do
          BlockedSettings.stub_const(:BLOCKING_SETTINGS, { some_random_setting: [:some_other_random_setting] }) do
            SecurityProductsEnablement::JobStatus.create({ id: SecurityAnalysisSettingsUpdateJob.job_id(@org, :some_random_setting) })

            assert_equal(
              "Some features under GitHub Advanced Security cannot be enabled or disabled until changes are propagated to " \
              "all repositories in this organization.",
              BlockedSettings.new(@org).message,
            )
          end
        end
      end
    end

    context "owner is a user" do
      context "a single setting is being change" do
        test "returns the user-level message" do
          SecurityProductsEnablement::JobStatus.create({ id: SecurityAnalysisSettingsUpdateJob.job_id(@user, :advanced_security_enable_all) })

          assert_equal(
            "GitHub Advanced Security is being enabled. Some features under GitHub Advanced Security cannot be enabled or " \
            "disabled until changes are propagated to all repositories owned by this user.",
            BlockedSettings.new(@user).message
          )
        end
      end

      context "multiple settings are being changed" do
        test "returns the user-level message" do
          SecurityProductsEnablement::JobStatus.create({ id: SecurityAnalysisSettingsUpdateJob.job_id(@user, :auto_codeql_disable_all) })
          SecurityProductsEnablement::JobStatus.create({ id: SecurityAnalysisSettingsUpdateJob.job_id(@user, :secret_scanning_enable_all) })

          assert_equal(
            "Code scanning is being disabled and secret scanning is being enabled. Some features under GitHub " \
            "Advanced Security cannot be enabled or disabled until changes are propagated to all repositories owned " \
            "by this user.",
            BlockedSettings.new(@user).message
          )
        end
      end
    end
  end

  context "#preface" do
    context "owner is a business" do
      test "returns the business-level preface" do
        SecurityProductsEnablement::JobStatus.create({ id: SecurityAnalysisSettingsUpdateJob.job_id(@org, :auto_codeql_disable_all) })

        assert_equal(
          "A change has been made to a configuration at either the enterprise or organization level.",
          BlockedSettings.new(@biz).preface
        )
      end
    end

    context "owner is an organization or user" do
      context "a single setting is being change" do
        test "returns the organization-level preface" do
          SecurityProductsEnablement::JobStatus.create({ id: SecurityAnalysisSettingsUpdateJob.job_id(@org, :auto_codeql_disable_all) })
          SecurityProductsEnablement::JobStatus.create({ id: SecurityAnalysisSettingsUpdateJob.job_id(@user, :auto_codeql_disable_all) })

          [@org, @user].each do |owner|
            assert_equal(
              "Code scanning is being disabled.",
              BlockedSettings.new(owner).preface
            )
          end
        end
      end

      context "multiple settings are being changed" do
        test "returns the organization-level preface" do
          SecurityProductsEnablement::JobStatus.create({ id: SecurityAnalysisSettingsUpdateJob.job_id(@org, :auto_codeql_disable_all) })
          SecurityProductsEnablement::JobStatus.create({ id: SecurityAnalysisSettingsUpdateJob.job_id(@org, :secret_scanning_enable_all) })

          SecurityProductsEnablement::JobStatus.create({ id: SecurityAnalysisSettingsUpdateJob.job_id(@user, :auto_codeql_disable_all) })
          SecurityProductsEnablement::JobStatus.create({ id: SecurityAnalysisSettingsUpdateJob.job_id(@user, :secret_scanning_enable_all) })

          [@org, @user].each do |owner|
            assert_equal(
              "Code scanning is being disabled and secret scanning is being enabled.",
              BlockedSettings.new(owner).preface
            )
          end
        end
      end
    end
  end

  context "#repo_message" do
    context "owner is an organization" do
      test "returns an organization-specific message" do
        assert_equal(
          "A change has been made to this configuration at the organization level. Some features under GitHub " \
          "Advanced Security cannot be enabled or disabled until changes are propagated to all repositories in this " \
          "organization.",
          BlockedSettings.new(@org).repo_message
        )
      end
    end

    context "owner is a user" do
      test "returns a user-specific message" do
        assert_equal(
          "A change has been made to this configuration at the user level. Some features under GitHub Advanced " \
          "Security cannot be enabled or disabled until changes are propagated to all repositories owned by this user.",
          BlockedSettings.new(@user).repo_message
        )
      end
    end
  end

  context "#repo_counter" do
    context "when owner is an Organization" do
      test "tracks count for a given update type" do
        update_type = :job_test_action
        repo_counter = BlockedSettings.new(@org).repo_counter
        assert_equal 1, repo_counter.increment(update_type)
        assert_equal 2, repo_counter.increment(update_type)
        assert_equal 1, repo_counter.decrement(update_type)
        assert_equal 0, repo_counter.decrement(update_type)
      end

      test "tracks different count per update type" do
        repo_counter = BlockedSettings.new(@org).repo_counter
        assert_equal 1, repo_counter.increment(:action_1)
        assert_equal 1, repo_counter.increment(:action_2)
        assert_equal 2, repo_counter.increment(:action_1)
        assert_equal 0, repo_counter.decrement(:action_2)
      end

      test "returns blocked when count is non-zero" do
        update_type = :job_test_action
        repo_counter = BlockedSettings.new(@org).repo_counter
        refute repo_counter.blocked?(update_type)

        assert_equal 1, repo_counter.increment(update_type)
        assert repo_counter.blocked?(update_type)

        assert_equal 2, repo_counter.increment(update_type)
        assert repo_counter.blocked?(update_type)

        assert_equal 1, repo_counter.decrement(update_type)
        assert repo_counter.blocked?(update_type)

        assert_equal 0, repo_counter.decrement(update_type)
        refute repo_counter.blocked?(update_type)
      end

      test "returns not blocked when kv entry doesn't exist", skip_enterprise: true do
        update_type = :job_test_action
        repo_counter = BlockedSettings.new(@org).repo_counter
        assert_equal 1, repo_counter.increment(update_type)

        # manually delete any/all keys that exist for this org
        SecurityProductsEnablement::KV.store.mdel_prefix("security_products:enablement_count:#{@biz.id}:#{@org.id}")

        refute repo_counter.blocked?(update_type)
      end
    end

    context "when owner is a Business" do
      test "returns blocked when count is non-zero", skip_enterprise: true do
        update_type = :job_test_action
        org_repo_counter = BlockedSettings.new(@org).repo_counter
        assert_equal 1, org_repo_counter.increment(update_type)
        assert org_repo_counter.blocked?(update_type)

        biz_repo_counter = BlockedSettings.new(@biz).repo_counter
        assert biz_repo_counter.blocked?(update_type)
      end

      test "returns not blocked when count is zero" do
        update_type = :job_test_action
        org_repo_counter = BlockedSettings.new(@org).repo_counter
        assert_equal 1, org_repo_counter.increment(update_type)
        assert_equal 0, org_repo_counter.decrement(update_type)
        refute org_repo_counter.blocked?(update_type)

        biz_repo_counter = BlockedSettings.new(@biz).repo_counter
        refute biz_repo_counter.blocked?(update_type)
      end

      test "returns not blocked when kv entry doesn't exist" do
        update_type = :job_test_action
        biz_repo_counter = BlockedSettings.new(@biz).repo_counter

        # manually delete any/all keys that exist for this business
        SecurityProductsEnablement::KV.store.mdel_prefix("security_products:enablement_count:#{@biz.id}")

        refute biz_repo_counter.blocked?(update_type)
      end
    end
  end

  context "#advanced_security?" do
    test "returns true if Advanced Security settings are blocked", skip_enterprise: true do
      [
        :advanced_security_enable_all,
        :advanced_security_disable_all,
        :auto_codeql_enable_all,
        :auto_codeql_enable_all_extended,
        :auto_codeql_disable_all,
        :secret_scanning_enable_all,
        :secret_scanning_disable_all,
        :secret_scanning_validity_checks_enable_all,
        :secret_scanning_validity_checks_disable_all,
        :secret_scanning_push_protection_enable_all,
        :secret_scanning_push_protection_disable_all
      ].each do |setting|
        SecurityProductsEnablement::JobStatus.create({ id: SecurityAnalysisSettingsUpdateJob.job_id(@org, setting) })
        SecurityProductsEnablement::JobStatus.create({ id: SecurityAnalysisSettingsUpdateJob.job_id(@user, setting) })

        [@biz, @org, @user].each do |owner|
          assert(BlockedSettings.new(owner).advanced_security?)
        end
      end
    end

    test "returns false if Advanced Security settings are not blocked" do
      [@biz, @org, @user].each do |owner|
        refute(BlockedSettings.new(owner).advanced_security?)
      end
    end
  end

  context "#advanced_security_user_namespace?" do
    test "returns true if Advanced Security settings are blocked", skip_enterprise: true do
      [
        :advanced_security_enable_all,
        :advanced_security_disable_all,
        :advanced_security_user_namespace_enable_all,
        :advanced_security_user_namespace_disable_all,
        :auto_codeql_enable_all,
        :auto_codeql_enable_all_extended,
        :auto_codeql_disable_all,
        :secret_scanning_enable_all,
        :secret_scanning_disable_all,
        :secret_scanning_validity_checks_enable_all,
        :secret_scanning_validity_checks_disable_all,
        :secret_scanning_push_protection_enable_all,
        :secret_scanning_push_protection_disable_all
      ].each do |setting|
        SecurityProductsEnablement::JobStatus.create({ id: SecurityAnalysisSettingsUpdateJob.job_id(@user, setting) })

        [@biz, @user].each do |owner|
          assert(BlockedSettings.new(owner).advanced_security_user_namespace?)
        end
      end
    end

    # This test can be removed when the feature flag is fully scaled up
    # because we'll want user level actions to block things upwards then
    test "never blocks biz level activity if feature is disabled for instance", enterprise_only: true do
      GitHub.stubs(:ghas_for_enterprise_users_enabled?).returns(false)

      [
        :advanced_security_enable_all,
        :advanced_security_disable_all,
        :advanced_security_user_namespace_enable_all,
        :advanced_security_user_namespace_disable_all,
        :auto_codeql_enable_all,
        :auto_codeql_enable_all_extended,
        :auto_codeql_disable_all,
        :secret_scanning_enable_all,
        :secret_scanning_disable_all,
        :secret_scanning_validity_checks_enable_all,
        :secret_scanning_validity_checks_disable_all,
        :secret_scanning_push_protection_enable_all,
        :secret_scanning_push_protection_disable_all
      ].each do |setting|
        SecurityProductsEnablement::JobStatus.create({ id: SecurityAnalysisSettingsUpdateJob.job_id(@user, setting) })
        refute(BlockedSettings.new(@biz).advanced_security_user_namespace?, "#{setting}")
      end
    end

    test "returns false if Advanced Security settings are not blocked" do
      [@biz, @user].each do |owner|
        refute(BlockedSettings.new(owner).advanced_security_user_namespace?)
      end
    end
  end

  context "#code_scanning?" do
    test "returns true if Code Scanning settings are blocked", skip_enterprise: true do
      [
        :advanced_security_enable_all,
        :advanced_security_disable_all,
        :auto_codeql_enable_all,
        :auto_codeql_enable_all_extended,
        :auto_codeql_disable_all
      ].each do |setting|
        SecurityProductsEnablement::JobStatus.create({ id: SecurityAnalysisSettingsUpdateJob.job_id(@org, setting) })
        SecurityProductsEnablement::JobStatus.create({ id: SecurityAnalysisSettingsUpdateJob.job_id(@user, setting) })

        [@biz, @org, @user].each do |owner|
          assert(BlockedSettings.new(owner).code_scanning?)
        end
      end
    end

    test "returns false if Code Scanning settings are not blocked" do
      [@biz, @org, @user].each do |owner|
        refute(BlockedSettings.new(owner).code_scanning?)

        [
          :secret_scanning_enable_all,
          :secret_scanning_disable_all,
          :secret_scanning_validity_checks_enable_all,
          :secret_scanning_validity_checks_disable_all,
          :secret_scanning_push_protection_enable_all,
          :secret_scanning_push_protection_disable_all
        ].each do |setting|
          SecurityProductsEnablement::JobStatus.create({ id: SecurityAnalysisSettingsUpdateJob.job_id(@org, setting) })
          SecurityProductsEnablement::JobStatus.create({ id: SecurityAnalysisSettingsUpdateJob.job_id(@user, setting) })

          refute(BlockedSettings.new(owner).code_scanning?)
        end
      end
    end
  end

  context "#secret_scanning?" do
    test "returns true if Secret Scanning settings are blocked", skip_enterprise: true do
      [
        :advanced_security_enable_all,
        :advanced_security_disable_all,
        :secret_scanning_enable_all,
        :secret_scanning_disable_all,
        :secret_scanning_validity_checks_enable_all,
        :secret_scanning_validity_checks_disable_all,
        :secret_scanning_push_protection_enable_all,
        :secret_scanning_push_protection_disable_all
      ].each do |setting|
        SecurityProductsEnablement::JobStatus.create({ id: SecurityAnalysisSettingsUpdateJob.job_id(@org, setting) })
        SecurityProductsEnablement::JobStatus.create({ id: SecurityAnalysisSettingsUpdateJob.job_id(@user, setting) })

        [@biz, @org, @user].each do |owner|
          assert(BlockedSettings.new(owner).secret_scanning?)
        end
      end
    end

    test "returns false if Secret Scanning settings are not blocked" do
      [@biz, @org, @user].each do |owner|
        refute(BlockedSettings.new(owner).secret_scanning?)

        [:auto_codeql_enable_all, :auto_codeql_enable_all_extended, :auto_codeql_disable_all].each do |setting|
          SecurityProductsEnablement::JobStatus.create({ id: SecurityAnalysisSettingsUpdateJob.job_id(@org, setting) })
          SecurityProductsEnablement::JobStatus.create({ id: SecurityAnalysisSettingsUpdateJob.job_id(@user, setting) })

          refute(BlockedSettings.new(owner).secret_scanning?)
        end
      end
    end
  end

  context "#validity_checks?" do
    test "returns true if Validity Checks settings are blocked", skip_enterprise: true do
      [
        :advanced_security_enable_all,
        :advanced_security_disable_all,
        :secret_scanning_enable_all,
        :secret_scanning_disable_all,
        :secret_scanning_validity_checks_enable_all,
        :secret_scanning_validity_checks_disable_all
      ].each do |setting|
        SecurityProductsEnablement::JobStatus.create({ id: SecurityAnalysisSettingsUpdateJob.job_id(@org, setting) })
        SecurityProductsEnablement::JobStatus.create({ id: SecurityAnalysisSettingsUpdateJob.job_id(@user, setting) })

        [@biz, @org, @user].each do |owner|
          assert(BlockedSettings.new(owner).validity_checks?)
        end
      end
    end

    test "returns false if Push Protection settings are not blocked" do
      [@biz, @org, @user].each do |owner|
        refute(BlockedSettings.new(owner).validity_checks?)

        [:auto_codeql_enable_all, :auto_codeql_disable_all].each do |setting|
          SecurityProductsEnablement::JobStatus.create({ id: SecurityAnalysisSettingsUpdateJob.job_id(@org, setting) })
          SecurityProductsEnablement::JobStatus.create({ id: SecurityAnalysisSettingsUpdateJob.job_id(@user, setting) })

          refute(BlockedSettings.new(owner).validity_checks?)
        end
      end
    end
  end

  context "#push_protection?" do
    test "returns true if Push Protection settings are blocked", skip_enterprise: true do
      [
        :advanced_security_enable_all,
        :advanced_security_disable_all,
        :secret_scanning_enable_all,
        :secret_scanning_disable_all,
        :secret_scanning_push_protection_enable_all,
        :secret_scanning_push_protection_disable_all
      ].each do |setting|
        SecurityProductsEnablement::JobStatus.create({ id: SecurityAnalysisSettingsUpdateJob.job_id(@org, setting) })
        SecurityProductsEnablement::JobStatus.create({ id: SecurityAnalysisSettingsUpdateJob.job_id(@user, setting) })

        [@biz, @org, @user].each do |owner|
          assert(BlockedSettings.new(owner).push_protection?)
        end
      end
    end

    test "returns false if Push Protection settings are not blocked" do
      [@biz, @org, @user].each do |owner|
        refute(BlockedSettings.new(owner).push_protection?)

        [:auto_codeql_enable_all, :auto_codeql_disable_all].each do |setting|
          SecurityProductsEnablement::JobStatus.create({ id: SecurityAnalysisSettingsUpdateJob.job_id(@org, setting) })
          SecurityProductsEnablement::JobStatus.create({ id: SecurityAnalysisSettingsUpdateJob.job_id(@user, setting) })

          refute(BlockedSettings.new(owner).push_protection?)
        end
      end
    end
  end
end

class ResilientBlockedSettingsTest < GitHub::TestCase
  include ResiliencyHelpers

  fixtures do
    @user = create(:user)
    @org = create(:organization)
    @biz = create(:business, organizations: [@org])
  end

  context "#blockers" do
    test "returns all blocking settings if kv is not available" do
      SecurityProductsEnablement::JobStatus.stubs(:find_prefix).raises(ActiveRecord::ActiveRecordError.new)
      assert_same_elements BlockedSettings::BLOCKING_SETTINGS.keys, ResilientBlockedSettings.new(@org).blockers
    end
  end
end
