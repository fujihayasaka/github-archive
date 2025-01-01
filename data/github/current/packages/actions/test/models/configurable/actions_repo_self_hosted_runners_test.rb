# typed: true
# frozen_string_literal: true

require "test_helper"

class Configurable::ActionsRepoSelfHostedRunnersTest < GitHub::TestCase
  include AuditLog::IntegrationTestHelpers

  fixtures do
    @admin = create(:user)
    @business = create(:business, :with_self_serve_payment, owners: [@admin])
    @org = create(:enterprise_linked_organization, admin: @admin, business: @business)
    @org_no_owner = create(:organization, admin: @admin)
    @repo = create(:repository, owner: @org)
    @repo_no_owner = create(:repository)

    unless GitHub.enterprise?
      @emu = create(:emu)
      @emu_business = @emu.enterprise_managed_business
      @emu_repo = create(:repository, owner: @emu)
    end
  end

  context "enterprise" do
    test "can be disabled" do
      refute @business.repo_self_hosted_runners_disabled?
      @business.disable_repo_self_hosted_runners(actor: @admin)
      assert @business.repo_self_hosted_runners_disabled?
    end

    test "can turn setting off for org and repo" do
      @business.disable_repo_self_hosted_runners(actor: @admin)
      assert @org.repo_self_hosted_runners_disabled_by_owner?
      assert @repo.repo_self_hosted_runners_disabled_by_owner?

      @business.enable_repo_self_hosted_runners(actor: @admin)

      @business.reload
      @org.reload
      @repo.reload

      refute @org.repo_self_hosted_runners_disabled_by_owner?
      refute @repo.repo_self_hosted_runners_disabled_by_owner?
    end
  end

  context "organization" do
    test "defaults to enabled for an org belonging to an enterprise" do
      refute @org.repo_self_hosted_runners_disabled_by_owner?
    end

    test "defaults to enabled for an org not belonging to an enterprise" do
      refute @org.repo_self_hosted_runners_disabled_by_owner?
    end

    test "is disabled if enterprise disabled repo-level self-hosted runners" do
      @business.disable_repo_self_hosted_runners(actor: @admin)
      assert @org.repo_self_hosted_runners_disabled?
      assert @org.repo_self_hosted_runners_disabled_by_owner?
    end
  end

  context "repository" do
    test "defaults to true for repo belonging to an enterprise owner" do
      refute @repo.repo_self_hosted_runners_disabled_by_owner?
    end

    test "defaults to true for repo not belonging to an enterprise owner" do
      refute @repo_no_owner.repo_self_hosted_runners_disabled_by_owner?
    end

    test "is disabled if enterprise disabled repo-level self-hosted runners" do
      @business.disable_repo_self_hosted_runners(actor: @admin)
      assert @repo.repo_self_hosted_runners_disabled_by_owner?
    end
  end

  context "#repo_self_hosted_runners_enabled_for_all_entities?" do
    test "returns true only if set to ALL_ENTITIES" do
      @business.disable_repo_self_hosted_runners(actor: @admin)
      refute @business.repo_self_hosted_runners_enabled_for_all_entities?

      @business.enable_repo_self_hosted_runners_for_selected_entities(actor: @admin)
      refute @business.repo_self_hosted_runners_enabled_for_all_entities?

      @business.enable_repo_self_hosted_runners(actor: @admin)
      assert @business.repo_self_hosted_runners_enabled_for_all_entities?
    end
  end

  context "#repo_self_hosted_runners_enabled_for_selected_entities?" do
    test "returns true only if set to ALL_ENTITIES" do
      @business.disable_repo_self_hosted_runners(actor: @admin)
      refute @business.repo_self_hosted_runners_enabled_for_selected_entities?

      @business.enable_repo_self_hosted_runners(actor: @admin)
      refute @business.repo_self_hosted_runners_enabled_for_selected_entities?

      @business.enable_repo_self_hosted_runners_for_selected_entities(actor: @admin)
      assert @business.repo_self_hosted_runners_enabled_for_selected_entities?
    end
  end

  context "#repo_self_hosted_runners_disabled_by_owner?" do
    context "enterprise" do
      test "returns false" do
        refute @business.repo_self_hosted_runners_disabled_by_owner?
      end
    end

    context "organization" do
      test "returns false if org isn't owned by a business" do
        refute @org_no_owner.repo_self_hosted_runners_disabled_by_owner?
      end

      test "returns false if business did not disable repo-level runners" do
        refute @org.repo_self_hosted_runners_disabled_by_owner?
      end

      test "returns true if business disabled repo-level runners" do
        @business.disable_repo_self_hosted_runners(actor: @admin)
        assert @org.repo_self_hosted_runners_disabled_by_owner?
      end
    end

    context "repository" do
      test "returns false if owner is not owned by a business" do
        refute @repo_no_owner.repo_self_hosted_runners_disabled_by_owner?
      end

      test "returns false if business did not disable repo-level runners" do
        refute @repo.repo_self_hosted_runners_disabled_by_owner?
      end

      test "returns true if business disabled repo-level runners" do
        @business.disable_repo_self_hosted_runners(actor: @admin)
        assert @repo.repo_self_hosted_runners_disabled_by_owner?
      end

      test "returns true if org disabled repo-level runners" do
        @org.disable_repo_self_hosted_runners(actor: @admin)
        assert @repo.repo_self_hosted_runners_disabled_by_owner?
      end

      test "returns true if org enabled repo-level for selected entities but not this repository" do
        @org.enable_repo_self_hosted_runners_for_selected_entities(actor: @admin)
        assert @repo.repo_self_hosted_runners_disabled_by_owner?
      end

      test "returns false if org enabled repo-level for selected entities including this repository" do
        @org.enable_repo_self_hosted_runners_for_selected_entities(actor: @admin)
        @repo.allow_repo_self_hosted_runners(actor: @admin)
        refute @repo.repo_self_hosted_runners_disabled_by_owner?
      end
    end
  end

  context "#repo_self_hosted_runners_allowed_entities" do
    context "enterprise" do
      test "returns the list of allowed orgs" do
        @business.enable_repo_self_hosted_runners_for_selected_entities(actor: @admin)

        entities = @business.repo_self_hosted_runners_allowed_entities
        assert entities.empty?

        @org.allow_repo_self_hosted_runners(actor: @admin)

        entities = @business.repo_self_hosted_runners_allowed_entities
        assert_equal 1, entities.length
        assert_equal @org.id, entities.first
      end
    end

    context "organization" do
      test "returns the list of allowed repos" do
        @org.enable_repo_self_hosted_runners_for_selected_entities(actor: @admin)
        entities = @org.repo_self_hosted_runners_allowed_entities
        assert entities.empty?

        @repo.allow_repo_self_hosted_runners(actor: @admin)

        entities = @org.repo_self_hosted_runners_allowed_entities
        assert_equal 1, entities.length
        assert_equal @repo.id, entities.first
      end
    end

    context "repository" do
      test "returns an empty list" do
        entities = @repo.repo_self_hosted_runners_allowed_entities
        assert entities.empty?
      end
    end
  end

  context "#repo_self_hosted_runners_allowed_by_owner?" do
    context "organization" do
      test "defaults to false" do
        refute @org.repo_self_hosted_runners_allowed_by_owner?
      end

      test "can be configured" do
        @org.allow_repo_self_hosted_runners(actor: @admin)
        assert @org.repo_self_hosted_runners_allowed_by_owner?

        @org.disallow_repo_self_hosted_runners(actor: @admin)
        refute @org.repo_self_hosted_runners_allowed_by_owner?
      end
    end

    context "repository" do
      test "defaults to false" do
        refute @repo.repo_self_hosted_runners_allowed_by_owner?
      end

      test "can be configured" do
        @repo.allow_repo_self_hosted_runners(actor: @admin)
        assert @repo.repo_self_hosted_runners_allowed_by_owner?

        @repo.disallow_repo_self_hosted_runners(actor: @admin)
        refute @repo.repo_self_hosted_runners_allowed_by_owner?
      end
    end
  end

  context "enterprise managed users", skip_enterprise: true do
    context "enterprise" do
      test "defaults to true" do
        assert @emu_business.repo_self_hosted_runners_enabled_for_emus?
        refute @emu_repo.repo_self_hosted_runners_disabled_by_owner?
      end

      test "can be configured" do
        @emu_business.disable_repo_self_hosted_runners_for_emus(actor: @admin)
        @emu_business.reload
        @emu_repo.reload
        refute @emu_business.repo_self_hosted_runners_enabled_for_emus?
        assert @emu_repo.repo_self_hosted_runners_disabled_by_owner?

        @emu_business.enable_repo_self_hosted_runners_for_emus(actor: @admin)
        @emu_business.reload
        @emu_repo.reload
        assert @emu_business.repo_self_hosted_runners_enabled_for_emus?
        refute @emu_repo.repo_self_hosted_runners_disabled_by_owner?
      end
    end

    test "returns false if is not an enterprise" do
      refute @org.repo_self_hosted_runners_enabled_for_emus?
      refute @repo.repo_self_hosted_runners_enabled_for_emus?
    end

    context "forked repository" do
      test "policy applies to forks too" do
        @emu_business.disable_repo_self_hosted_runners_for_emus(actor: @admin)
        @emu_business.allow_private_repository_forking(actor: @admin, policy: Configurable::AllowPrivateRepositoryForking::ENTERPRISE_ORGANIZATIONS_USER_ACCOUNTS)
        @emu_business.reload

        org = create(:enterprise_linked_organization, admin: @admin, business: @emu_business)
        org.allow_private_repository_forking(actor: @admin, policy: Configurable::AllowPrivateRepositoryForking::ENTERPRISE_ORGANIZATIONS_USER_ACCOUNTS)
        org.add_member(@emu)
        org.reload

        repo = create(:repository, :org_owned_internal, owner: org)

        # EMU policy should only apply to user-owned repos,
        # for organizations the policy has another setting
        refute repo.repo_self_hosted_runners_disabled_by_owner?

        fork_repo = create(:fork_repository, forker: @emu, fork_repo: repo)
        assert fork_repo.repo_self_hosted_runners_disabled_by_owner?
      end
    end
  end

  context "instrument repo runners policy" do
    test "when disabled" do
      [[@business, "business"], [@org, "org"]].each do |(model, type)|
        old_policy_expected = model.repo_self_hosted_runners_access
        events = assert_performed_audit_entries(count: 1, only: "#{type}.update_repo_self_hosted_runners_policy") do
          model.disable_repo_self_hosted_runners(actor: @admin)
        end

        expected_payload = {
          old_repo_runners_policy: old_policy_expected,
          new_repo_runners_policy: Configurable::ActionsRepoSelfHostedRunners::NO_ENTITIES,
          actor: @admin.login,
        }

        assert_subset_hash expected_payload, events.first
      end
    end

    test "when enabled" do
      [[@business, "business"], [@org, "org"]].each do |(model, type)|
        old_policy_expected = model.repo_self_hosted_runners_access
        events = assert_performed_audit_entries(count: 1, only: "#{type}.update_repo_self_hosted_runners_policy") do
          model.enable_repo_self_hosted_runners(actor: @admin)
        end

        expected_payload = {
          old_repo_runners_policy: old_policy_expected,
          new_repo_runners_policy: Configurable::ActionsRepoSelfHostedRunners::ALL_ENTITIES,
          actor: @admin.login,
        }

        assert_subset_hash expected_payload, events.first
      end
    end

    test "when selected" do
      [[@business, "business"], [@org, "org"]].each do |(model, type)|
        @business.enable_repo_self_hosted_runners(actor: @admin)
        old_policy_expected = model.repo_self_hosted_runners_access
        events = assert_performed_audit_entries(count: 1, only: "#{type}.update_repo_self_hosted_runners_policy") do
          model.enable_repo_self_hosted_runners_for_selected_entities(actor: @admin)
        end

        expected_payload = {
          old_repo_runners_policy: old_policy_expected,
          new_repo_runners_policy: Configurable::ActionsRepoSelfHostedRunners::SELECTED_ENTITIES,
          actor: @admin.login,
        }

        assert_subset_hash expected_payload, events.first
      end
    end

    context "enterprise managed users", skip_enterprise: true do
      test "when disabled" do
        old_policy_expected = @emu_business.repo_self_hosted_runners_enabled_for_emus?
        string_old_policy_expected = @emu_business.convert_emu_policy_to_string(old_policy_expected)
        events = assert_performed_audit_entries(count: 1, only: "business.update_emu_repo_self_hosted_runners_policy") do
          @emu_business.disable_repo_self_hosted_runners_for_emus(actor: @admin)
        end

        expected_payload = {
          old_emu_repo_runners_policy: string_old_policy_expected,
          new_emu_repo_runners_policy: Configurable::ActionsRepoSelfHostedRunners::NO_ENTITIES,
          actor: @admin.login,
        }

        assert_subset_hash expected_payload, events.first
      end

      test "when enabled" do
        old_policy_expected = @emu_business.repo_self_hosted_runners_enabled_for_emus?
        string_old_policy_expected = @emu_business.convert_emu_policy_to_string(old_policy_expected)
        events = assert_performed_audit_entries(count: 1, only: "business.update_emu_repo_self_hosted_runners_policy") do
          @emu_business.enable_repo_self_hosted_runners_for_emus(actor: @admin)
        end

        expected_payload = {
          old_emu_repo_runners_policy: string_old_policy_expected,
          new_emu_repo_runners_policy: Configurable::ActionsRepoSelfHostedRunners::ALL_ENTITIES,
          actor: @admin.login,
        }

        assert_subset_hash expected_payload, events.first
      end
    end
  end
end
