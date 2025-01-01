# typed: true
# frozen_string_literal: true

require "test_helper"

class CodespacesDependencyTest < GitHub::TestCase
  include ResiliencyHelpers

  fixtures do
    GitHub.flipper[:codespaces_billing_free].disable
  end

  context "#has_existing_fork_of?(repository)" do
    test "is true when the user has a fork of the repository" do
      user = create(:user)
      repo = create(:repository)
      fork = create(:fork_repository, forker: user, fork_repo: repo)

      assert user.has_existing_fork_of?(repo)
    end

    test "is false when the user has no connection to the repository" do
      user = create(:user)
      repo = create(:repository)

      refute user.has_existing_fork_of?(repo)
    end

    test "is false when the user is the repository owner" do
      user = create(:user)
      repo = create(:repository, owner: user)

      refute user.has_existing_fork_of?(repo)
    end
  end

  context "#owned_billing_entries" do
    test "is zero when there are no billing entries" do
      assert_empty create(:user).owned_billing_entries
    end

    test "is one with a created codespace" do
      codespace = create(:codespace)
      assert_equal 1, codespace.owner.owned_billing_entries.count
    end

    test "includes codespaces since date" do
      user = create(:user)
      old_codespace = create(:codespace, created_at: 10.days.ago, owner: user)
      codespace = create(:codespace, owner: user, created_at: 1.day.ago)

      # with no since filter, this should return both of them
      assert_includes user.owned_billing_entries, old_codespace.billing_entry
      assert_includes user.owned_billing_entries, codespace.billing_entry

      refute_includes user.owned_billing_entries(since: 3.days.ago), old_codespace.billing_entry
      assert_includes user.owned_billing_entries(since: 3.days.ago), codespace.billing_entry
    end
  end

  context "#billed_billing_entries" do
    test "for users is zero when there are no billing entries" do
      user = create(:user)
      assert_empty user.billed_billing_entries
    end

    test "for orgs is zero when there are no billing entries" do
      org = create(:team_org)
      assert_empty org.billed_billing_entries
    end

    test "for users is one with a created codespace" do
      user = create(:user)
      create(:codespace, billable_owner: user, owner: user)
      assert_equal 1, user.billed_billing_entries.count
    end

    test "for orgs is one with a created codespace" do
      org = create(:team_org)
      create(:codespace, billable_owner: org)
      assert_equal 1, org.billed_billing_entries.count
    end

    test "for users includes codespaces since date" do
      user = create(:user)
      old_codespace = create(:codespace, billable_owner: user, owner: user, created_at: 10.days.ago)
      codespace = create(:codespace, billable_owner: user, owner: user, created_at: 1.day.ago)

      # with no since filter, this should return both of them
      assert_same_elements [codespace.billing_entry, old_codespace.billing_entry], user.billed_billing_entries
      assert_same_elements [codespace.billing_entry], user.billed_billing_entries(since: 3.days.ago)
    end

    test "for orgs includes codespaces since date" do
      org = create(:team_org)
      old_codespace = create(:codespace, billable_owner: org, created_at: 10.days.ago)
      codespace = create(:codespace, billable_owner: org, created_at: 1.day.ago)

      # with no since filter, this should return both of them
      assert_same_elements [codespace.billing_entry, old_codespace.billing_entry], org.billed_billing_entries
      assert_same_elements [codespace.billing_entry], org.billed_billing_entries(since: 3.days.ago)
    end
  end

  context ".owned_codespaces_count" do
    test "is zero when there are no billing entries" do
      assert_equal 0, User.owned_codespaces_count(create(:user))
    end

    test "is one with a created codespace" do
      codespace = create(:codespace)
      assert_equal 1, User.owned_codespaces_count(codespace.owner)
    end

    test "only counts unique" do
      codespace = create(:codespace)

      Codespaces::BillingEntry.create!(
        billable_owner: codespace.billable_owner,
        codespace_owner: codespace.owner,
        codespace_guid: codespace.guid,
        codespace_plan_name: codespace.plan&.name,
        codespace_created_at: codespace.created_at,
        repository: codespace.repository)

      assert_equal 1, User.owned_codespaces_count(codespace.owner)
    end

    test "is one with a deleted codespace" do
      codespace = create(:codespace)
      owner = codespace.owner
      codespace.destroy
      assert_equal 1, User.owned_codespaces_count(owner)
    end
  end

  context ".billed_codespaces_count" do
    test "is zero when there are no billing entries" do
      assert_equal 0, User.billed_codespaces_count(create(:user))
    end

    test "is one with a created codespace" do
      codespace = create(:codespace)
      assert_equal 1, User.billed_codespaces_count(codespace.billable_owner)
    end

    test "only counts unique" do
      codespace = create(:codespace)

      Codespaces::BillingEntry.create!(
        billable_owner: codespace.billable_owner,
        codespace_owner: codespace.owner,
        codespace_guid: codespace.guid,
        codespace_plan_name: codespace.plan&.name,
        codespace_created_at: codespace.created_at,
        repository: codespace.repository)

      assert_equal 1, User.billed_codespaces_count(codespace.owner)
    end

    test "is one with a deleted codespace" do
      codespace = create(:codespace)
      codespace.destroy
      assert_equal 1, User.billed_codespaces_count(codespace.owner)
    end
  end

  context ".codespaces_feature_enabled", skip_enterprise: true do

    context "User" do
      test "returns true for a User" do
        user = create(:user)
        assert user.codespaces_feature_enabled?
      end

      test "returns true for a collaborator when the org allows it" do
        team_org = create(:team_org)
        team_org.update_organization_codespaces_user_limit(Configurable::OrganizationCodespacesUserLimit::ALL_USERS_AND_OUTSIDE_COLLABORATORS, actor: team_org.owner)
        repo = create(:private_repository, owner: team_org)
        collaborator = create(:user)
        repo.add_member(collaborator)
        Codespaces::OrgPolicy.stubs(:allow_codespaces?).with(team_org).returns(true)

        assert collaborator.codespaces_feature_enabled?
      end
    end

    test "returns true for an organization that is part of an enterprise" do
      org = create(:enterprise_linked_organization)
      assert org.codespaces_feature_enabled?
    end

    test "returns true for a free organization with :codespaces_billing_free enabled" do
      free_org = create(:organization, plan: "free")
      GitHub.flipper[:codespaces_billing_free].enable(free_org)
      assert free_org.codespaces_feature_enabled?
    end

    test "returns true for organizations whose business has :codespaces_billing_free enabled" do
      org = create(:enterprise_linked_organization)
      GitHub.flipper[:codespaces_billing_free].enable(org.business)
      assert org.codespaces_feature_enabled?
    end

    test "returns false when Organization has a plan where :allow_codespaces option is set to false" do
      free_org = create(:organization, plan: "free")

      refute free_org.codespaces_feature_enabled?
    end

    test "returns false despite tiers if the org plan doesn't support it" do
      free_org = create(:organization, plan: "free")
      free_org.settings.set!(:trust_tier, "1")

      refute free_org.codespaces_feature_enabled?
    end

    test "returns false if the organization belongs to a suspended business" do
      org = create(:enterprise_linked_organization)
      org.business.suspend("Abusive behaviour")

      refute org.codespaces_feature_enabled?
    end

    test "(potentially incorrectly?) returns true if the organization belongs to a spammy business" do
      org = create(:enterprise_linked_organization)
      org.business.mark_as_spammy

      assert org.codespaces_feature_enabled?
    end

    test "returns false when a tier 2 or 3 org has an active GHEC enterprise trial" do
      org = create(:business_plus_org)
      create(:billing_plan_trial, :active, user: org)
      GitHub.flipper[:codespaces_allow_trials].disable(org)

      # force tier 2
      org.settings.set!(:trust_tier, "2")
      refute org.codespaces_feature_enabled?

      # force tier 3
      org.settings.set!(:trust_tier, "3")
      refute org.codespaces_feature_enabled?
    end

    test "returns true for a tier 1 org with an active GHEC enterprise trial" do
      org = create(:business_plus_org)
      create(:billing_plan_trial, :active, user: org)

      # force tier 1
      org.settings.set!(:trust_tier, "1")

      assert org.codespaces_feature_enabled?
    end

    test "return true when the codespaces_allow_trials FF is on to allow tier 2 & 3 orgs in GHEC trials" do
      GitHub.flipper[:codespaces_allow_trials].enable

      org = create(:business_plus_org)
      create(:billing_plan_trial, :active, user: org)

      # force tier 2
      org.settings.set!(:trust_tier, "2")
      assert org.codespaces_feature_enabled?

      # force tier 3
      org.settings.set!(:trust_tier, "3")
      assert org.codespaces_feature_enabled?
    end

    test "returns true when a tier 2 or 3 org is not on a GHEC trial, but is part of a trial EA" do
      GitHub.flipper[:codespaces_block_low_tier_ea_trials].disable

      business = create(:business, :with_self_serve_payment, trial_expires_at: 3.days.from_now)
      org = create(:business_plus_org, business: business)

      # force tier 2
      org.settings.set!(:trust_tier, "2")
      assert org.codespaces_feature_enabled?

      # force tier 3
      org.settings.set!(:trust_tier, "3")
      assert org.codespaces_feature_enabled?
    end

    test "return false when the FF is on to block tier 2 & 3 orgs moved into a trial EA" do
      GitHub.flipper[:codespaces_block_low_tier_ea_trials].enable

      business = create(:business, :with_self_serve_payment, trial_expires_at: 3.days.from_now)
      org = create(:business_plus_org, business: business)

      # force tier 2
      org.settings.set!(:trust_tier, "2")
      refute org.codespaces_feature_enabled?

      # force tier 3
      org.settings.set!(:trust_tier, "3")
      refute org.codespaces_feature_enabled?
    end

    test "returns true for a tier 1 org in a trial EA, regardless of FF" do
      GitHub.flipper[:codespaces_block_low_tier_ea_trials].enable

      business = create(:business, :with_self_serve_payment, trial_expires_at: 3.days.from_now)
      org = create(:business_plus_org, business: business)

      # force tier 1
      org.settings.set!(:trust_tier, "1")

      assert org.codespaces_feature_enabled?
    end

    test "returns false if the organization belongs to a business that has disabled codespaces" do
      org = create(:enterprise_linked_organization)
      Codespaces::BusinessDelegator.new(org.business).disable_codespaces!
      refute org.codespaces_feature_enabled?
    end

    test "returns true when a tier 2 or 3 org has an active GHEC enterprise trial, but billing cluster is down" do
      GitHub.flipper[:codespaces_billing_cluster_outage_fail_closed].disable
      org = create(:business_plus_org)
      create(:billing_plan_trial, :active, user: org)
      GitHub.flipper[:codespaces_allow_trials].disable(org)

      org.settings.set!(:trust_tier, "3")
      prevent_connections_to(ApplicationRecord::Billing) do
        assert org.codespaces_feature_enabled?
      end
    end

    test "returns false when a tier 2 or 3 org has an active GHEC enterprise trial, but billing cluster is down when flag is enabled" do
      GitHub.flipper[:codespaces_billing_cluster_outage_fail_closed].enable
      org = create(:business_plus_org)
      create(:billing_plan_trial, :active, user: org)
      GitHub.flipper[:codespaces_allow_trials].disable(org)

      org.settings.set!(:trust_tier, "3")
      prevent_connections_to(ApplicationRecord::Billing) do
        refute org.codespaces_feature_enabled?
      end
    end
  end
end
