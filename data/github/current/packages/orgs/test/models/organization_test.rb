# encoding: utf-8
# typed: true
# frozen_string_literal: true

require "test_helper"

module OrganizationHelper
  def add_member_to_org(org, user, skip_perform_organization_orchestration_job: false, **args)
    T.bind(self, GitHub::TestCase)
    if GitHub.flipper[:add_org_member_bulk_refactor].enabled?
      if skip_perform_organization_orchestration_job
        org.bulk_add_members([user], **args)
      else
        perform_enqueued_jobs only: OrganizationOrchestrationJob do
          org.bulk_add_members([user], **args)
        end
      end
    else
      org.add_member(user, **args)
    end
  end
end

class OrganizationTest < GitHub::TestCase
  include GitHub::LoggerHelper
  include OrganizationHelper
  include HydroMessageJobTestHelpers

  fixtures do
    GitHub::Enterprise.ensure_business! if GitHub.single_business_environment?

    @rando          = create(:user)
    @org_admin      = create(:user, login: "org-admin")
    @org_member     = create(:user)
    @non_org_member = create(:user)
    perform_enqueued_jobs(only: [SyncOrganizationDefaultRepositoryPermissionJob]) { @org = create(:organization, admin: @org_admin, plan: "bronze", business: GitHub.global_business) }
    @team           = create :team, organization: @org, permission: "pull"
    @repo           = create :private_repository, owner: @org, has_discussions: true
    @repo_user      = create(:repository, owner: @rando)
    @pub_repo       = create(:repository, owner: @org)
    @pub_push_repo  = create :repository, owner: @org, public_push: true, name: "pub-push"
    @org_repo2      = create :repository, owner: @org, name: "other-org-repo"

    @team.add_repository @repo, :pull
    @team.add_repository @pub_repo, :pull
    @team.add_member @org_admin
    @team.add_member @org_member

    @parent_team = create(:team, organization: @org, privacy: :closed)
    @child_team = create(:team, organization: @org, privacy: :closed, parent_team_id: @parent_team.id)

    @org.allow_private_repository_forking(actor: @org.admins.first, policy: Configurable::AllowPrivateRepositoryForking::ENTERPRISE_ORGANIZATIONS_USER_ACCOUNTS)
    @org.publicize_member @org_member

    @repo2 = create :repository, :minimal, owner: @org_member

    @business = Business.first || create(:business)
    @business.seats = 100
    @business.save
    @business_billing_manager = create(:user)
    @business.billing.add_manager(@business_billing_manager, actor: @business.owners.first)

    @business_org = create(:organization, business: @business)
    @business_org.add_admin(@org_admin)
    @business_org_repo = create(:repository, :minimal, owner: @business_org)
    @business_org_repo_private = create(:private_repository, owner: @business_org)

    @org_discussion = create(:discussion, repository: @repo)

    perform_enqueued_jobs(only: [SyncOrganizationDefaultRepositoryPermissionJob]) { @internal_repo_org = create(:organization, admin: @org_admin, plan: "bronze", business: @business) }
    @internal_repo_org.update_default_repository_permission(:none, actor: @org_admin)

    @internal_repo = create(:internal_repository, owner: @internal_repo_org)

    business_org_admin = create(:user)
    business_org_user = create(:user)
    @business_org2 = create(:enterprise_linked_organization, business: @business, admin: business_org_admin)
    add_member_to_org(@business_org2, business_org_user)
    @business_org2_repo = create(:repository, :minimal, owner: @business_org2)

    # include some deleted repos which should not show up anywhere
    @deleted_pub_repo = create :repository, :minimal, owner: @org, name: "deleted-pub-repo"
    @deleted_priv_repo = create :private_repository, :minimal, owner: @org, name: "deleted-priv-repo"
    @team.add_repository @deleted_pub_repo, :pull
    @team.add_repository @deleted_priv_repo, :pull
    @deleted_pub_repo.remove(@org)
    @deleted_priv_repo.remove(@org)

    @soft_deleted_org = create :organization, admin: @org_admin, login: "soft-deleted-org"
    @soft_deleted_org.update!(deleted: true, deleted_at: 10.minutes.ago)
    @soft_deleted_org.create_soft_deleted_organization(
      organization: @soft_deleted_org,
      created_at: 10.minutes.ago
    )

    @business_soft_deleted_org = create :organization, business: @business, admin: @org_admin, login: "soft-deleted-business-org"
    @business_soft_deleted_org.update!(deleted: true, deleted_at: 10.minutes.ago)
    @business_soft_deleted_org.create_soft_deleted_organization(
      organization: @business_soft_deleted_org,
      created_at: 10.minutes.ago
    )
  end

  setup do
    GitHub.flipper[:discard_stratocaster_fanout].disable
  end

  context "#after_destroy" do
    test "business user accounts are removed after destroy", skip_enterprise: true do
      GitHub.flipper[:unaffiliated_user_accounts].disable
      GitHub.flipper[:enterprise_teams_migrate_from_cfb].disable
      # Business user accounts for business billing managers should not be removed
      add_member_to_org(@business_org2, @business_billing_manager)

      assert_difference("BusinessUserAccount.count", -2) do
        @business_org2.destroy
      end
    end

    test "business user accounts are not removed after destroy if unaffiliated user accounts are supported", skip_enterprise: true do
      GitHub.flipper[:unaffiliated_user_accounts].enable
      # Business user accounts for business billing managers should not be removed
      add_member_to_org(@business_org2, @business_billing_manager)

      assert_no_difference("BusinessUserAccount.count") do
        @business_org2.destroy
      end
    end
  end

  context "#remove_business_user_accounts_for_members?" do
    test "return false if single business environment", enterprise_only: true do
      refute_predicate @org, :remove_business_user_accounts_for_members?
    end

    test "return true if organization is not enterprise managed", skip_enterprise: true do
      assert_predicate @org, :remove_business_user_accounts_for_members?
    end
  end

  context "#parent_teams_search_for" do
    test "should return available parent team" do
      EnterpriseTeam.stubs(:enabled_for_organizations?).returns(true)

      org_owner = create :user
      new_org = create :organization, business: @business, admin: org_owner
      enterprise_team = create :enterprise_team, business: @business
      parent_team = create :team, name: "parent team", organization: new_org, privacy: :closed

      # Other team has a mapping and shouldn't be returned in response
      other_team = create :team, name: "other team", organization: new_org, privacy: :closed
      EnterpriseTeamOrganizationMapping.create(enterprise_team: enterprise_team, organization: new_org, team: other_team)

      result = new_org.parent_teams_search_for(nil, org_owner)

      expected_result = [parent_team]

      assert_equal expected_result, result
    end

    test "should not return any team if user is not a allowed to see it" do
      EnterpriseTeam.stubs(:enabled_for_organizations?).returns(true)

      non_member = create :user
      new_org = create :organization, business: @Business
      parent_team = create :team, name: "parent team", organization: new_org, privacy: :closed

      result = new_org.parent_teams_search_for(nil, non_member)

      assert_empty result
    end

    test "should return multiple available parent teams" do
      EnterpriseTeam.stubs(:enabled_for_organizations?).returns(true)

      org_owner = create :user
      new_org = create :organization, business: @business, admin: org_owner
      parent_team1 = create :team, name: "parent team 1", organization: new_org, privacy: :closed
      parent_team2 = create :team, name: "parent team 2", organization: new_org, privacy: :closed

      result = new_org.parent_teams_search_for(nil, org_owner)

      expected_result = [parent_team1, parent_team2]

      assert_equal expected_result, result.sort
    end

    test "should not return any team if there are no available parent teams" do
      EnterpriseTeam.stubs(:enabled_for_organizations?).returns(true)

      org_owner = create :user
      new_org = create :organization, business: @business, admin: org_owner
      other_team = create :team, name: "other team", organization: new_org, privacy: :closed
      enterprise_team = create :enterprise_team, business: @business
      EnterpriseTeamOrganizationMapping.create(enterprise_team: enterprise_team, organization: new_org, team: other_team)

      result = new_org.parent_teams_search_for(nil, org_owner)

      assert_empty result
    end

    test "should return teams that match the query by name" do
      EnterpriseTeam.stubs(:enabled_for_organizations?).returns(true)

      org_owner = create :user
      new_org = create :organization, business: @business, admin: org_owner
      matching_team = create :team, name: "unique", organization: new_org, privacy: :closed
      non_matching_team = create :team, name: "non matching team", organization: new_org, privacy: :closed

      result = new_org.parent_teams_search_for("unique", org_owner)

      expected_result = [matching_team]

      assert_equal expected_result, result
    end

    test "should not return any team if teams are all secret" do
      EnterpriseTeam.stubs(:enabled_for_organizations?).returns(true)

      owner = create :user
      new_org = create :organization, business: @Business, admin: owner
      parent_team = create :team, name: "parent team", organization: new_org, privacy: :secret

      result = new_org.parent_teams_search_for(nil, owner)

      assert_empty result
    end
  end

  context "#visible_discussions_for" do
    test "includes discussion in org repo when feature flag enabled" do
      result = @org.visible_discussions_for(@org_member)
      assert_equal [@org_discussion], result
    end

    test "omits discussion in repo user can't access" do
      assert_empty @org.visible_discussions_for(@non_org_member)
    end

    test "includes discussion in org repo when repo in feature flag" do
      result = @org.visible_discussions_for(@org_member)

      assert_equal [@org_discussion], result
    end
  end

  context "#fork_allowed?" do
    test "true for public repos" do
      pub_repo = create(:repository, :minimal)
      assert @org.fork_allowed?(repo: pub_repo, user: pub_repo.owner)
    end

    test "should return true for an intra-org fork" do
      priv_repo = create(:private_repository, owner: @org)
      assert @org.fork_allowed?(repo: priv_repo, user: priv_repo.owner)
    end

    test "should return true for an internal repo and an enterprise org" do
      assert @business_org.fork_allowed?(repo: @internal_repo, user: @internal_repo_org.admin)
    end

    test "should return false for an internal repo and an org outside of the enterprise" do
      random_org = create(:organization)
      random_org.add_admin(@internal_repo_org.admin)

      refute random_org.fork_allowed?(repo: @internal_repo, user: @internal_repo_org.admin)
    end

    test "should return true for a private repo into the same org with an enterprise policy that allows same org forks" do
      @business.allow_private_repository_forking(force: true, actor: @org_admin, policy: Configurable::AllowPrivateRepositoryForking::SAME_ORGANIZATION)

      assert @business_org.fork_allowed?(repo: @business_org_repo_private, user: @org_admin)
    end

    test "should return true for a private repo into an enterprise org with an enterprise policy that allows enterprise org forks" do
      @business.allow_private_repository_forking(force: true, actor: @org_admin, policy: Configurable::AllowPrivateRepositoryForking::ENTERPRISE_ORGANIZATIONS)

      assert @business_org.fork_allowed?(repo: @business_org_repo_private, user: @org_admin)
    end

    test "should return false for a private repo into an outside org with an enterprise policy that allows only enterprise org forks" do
      @business.allow_private_repository_forking(force: true, actor: @org_admin, policy: Configurable::AllowPrivateRepositoryForking::ENTERPRISE_ORGANIZATIONS)

      random_org = create :organization, admin: @org_admin

      refute random_org.fork_allowed?(repo: @business_org_repo_private, user: @org_admin)
    end

    test "should return true for a private repository into an outside org with an enterprise policy that allows forks to anywhere" do
      @business.allow_private_repository_forking(force: true, actor: @org_admin, policy: Configurable::AllowPrivateRepositoryForking::EVERYWHERE)

      random_org = create :organization, admin: @org_admin

      assert random_org.fork_allowed?(repo: @business_org_repo_private, user: @org_admin)
    end

    test "should return false for an internal repo into an outside org with an enterprise policy that allows forks to anywhere" do
      @business.allow_private_repository_forking(force: true, actor: @org_admin, policy: Configurable::AllowPrivateRepositoryForking::EVERYWHERE)

      random_org = create :organization, admin: @org_admin

      assert random_org.fork_allowed?(repo: @internal_repo_org, user: @org_admin)
    end

    test "should return false for a private repository into an outside org with an enterprise policy that allows forks to user accounts" do
      @business.allow_private_repository_forking(force: true, actor: @org_admin, policy: Configurable::AllowPrivateRepositoryForking::USER_ACCOUNTS)

      random_org = create :organization, admin: @org_admin

      refute random_org.fork_allowed?(repo: @business_org_repo_private, user: @org_admin)
    end

    test "should return false for a private repo into the same org with an enterprise policy that allows forks to user accounts" do
      @business.allow_private_repository_forking(force: true, actor: @org_admin, policy: Configurable::AllowPrivateRepositoryForking::USER_ACCOUNTS)

      refute @business_org.fork_allowed?(repo: @business_org_repo_private, user: @org_admin)
    end

    test "should return false for a private repo into an enterprise org with an enterprise policy that allows forks to user accounts" do
      @business.allow_private_repository_forking(force: true, actor: @org_admin, policy: Configurable::AllowPrivateRepositoryForking::USER_ACCOUNTS)

      refute @business_org.fork_allowed?(repo: @business_org_repo_private, user: @org_admin)
    end

    test "should return false for a private repository into an outside org with an enterprise policy that allows forks to same org and user accounts" do
      @business.allow_private_repository_forking(force: true, actor: @org_admin, policy: Configurable::AllowPrivateRepositoryForking::SAME_ORGANIZATION_USER_ACCOUNTS)

      random_org = create :organization, admin: @org_admin

      refute random_org.fork_allowed?(repo: @business_org_repo_private, user: @org_admin)
    end

    test "should return true for a private repo into the same org with an enterprise policy that allows forks to same org and user accounts" do
      @business.allow_private_repository_forking(force: true, actor: @org_admin, policy: Configurable::AllowPrivateRepositoryForking::SAME_ORGANIZATION_USER_ACCOUNTS)

      assert @business_org.fork_allowed?(repo: @business_org_repo_private, user: @org_admin)
    end

    test "should return false for a private repo into an enterprise org with an enterprise policy that allows forks to same org and user accounts" do
      second_business_org = create(:organization, admin: @org_admin, business: @business)

      @business.allow_private_repository_forking(force: true, actor: @org_admin, policy: Configurable::AllowPrivateRepositoryForking::SAME_ORGANIZATION_USER_ACCOUNTS)

      refute second_business_org.fork_allowed?(repo: @business_org_repo_private, user: @org_admin)
    end

    test "should return true for a private repo forked from a fork in a user account to an enterprise organization with the enterprise and users policy" do
      @business.allow_private_repository_forking(force: true, actor: @org_admin, policy: Configurable::AllowPrivateRepositoryForking::ENTERPRISE_ORGANIZATIONS_USER_ACCOUNTS)
      second_business_org = create(:organization, admin: @org_admin, business: @business)

      first_fork = create(:fork_repository, forker: @org_admin, fork_repo: @business_org_repo_private)

      assert first_fork

      assert second_business_org.fork_allowed?(repo: first_fork, user: @org_admin)
    end

    test "should return false for a private repo forked from a fork in a user account to an outside org with the enterprise and users policy" do
      outside_org = create(:organization, admin: @org_admin)

      @business.allow_private_repository_forking(force: true, actor: @org_admin, policy: Configurable::AllowPrivateRepositoryForking::ENTERPRISE_ORGANIZATIONS_USER_ACCOUNTS)
      second_business_org = create(:organization, admin: @org_admin, business: @business)

      first_fork = create(:fork_repository, forker: @org_admin, fork_repo: @business_org_repo_private)

      assert first_fork
      refute outside_org.fork_allowed?(repo: first_fork, user: @org_admin)
    end
  end

  context "#same_business_as_org?" do
    test "should return true if the orgs are in the same business" do
      assert @business_org.same_business_as_org?(@business_org2)
    end

    test "should return false if the orgs are in different businesses" do
      random_org = create(:organization)
      refute @business_org.same_business_as_org?(random_org)
    end
  end

  context "#same_org_as_repo?" do
    test "should return true if the repos is in the same org" do
      assert @business_org.same_org_as_repo?(@business_org_repo)
    end

    test "should return false if the repo have different owners" do
      # owner is a user
      refute @business_org.same_org_as_repo?(@repo)

      # owner is a different org
      refute @business_org.same_org_as_repo?(@business_org2_repo)
    end
  end

  context "#bulk_add_members" do
    test "adds non EMUs members with 2fa requirements met" do
      GitHub.flipper[:members_without_2fa_allowed].disable

      tfa_invitee1 = create(:two_factor_credential_user)
      tfa_invitee2 = create(:two_factor_credential_user)
      tfa_org = create(:two_factor_credential_org, business: nil)

      tfa_org.bulk_add_members([tfa_invitee1, tfa_invitee2])
      assert tfa_org.member?(tfa_invitee1)
      assert tfa_org.member?(tfa_invitee1)
    end

    test "does not invite EMU members that doesn't meet 2fa requirements" do
      GitHub.flipper[:organization_add_remove_orchestrator].enable
      GitHub.flipper[:members_without_2fa_allowed].disable

      non_tfa_invitee = create(:user)
      tfa_invitee = create(:two_factor_credential_user)
      tfa_org = create(:two_factor_credential_org, business: nil)

      tfa_org.bulk_add_members([non_tfa_invitee, tfa_invitee])

      refute tfa_org.member?(non_tfa_invitee)
      assert tfa_org.member?(tfa_invitee)
    end

    test "does nothing if at least one non EMU members doesn't meet 2fa requirements" do
      GitHub.flipper[:organization_add_remove_orchestrator].disable
      GitHub.flipper[:members_without_2fa_allowed].disable

      non_tfa_invitee = create(:user)
      tfa_invitee = create(:two_factor_credential_user)
      tfa_org = create(:two_factor_credential_org, business: nil)

      tfa_org.bulk_add_members([non_tfa_invitee, tfa_invitee])

      refute tfa_org.member?(non_tfa_invitee)
      refute tfa_org.member?(tfa_invitee)
    end
  end

  context "supports_internal_repositories?" do
    test "is true for org associated with an enterprise" do
      assert_predicate @internal_repo_org, :supports_internal_repositories?
    end

    test "is false for org not associated with an enterprise" do
      refute_predicate @org, :supports_internal_repositories?
    end unless GitHub.enterprise?
  end

  context "validation" do
    test "does not require email" do
      org = Organization.new(login: "ACME")
      org.valid?

      assert org.errors[:email].blank?
    end

    test "does not require password" do
      org = Organization.new
      org.valid?
      assert org.errors[:password].blank?
    end

    test "requires admins" do
      @org.admins.delete_all
      refute @org.save
      assert_includes @org.errors[:admins], "can't be blank"
    end

    test "can optionally skip requiring admins" do
      @org.admins.delete_all
      @org.skip_admins_presence_validation = true
      assert @org.save
      assert_empty @org.errors[:admins]
    end

    test "limits org's description to 160 characters" do
      @org.description = "a" * 161
      refute @org.valid?
      assert_equal "is too long (maximum is 160 characters)",
        @org.errors[:description].first
    end
  end

  test "#user? returns false" do
    refute_predicate @org, :user?
  end

  test "#organization? returns true" do
    assert_predicate @org, :organization?
  end

  test "#bot? returns false" do
    refute_predicate @org, :bot?
  end

  context "#active?" do
    test "returns false for soft-deleted org" do
      refute_predicate @soft_deleted_org, :active?
    end

    test "returns false for a deleted org" do
      org = Organization.new
      org.deleted = 1
      refute_predicate org, :active?
    end

    test "returns true for active org" do
      assert_predicate @org, :active?
    end
  end

  context "#last_ip" do
    test "returns the most recently updated org_admin's last_ip" do
      assert_equal [@org_admin], @org.admins
      assert_nil @org.last_ip

      expected_value = "192.168.1.1"
      @org_admin.update last_ip: expected_value

      refute_nil @org.last_ip
      assert_equal expected_value, @org.last_ip
    end

    test "returns nil if no admin exists to get last ip from" do
      assert_equal [@org_admin], @org.admins

      @org.admins.delete_all # simulate follower replication lag
      assert_empty @org.admins

      assert_nil @org.last_ip
    end
  end

  # These tests were updated to use assert_equal because of a bug that caused the third scenario to falsely pass.
  # deleted? was returning nil instead of false, which was causing the test to pass because nil is falsey.
  context "#deleted?" do
    test "returns false with a 0 value stored in deleted key" do
      org = Organization.new
      org.deleted = 0
      assert_equal org.deleted?, false
    end

    test "returns false when false stored in deleted key" do
      org = Organization.new
      org.deleted = false
      assert_equal org.deleted?, false
    end

    test "returns false when nil stored in deleted key" do
      org = Organization.new
      assert_equal org.deleted?, false
    end

    test "returns true when 1 stored in deleted key" do
      org = Organization.new
      org.deleted = 1
      assert_equal org.deleted?, true
    end

    test "returns true when true stored in deleted key" do
      org = Organization.new
      org.deleted = true
      assert_equal org.deleted?, true
    end
  end

  context "#soft_deleted?" do
    test "returns true for soft-deleted org" do
      assert_predicate @soft_deleted_org, :soft_deleted?
    end

    test "returns false for a deleted org" do
      org = Organization.new
      org.deleted = 1
      refute_predicate org, :soft_deleted?
    end

    test "returns false for an active org" do
      refute_predicate @org, :soft_deleted?
    end
  end

  context "#set_display_commenter_full_name_for_enterprise" do
    if GitHub.enterprise?
      test "enables flag for enterprise at org creation" do
        organization = create(:organization)
        assert organization.display_commenter_full_name_setting_enabled?
      end
    else
      test "flag disabled for non-enterprise org creation" do
        organization = create(:organization)
        refute organization.display_commenter_full_name_setting_enabled?
      end
    end
  end

  context "#populate_initial_user_labels" do
    test "creates user_labels for the org at org creation" do
      expected_labels = UserLabel.initial_labels

      assert_difference "UserLabel.count", expected_labels.count do
        @organization = create(:organization_with_user_labels)
      end

      expected_labels.each do |hash|
        label = @organization.user_labels.find_by(name: hash[:name])
        refute_nil label, "should have created label '#{hash[:name]}'"
        assert_equal hash[:color], label.color
        assert_equal hash[:description], label.description
      end
    end

    test "does not create duplicates or error if org labels have already been created" do
      assert_empty @org.user_labels

      @org.populate_initial_user_labels

      refute_empty @org.reload.user_labels

      assert_no_difference "@org.user_labels.count" do
        @org.populate_initial_user_labels
      end
    end

    test "logs an event for each label created" do
      events = subscribe "organization_default_label.create"
      expected_labels = UserLabel.initial_labels

      organization = create(:organization_with_user_labels)

      refute_empty organization.reload.user_labels, "should have created labels"
      refute_empty events, "should have created audit log events"
      refute_empty expected_labels # sanity check

      expected_labels.each do |label_data|
        label = organization.user_labels.find_by(name: label_data[:name])
        refute_nil label, "label '#{label_data[:name]}' should exist on organization"

        expected_payload = {
          org_id: organization.id,
          org: organization.login,
          organization_default_label_id: label.id,
          organization_default_label: label_data[:name]
        }

        label_event = events.map(&:payload).detect do |event_payload|
          event_payload == expected_payload
        end

        assert label_event,
          "no organization_default_label.create event with #{expected_payload} in #{events.inspect}"
      end
    end
  end

  test "an organization is billable?" do
    org = Organization.new
    assert org.billable?
  end

  test "supports company names containing emoji" do
    org = create(:organization, company_name: "\xF0\x9F\x98\x81")
    org.terms_of_service.update(type: "Corporate", actor: @org_admin)
    org.company_name = "\xF0\x9F\x98\x81"
    org.save

    assert_predicate org, :valid?
    assert_predicate org, :persisted?
    assert_predicate org.company, :valid?
    assert_predicate org.company, :persisted?
  end

  test "an organization cannot auth via basic auth" do
    refute @org.can_authenticate_via_basic_auth?
  end

  test "an organization cannot auth via username and password basic auth" do
    refute @org.can_authenticate_via_username_password_basic_auth?
  end

  test "an organization can own repositories" do
    assert_predicate @org, :can_own_repositories?
  end

  test "an organization requires transfer requests if the user cannot create repositories" do
    @org.disallow_members_can_create_repositories(actor: @org_admin)

    member = create(:user)
    add_member_to_org(@org, member, action: :read)

    assert @org.requires_transfer_requests_from?(member)
  end

  test "an organization requires transfer requests if the user is not in the org" do
    assert @org.requires_transfer_requests_from?(@non_org_member)
  end

  test "an organization does not require transfer requests if the user can create repositories" do
    refute @org.requires_transfer_requests_from?(@org_admin)
  end

  test "default setting values" do
    org = create(:organization)

    assert_predicate org, :members_can_create_repositories?
    assert_equal :read, org.default_repository_permission
  end

  test "can make an org without an explicit owner via Machinist" do
    org = create(:organization)
    org.reload
    assert org.valid?
    refute_nil org.admins.first
    assert org.admins.first.valid?
  end

  test "sets the company associated to the organization" do
    org = create :organization, company_name: "Primatech"
    company = Company.create!(name: "Primatech")
    org.company = company
    org.reload

    assert_equal "Primatech", org.company.name
  end

  test "does not create a new company record if it exists" do
    org = create :organization, company_name: "Primatech"

    assert_no_difference "Company.count" do
      create :organization, company_name: "Primatech"
    end
  end

  test "an organization with a company name can be saved multiple times" do
    org = create :organization, company_name: "Company Name"
    company = Company.create!(name: "Company Name")
    org.company = company

    2.times { org.save }
    assert Company.find_by(name: "Company Name")
  end

  test "instruments org.create" do
    events = subscribe "org.create"
    org = create(:organization, :with_instrumentation, admin: @org_admin, creator: @org_admin, plan: "bronze", company_name: "Primatech")

    expected_payload = {
      org: org.login,
      org_id: org.id,
      actor: @org_admin.login,
      actor_id: @org_admin.id,
      email: org.billing_email,
      plan: "bronze",
      tos_sha: TosAcceptance.current_sha,
    }

    assert event = events.pop, "expected an event"
    assert_equal expected_payload, event.payload
  end

  test "instruments org.update_member_repository_creation_permission prevent" do
    events = subscribe "org.update_member_repository_creation_permission"
    org = create(:organization)

    admin = org.admins.first
    org.disallow_members_can_create_repositories(actor: admin)
    expected_payload = {
      permission: false,
      visibility: "all",
      org: org.login,
      org_id: org.id,
      actor: admin.login,
      actor_id: admin.id,
    }

    assert event = events.pop, "expected an event"
    assert_equal expected_payload, event.payload
  end

  test "instruments org.update_member_repository_creation_permission allow" do
    events = subscribe "org.update_member_repository_creation_permission"
    org = create(:organization)

    admin = org.admins.first
    org.allow_members_can_create_repositories(force: true, actor: admin)
    expected_payload = {
      permission: true,
      visibility: "none",
      org: org.login,
      org_id: org.id,
      actor: admin.login,
      actor_id: admin.id,
    }

    assert event = events.pop, "expected an event"
    assert_equal expected_payload, event.payload
  end

  test "instruments org.update_member_repository_creation_permission disallow public repo creation" do
    events = subscribe "org.update_member_repository_creation_permission"
    org = create(:organization)

    admin = org.admins.first
    org.allow_members_can_create_repositories_with_visibilities(public_visibility: true, private_visibility: true, force: true, actor: admin)

    assert event = events.pop, "expected an event"
    assert_equal "internal", event.payload[:visibility]
  end

  test "cannot receive notifications" do
    refute @org.newsies_enabled?
  end

  test "should not authenticate organizations" do
    org = create(:organization, admin: @org_admin, plan: "bronze", password: GitHub.default_password)
    user, message = User.authenticate(org.login, GitHub.default_password)
    assert_nil user
  end

  if GitHub.public_push_enabled?
    test "only repository with public push has public push" do
      assert @pub_push_repo.public_push?
      assert !@pub_repo.public_push?
    end

    test "private repository cannot accept public_pushes regardless of flag from strangers" do
      owner = create(:user)
      org = create :organization, admin: owner
      priv = create :private_repository, :minimal, owner: org, public_push: true

      assert priv.pushable_by?(owner)
      assert !priv.pushable_by?(@non_org_member)
    end

    test "non-org-member can push to public push repo but not a public repo" do
      assert @pub_push_repo.pushable_by?(@non_org_member)
      assert !@pub_repo.pushable_by?(@non_org_member)
    end
  else
    test "non-org-member cannot push to public push repo" do
      refute @pub_push_repo.pushable_by?(@non_org_member)
    end
  end

  test "finds public organizations" do
    assert_equal [],     @org_admin.public_organizations
    assert_equal [@org], @org_member.public_organizations
  end

  test "does not find soft-deleted organizations", skip_enterprise: true do
    @org.soft_delete!

    assert_empty @org_member.public_organizations
  end

  test "doesn't want notifications" do
    assert  @org_admin.notifications?
    assert !@org.notifications?
  end

  test "can't reset its password" do
    assert_no_difference "ActionMailer::Base.deliveries.size" do
      @org.forgot_password
    end
  end

  test "can't use a Personal plan" do
    @org.plan = "medium"
    assert !@org.valid?
  end

  test "can use a hidden Org plan" do
    @org.plan = "diamond"
    assert @org.valid?
  end

  test "can't use a non existing plan" do
    @org.plan = "random_non_existing_plan"
    assert !@org.valid?
  end

  test "has teams" do
    assert_equal 3, @org.teams.size
  end

  test "has no members when initialized" do
    org = build :organization
    assert_equal [], org.people
  end

  test "has an accurate count of members" do
    team = create(:team, organization: @org)
    team.add_member @org_member

    assert_equal 2, @org.people.count
    assert_equal 2, @org.people.order("login").count
  end

  test "has team repos" do
    assert_same_elements [@repo, @pub_repo, @pub_push_repo, @org_repo2], @org.repositories
  end

  test "has admins" do
    org = create(:organization)
    assert org.admins.any?
  end

  test "has admin_ids" do
    org = create(:organization)
    assert org.admin_ids.any?
    assert_equal [org.admins.first.id], org.admin_ids
  end

  test "does not have an owners team" do
    org = create(:organization)
    assert_nil org.legacy_owners_team
  end

  test "is its own owner" do
    assert @org.adminable_by?(@org)
  end

  test "has an owner who can admin the owners" do
    assert @org.adminable_by?(@org_admin)
  end

  test "can have billing managed by an org admin" do
    assert @org.billing_manageable_by?(@org_admin)
    assert @org.async_billing_manageable_by?(@org_admin).sync
  end

  test "can have billing managed by a billing manager" do
    billing_manager = create(:user)
    @org.billing.add_manager(billing_manager, actor: @org_admin)

    assert @org.billing_manageable_by?(billing_manager)
    assert @org.async_billing_manageable_by?(billing_manager).sync
  end

  context "#billing_manager_only?" do
    test "false if the user is a admin of the org" do
      user = create(:user)
      @org.add_admin(user)
      assert @org.adminable_by?(user)
      refute @org.billing_manager_only?(user)
    end

    test "false if the user is a member of the org" do
      user = create(:user)
      add_member_to_org(@org, user)
      assert @org.member?(user)
      refute @org.billing_manager_only?(user)
    end

    test "true if the user is a billing manager for the organization" do
      billing_manager = create(:user)
      @org.billing.add_manager(billing_manager, actor: @org.admins.first)
      refute @org.member?(billing_manager)
      assert @org.billing_manager_only?(billing_manager)
    end
  end

  test "can't find a user" do
    assert_nil Organization.find_by_login(@org_admin.to_s)
  end

  test "can find a member with a case-insensitive search" do
    upcased_login = @org_admin.login.upcase

    refute_equal upcased_login, @org_admin.login
    assert_equal @org_admin, @org.find_team_member_by_login(upcased_login)
  end

  test "direct_member_ids returns a list of org members ids" do
    direct_member = create(:user)
    add_member_to_org(@org, direct_member)

    assert_same_elements [@org.admin.id, @org_member.id, direct_member.id], @org.direct_member_ids
  end

  context "#member_and_billing_manager_ids" do
    test "returns all members and billing managers" do
      direct_member = create(:user)
      add_member_to_org(@org, direct_member)

      billing_manager = create :user
      @org.billing.add_manager(billing_manager, actor: @org.admin)

      expected_results = [
        @org.admin.id,
        @org_member.id,
        direct_member.id,
        billing_manager.id,
      ]
      assert_same_elements expected_results, @org.member_and_billing_manager_ids
    end
  end

  test "can find an org member by login" do
    direct_member = create(:user)
    add_member_to_org(@org, direct_member)

    assert_equal direct_member, @org.find_direct_or_team_member_by_login(direct_member.login)
  end

  test "can find an organization" do
    assert_equal @org, Organization.find_by_login(@org.to_s)
  end

  test "knows who is and isn't associated" do
    assert !@org.direct_or_team_member?(create(:user))
    assert @org.direct_or_team_member?(@org_admin), "private members are members"
    assert @org.direct_or_team_member?(@org_member), "public members are members"
  end

  test "knows repos are in an org" do
    assert  @repo.in_organization?
    assert !@repo2.in_organization?

    forked_repo, reason = @pub_repo.fork(forker: @org_member)
    assert !forked_repo.in_organization?
  end

  test "can be found from a repo" do
    assert_equal @org, @repo.organization
  end

  test "can be found from a forked private repo" do
    forked, reason = @repo.fork(forker: @org_admin)
    RepositoryAddTeamsJob.perform_now(forked.id, @repo.id)

    assert_equal @org, forked.organization
    assert_equal 1,    forked.teams.count
  end

  test "can be found from a forked public repo" do
    forked, reason  = @pub_repo.fork(forker: @org_admin)
    assert_nil      forked.organization
    assert_equal 0, forked.teams.count
  end

  test "owners know which orgs they own" do
    assert_same_elements [@org, @business_org, @internal_repo_org], @org_admin.owned_organizations
    assert_equal [],     @non_org_member.owned_organizations
  end

  test "owners can't delete themselves" do
    @org_admin.destroy
    assert @org_admin.errors[:organizations].any?
    assert Organization.find_by(id: @org.id)
  end

  test "outbound email uses profile_email" do
    @org.profile_email = "test@example.com"
    @org.save!
    assert_equal "test@example.com", @org.profile_email
    assert_equal "test@example.com", @org.outbound_email
  end

  test "event_context returns serialized organization" do
    context = @org.event_context

    assert_equal @org.login, context[:org]
    assert_equal @org.id, context[:org_id]
  end

  test "instruments billing email change" do
    events    = subscribe "billing.change_email"
    old_email = @org.billing_email
    new_email = "new@example.com"

    @org.update! gravatar_email: new_email
    assert_nil events.pop, "an event was not expected"

    @org.update! billing_email: new_email
    assert event = events.pop, "event expected"
    assert_equal @org.id, event.payload[:org_id]
    assert_equal @org.login, event.payload[:org]
    assert_equal new_email, event.payload[:email]
    assert_equal old_email, event.payload[:old_email]
  end

  test "enables and disables members_can_change_repo_visibility" do
    user = create(:user)
    @org.add_admin(user)

    @org.allow_members_to_change_repo_visibility(actor: user)
    assert @org.members_can_change_repo_visibility?

    @org.block_members_from_changing_repo_visibility(actor: user)
    refute @org.members_can_change_repo_visibility?
  end

  if GitHub.single_business_environment?
    test "members_can_change_repo_visibility is false when block_members_from_changing_repo_visibility set to false (on the global business)" do
      user = create(:user)
      @org.add_admin(user)

      @org.allow_members_to_change_repo_visibility(actor: user)
      assert @org.members_can_change_repo_visibility?

      staff = create :staff_admin_user
      GitHub.global_business.block_members_from_changing_repo_visibility(force: true, actor: staff)

      refute @org.reload.members_can_change_repo_visibility?
    end
  end

  if GitHub.single_business_environment?
    test "members_can_delete_repositories is false when disallow_members_can_delete_repositories is set to true (globally)" do
      user = create(:user)
      @org.add_admin(user)

      @org.allow_members_can_delete_repositories(actor: user)
      assert @org.members_can_delete_repositories?

      staff = create :staff_admin_user
      GitHub.global_business.disallow_members_can_delete_repositories(force: true, actor: staff)
      refute @org.reload.members_can_delete_repositories?
    end
  end

  test "removes public membership when user is removed" do
    assert_equal 1, @org.public_members.size

    @org.remove_member! @org_member

    assert_equal 0, @org.reload.public_members.size
  end

  test "reset_public_members keeps public list in sync" do
    user = create(:user)
    @org.add_admin(user)
    @org.publicize_member user

    @org.remove_member! user
    @org.reset_public_members!

    refute @org.public_member? user
  end

  context "#remove_member!" do
    test "noops if the user is not a direct_or_team_member" do
      assert_nil @org.remove_member!(@non_org_member)
    end

    test "noops if the user is a pending_member" do
      invitation = create(:organization_invitation, organization: @org)
      assert_nil @org.remove_member!(invitation.invitee)
    end

    test "allows admins to remove members" do
      new_member = create(:user)
      org = create(:organization, admin: @org_admin)
      add_member_to_org(org, new_member)
      assert org.reload.members.include?(new_member)

      perform_enqueued_jobs(only: [RevokeOrgMembershipAbilitiesJob]) do
        org.remove_member!(new_member)
      end
      refute org.reload.members.include?(new_member)
    end

    test "unlinks billing info if linked admin is removed from the org" do
      new_admin = create(:user, :with_trade_screening_record)
      org = create(:organization, admin: @org_admin)
      org.add_admin(new_admin)
      assert org.reload.members.include?(new_admin)
      new_admin.link_trade_screening_record_to_org(organization: org)

      org.remove_member!(new_admin)
      refute org.reload.members.include?(new_admin)
      refute_predicate org, :has_linked_trade_screening_record?
    end

    test "doesn't unlink billing info if admin is removed from the org and doesn't own the linked billing info" do
      new_admin = create(:user, :with_trade_screening_record)
      org = create(:organization, admin: @org_admin)
      org.add_admin(new_admin)
      assert org.reload.members.include?(new_admin)
      new_admin.link_trade_screening_record_to_org(organization: org)

      org.remove_member!(@org_admin)
      refute org.reload.members.include?(@org_admin)
      assert_predicate org, :has_linked_trade_screening_record?
    end

    test "unlinks billing info if linked admin role changes to member" do
      new_admin = create(:user, :with_trade_screening_record)
      org = create(:organization, admin: @org_admin)
      org.add_admin(new_admin)
      assert org.reload.members.include?(new_admin)
      new_admin.link_trade_screening_record_to_org(organization: org)

      org.update_member(new_admin, action: :read)
      assert org.reload.members.include?(new_admin)
      refute_predicate org, :has_linked_trade_screening_record?
    end

    test "doesn't unlink billing info if admin role changes to member and doesn't own the linked billing info" do
      new_admin = create(:user, :with_trade_screening_record)
      org = create(:organization, admin: @org_admin)
      org.add_admin(new_admin)
      assert org.reload.members.include?(new_admin)
      new_admin.link_trade_screening_record_to_org(organization: org)

      org.update_member(@org_admin, action: :read)
      assert org.reload.members.include?(@org_admin)
      assert_predicate org, :has_linked_trade_screening_record?
    end

    test "removes memex access when user is removed from the org" do
      org = create(:organization, admin: @org_admin)
      user = create(:user)

      add_member_to_org(org, user)
      org_memex = create(:memex_project, :with_writer, writer: user, owner: org)
      another_memex = create(:memex_project, :with_writer, writer: user)

      assert_equal 2, user.user_roles.length

      perform_enqueued_jobs(only: [RemoveOrgMemberProjectsNextAccessJob]) do
        org.remove_member!(user)
      end

      assert_equal 1, user.user_roles.reload.length
      assert_equal another_memex.id, user.user_roles[0].target_id
    end

    test "query count is reduced for business orgs when using the remove_unaffiliated_users_from_business feature flag", skip_enterprise: true do
      GitHub.flipper[:org_remove_member_cleanup_in_bulk_test_only].disable # Disabling to reduce complexity of this test.
      GitHub.flipper[:business_use_organization_outside_collaborator_ids].disable
      GitHub.flipper[:collaborator_cache_write].disable
      GitHub.flipper[:collaborator_cache_read].disable
      user = create(:user)

      orgs = []
      10.times do
        org = create(:organization, admin: @org_admin, business: @business)
        add_member_to_org(org, user)
        orgs << org
      end

      feature_enabled = @business.feature_enabled?(:remove_unaffiliated_users_from_business)

      replica_clusters_and_counts = {
        ApplicationRecord::Mysql1 => feature_enabled ? 0 : 136,
        ApplicationRecord::IamAbilities => feature_enabled ? 42 : 307,
      }

      assert_query_count_against_replicas(clusters_and_counts: replica_clusters_and_counts) do
        orgs.each do |org|
          org.remove_member!(user)
        end
        BusinessUserAccountUpdateAttributesJob.perform_now(business_id: @business.id)
      end
    end

    test "instruments removal" do
      events = subscribe "org.remove_member"
      new_admin = create(:user)
      org = create(:organization, admin: @org_admin)
      org.add_admin(new_admin)
      assert org.reload.admins.include?(new_admin)

      org.remove_member!(new_admin)
      assert event = events.pop, "expected an event"
    end

    test "removes custom email routing" do
      new_member = create(:user)
      org = create(:organization, admin: @org_admin)
      add_member_to_org(org, new_member)
      assert org.reload.members.include?(new_member)

      GitHub.newsies.get_and_update_settings(new_member) do |settings|
        settings.email org, "org@email.com"
      end

      assert_equal GitHub.newsies.settings(new_member).email(org).address, "org@email.com"

      org.remove_member!(new_member)

      refute_equal GitHub.newsies.settings(new_member).email(org).address, "org@email.com"
    end

    test "allows admins to remove other admins" do
      new_admin = create(:user)
      org = create(:organization, admin: @org_admin)
      org.add_admin(new_admin)
      assert org.reload.admins.include?(new_admin)

      org.remove_member!(new_admin)
      assert_same_elements [@org_admin], org.reload.admins
    end

    test "when user is the last admin, it raises" do
      GitHub.flipper[:org_remove_member_cleanup_in_bulk_test_only].disable # This feature does not support safety checks
      assert_raises ::Organization::NoAdminsError do
        @org.remove_member!(@org_admin)
      end
    end

    test "removes OrganizationRole assignments when member is removed" do
      org = create(:business_plus_organization)
      custom_org_role = custom_org_role = OrganizationRole.create!(name: "custom_org_role", owner: org, owner_type: "Organization")

      user = create(:user)
      add_member_to_org(org, user)

      result = Permissions::Granters::RoleGranter.new(actor: user, target: org, role: custom_org_role).grant!
      assert_equal true, result.success?
      user_role = UserRole.find_by(role_id: custom_org_role.id, actor_id: user.id)
      refute_nil user_role

      perform_enqueued_jobs(only: [RemoveOrgMemberJob, RevokeOrgMembershipAbilitiesJob]) do
        org.remove_member(user)
      end

      assert_nil UserRole.find_by(role_id: custom_org_role.id, actor_id: user.id)
    end

    test "throws when attempting to remove ET managed user `remove_member`" do
      GitHub.flipper[:org_remove_member_cleanup_in_bulk_test_only].disable # This feature does not support safety checks
      EnterpriseTeam.stubs(:enabled_for_organizations?).returns(true)

      user = create :user
      et = create :enterprise_team, business: @business
      org = create :organization, business: @business
      team = create :team, organization: org

      team.add_member(user)

      # Force creation of OrgMembershipEntry
      ability = Ability.user_direct_read_on_organization(actor_id: user.id, subject_id: org.id).pluck(:id)
      OrganizationMembershipEntry.create_entry(user: user, organization_id: org.id, ability_id: ability.first, derived: true, adder_id: team.id, adder_type: :enterprise_team)

      # should throw the error
      assert_raises(Organization::UnableToRemoveEnterpriseTeamMemberError) do
        org.remove_member(user)
      end
    end

    test "throws when attempting to remove ET managed user `remove_member!`" do
      GitHub.flipper[:org_remove_member_cleanup_in_bulk_test_only].disable # This feature does not support safety checks
      EnterpriseTeam.stubs(:enabled_for_organizations?).returns(true)

      user = create :user
      et = create :enterprise_team, business: @business
      org = create :organization, business: @business
      team = create :team, organization: org

      team.add_member(user)

      # Force creation of OrgMembershipEntry
      ability = Ability.user_direct_read_on_organization(actor_id: user.id, subject_id: org.id).pluck(:id)
      OrganizationMembershipEntry.create_entry(user: user, organization_id: org.id, ability_id: ability.first, derived: true, adder_id: team.id, adder_type: :enterprise_team)

      # should throw the error
      assert_raises(Organization::UnableToRemoveEnterpriseTeamMemberError) do
        org.remove_member!(user)
      end
    end

    test "Removes the org membership entries when provided adder_type" do
      EnterpriseTeam.stubs(:enabled_for_organizations?).returns(true)

      user = create :user
      et = create :enterprise_team, business: @business
      org = create :organization, business: @business
      team = create :team, organization: org

      team.add_member(user)

      # Force creation of OrgMembershipEntry
      ability = Ability.user_direct_read_on_organization(actor_id: user.id, subject_id: org.id).pluck(:id)
      OrganizationMembershipEntry.create_entry(user: user, organization_id: org.id, ability_id: ability.first, derived: true, adder_id: team.id, adder_type: :enterprise_team)

      ability_id = Ability.user_direct_read_on_organization(actor_id: user.id, subject_id: org.id).pluck(:id)
      assert OrganizationMembershipEntry.enterprise_team_managed?(user: user, organization_id: org.id, ability_id: ability_id)

      org.remove_organization_membership_entry_with_adder_type(user: user, derived: true, adder_type: :enterprise_team, adder_id: team.id)

      refute OrganizationMembershipEntry.enterprise_team_managed?(user: user, organization_id: org.id, ability_id: ability_id)
    end

    test "no-ops if kill switch is enabled for the org", skip_enterprise: true do
      GitHub.flipper[:bypass_heavy_workloads].enable(@org)
      assert @org.reload.members.include?(@org_member)

      perform_enqueued_jobs(only: [RevokeOrgMembershipAbilitiesJob]) do
        @org.remove_member!(@org_member)
      end
      assert @org.reload.members.include?(@org_member)
    end unless TestEnv.test_all_features?

    test "no-ops if kill switch is enabled for the orgs business", skip_enterprise: true do
      business = create(:business, organizations: [@org])
      @org.reload
      GitHub.flipper[:bypass_heavy_workloads].enable(business)

      perform_enqueued_jobs(only: [RevokeOrgMembershipAbilitiesJob]) do
        @org.remove_member!(@org_member)
      end
      assert @org.reload.members.include?(@org_member)
    end unless TestEnv.test_all_features?
  end

  context "#prevent_removal_of_last_admin!" do
    test "noops if the user is not the last admin" do
      new_member = create(:user)
      add_member_to_org(@org, new_member)
      assert @org.reload.members.include?(new_member)

      assert_nil @org.prevent_removal_of_last_admin!(new_member, "just don't")
    end

    test "raises and logs if user is the last org admin" do
      expected = {
        ns: "Organization#prevent_removal_of_last_admin!",
        msg: "prevent_removal_of_last_admin!",
        org: @org,
        org_id: @org.id,
        user: @org_admin,
        user_id: @org_admin.id,
      }

      assert_raises Organization::NoAdminsError do
        assert_logged **expected do
          @org.prevent_removal_of_last_admin!(@org_admin, "just don't")
        end
      end
    end
  end

  if GitHub.enterprise?
    test "can be created when there are no seats left" do
      GitHub::Enterprise.license_reset!
      GitHub::Enterprise.license.stubs(:reached_seat_limit?).returns(true)
      GitHub::Enterprise.license.stubs(:seats_available).returns(0)
      assert GitHub::Enterprise.license.reached_seat_limit?, "should have reached the seat limit"
      assert GitHub::Enterprise.license.seats_available.zero?, "should have zero seats"
      assert_difference "Organization.count" do
        create(:organization, admin: @org_admin)
      end
    end
  end

  context "#create_team" do
    test "creates a new team with the given repos" do
      ActionMailer::Base.deliveries.clear

      team = assert_difference("Team.count", 1) do
        @org.create_team(
          creator: @org_admin,
          repos: [@repo, @org_repo2],
          attrs: { name: "test team" },
        )
      end

      assert_same_elements [@repo, @org_repo2], team.batched_repositories
    end

    test "returns an invalid team if there is an error" do
      team = assert_no_difference "Team.count" do
        @org.create_team(creator: @org_admin, attrs: { name: "" })
      end
      refute team.valid?
    end

    test "does not allow repos from other orgs to be added to a team" do
      assert_difference("Team.count", 1) do
        team = @org.create_team(
          creator: @org_admin,
          repos: [@internal_repo], # repo belongs to a differnt org
          attrs: { name: "test team" },
        )

        assert_empty team.batched_repositories
      end
    end

    test "does not allow unauthorized repos to be added to a team" do
      assert_difference("Team.count", 1) do
        team = @org.create_team(
          creator: @org_member,
          repos: [@repo, @org_repo2], # org_member cannot admin these repos
          attrs: { name: "test team" },
        )

        assert_empty team.batched_repositories
      end
    end

    test "allow apps to add repos to a team with the right permissions" do
      GitHub.flipper[:team_creation_with_repo_admin_check].enable

      installation = make_integration_installation(target: @org, permissions: {
        "administration" => :write,
        "members" => :write,
      })

      team = assert_difference("Team.count", 1) do
        @org.create_team(
          creator: installation,
          repos: [@repo, @org_repo2],
          attrs: { name: "test team" },
        )
      end

      assert_same_elements [@repo, @org_repo2], team.batched_repositories
    end

    test "does not allow unauthorized repos to be added to a team (github app version)" do
      GitHub.flipper[:team_creation_with_repo_admin_check].enable

      installation = make_integration_installation(target: @org, permissions: {
        "members" => :write,
      })

      assert_difference("Team.count", 1) do
        team = @org.create_team(
          creator: installation,
          repos: [@repo, @org_repo2], # installation cannot admin these repos
          attrs: { name: "test team" },
        )

        assert_empty team.batched_repositories
      end
    end
  end

  test "#adminable_by? returns false if nil user" do
    refute @org.adminable_by? nil
  end

  test "#adminable_by? returns true for members of the owners team" do
    assert @org.adminable_by? @org_admin
  end

  test "#adminable_by? returns false for non-owner org members" do
    refute @org.adminable_by? @org_member
  end

  context "visible_repositories_for" do
    test "doesn't return private repos to non-org-members" do
      refute @org.visible_repositories_for(@non_org_member).include?(@repo)
    end

    test "returns private repos to org members with pull access" do
      assert @org.visible_repositories_for(@org_member).include?(@repo)
    end

    test "returns only public repos to anonymous users" do
      repos = @org.visible_repositories_for(nil)

      assert repos.all?(&:public?)
      assert repos.include?(@pub_repo)
      refute repos.include?(@repo)
    end

    test "does not return internal repos to people outside of the business" do
      repos = @internal_repo_org.reload.visible_repositories_for(nil)
      refute repos.include?(@internal_repo)
    end

    test "returns internal repos to business members by default" do
      add_member_to_org(@internal_repo_org, @rando, action: :read)

      repos = @internal_repo_org.reload.visible_repositories_for(@rando)
      assert repos.include?(@internal_repo)
    end

    test "fetches internal repositories to business members when esm_enabled", enterprise_only: true do
      GitHub.stubs(:esm_enabled?).returns(true)

      add_member_to_org(@internal_repo_org, @rando, action: :read)

      repos = @internal_repo_org.reload.visible_repositories_for(@rando)
      assert repos.include?(@internal_repo)
    end

    test "does not return internal repos to business members flagged as contributors by default" do
      add_member_to_org(@internal_repo_org, @rando, action: :read)

      EnterpriseAttestation.stubs(contractor?: true)
      repos = @internal_repo_org.reload.visible_repositories_for(@rando)
      refute repos.include?(@internal_repo)
    end

    test "returns internal repos to business members flagged as contributors who have direct access" do
      @internal_repo.add_member(@rando)

      EnterpriseAttestation.stubs(contractor?: true)
      repos = @internal_repo_org.reload.visible_repositories_for(@rando)
      assert repos.include?(@internal_repo)
    end

    test "returns internal repo if user is an admin of the business" do
      @business.add_owner(@rando, actor: nil)

      repos = @internal_repo_org.reload.visible_repositories_for(@rando)

      assert repos.include?(@internal_repo)
    end

    test "returns internal repo if user is a billing manager of a business and also a member of a org owned by the business", skip_enterprise: true do
      GitHub.flipper[:bus_ids_exclude_billing_manager_valid_license].enable
      @business_org.add_member(@business_billing_manager)
      repos = @internal_repo_org.reload.visible_repositories_for(@business_billing_manager)

      assert repos.include?(@internal_repo)
    end

    test "does not return internal repo if user is only a billing manager of a business and not a member of an org", skip_enterprise: true do
      GitHub.flipper[:bus_ids_exclude_billing_manager_valid_license].enable
      repos = @internal_repo_org.reload.visible_repositories_for(@business_billing_manager)

      refute repos.include?(@internal_repo)
    end

    test "returns internal repo if user is a member of the organization" do
      add_member_to_org(@internal_repo_org, @rando)

      repos = @internal_repo_org.reload.visible_repositories_for(@rando)

      assert repos.include?(@internal_repo)
    end

    test "returns internal repo if user is a member of a different organization in the same business" do
      org2 = nil
      org2 = create(:organization, admin: @org_admin, plan: "bronze")
      @business.add_organization(org2)

      add_member_to_org(org2, @rando)
      repos = @internal_repo_org.reload.visible_repositories_for(@rando)

      assert repos.include?(@internal_repo)
    end
  end

  context "#bulk_update_privacy" do
    test "sets visibility to closed for many teams" do
      teams = []
      teams << create(:team, organization: @org, permission: "pull")
      teams << create(:team, organization: @org, permission: "pull")
      closed_team_ids = teams.map(&:id)

      @org.bulk_update_privacy(closed_team_ids, :closed)
      closed_teams = @org.teams.closed.where(id: closed_team_ids)

      assert_equal 2, closed_teams.size
    end

    test "sets visibility to secret for many teams" do
      teams = []
      teams << create(:team, organization: @org, permission: "pull")
      teams << create(:team, organization: @org, permission: "pull")
      secret_team_ids = teams.map(&:id)

      @org.bulk_update_privacy(secret_team_ids, :secret)
      secret_teams = @org.teams.secret.where(id: secret_team_ids)

      assert_equal 2, secret_teams.size
    end
  end

  context "repositories_associated_with" do
    test "returns all of the org's repositories for admins" do
      repos = @org.repositories_associated_with(@org_admin)
      assert_same_elements [@repo, @pub_repo, @pub_push_repo, @org_repo2], repos
    end

    test "returns repositories on a team member's teams" do
      only = [DeleteDependentAbilitiesJob, RemoveForksForInaccessibleRepositoriesJob, SyncOrganizationDefaultRepositoryPermissionJob]
      perform_enqueued_jobs(only: only) { @org.update_default_repository_permission(:none, actor: @org_admin) }
      repos = @org.repositories_associated_with(@org_member)

      assert_same_elements [@repo, @pub_repo], repos
    end

    test "includes direct collaborator repositories for org members" do
      only = [DeleteDependentAbilitiesJob, RemoveForksForInaccessibleRepositoriesJob, SyncOrganizationDefaultRepositoryPermissionJob]
      perform_enqueued_jobs(only: only) { @org.update_default_repository_permission(:none, actor: @org_admin) }

      @pub_push_repo.add_member(@org_member)

      repos = @org.repositories_associated_with(@org_member)
      assert_same_elements [@repo, @pub_repo, @pub_push_repo], repos
    end

    test "includes direct collaborator repositories for non-members" do
      @repo.add_member(@non_org_member)

      repos = @org.repositories_associated_with(@non_org_member)
      assert_same_elements [@repo], repos
    end

    test "excludes private forks of repositories owned by orgs that the user is an owner of" do
      GitHub.flipper[:bypass_oopfs_query].disable
      GitHub.flipper[:bypass_oopfs_query_org].disable

      org = T.let(nil, T.nilable(Organization))
      foreign_org = T.let(nil, T.nilable(Organization))
      perform_enqueued_jobs(only: [SyncOrganizationDefaultRepositoryPermissionJob]) do
        org = create(:organization)
        org.allow_members_can_create_repositories(actor: org.admin)
        org.update_default_repository_permission(:none, actor: org.admin)

        foreign_org = create(:organization)
        foreign_org.allow_private_repository_forking(actor: foreign_org.admins.first)
      end

      foreign_repo = create(:private_repository, owner: foreign_org)
      foreign_user = create(:user, login: "foreign-user")
      forker       = create(:user, login: "forker")
      T.must(foreign_org).add_admin(foreign_user)
      T.must(foreign_org).add_admin(forker)

      add_member_to_org(org, foreign_user)
      add_member_to_org(org, forker)
      oopf = create(:fork_repository, forker: forker, fork_repo: foreign_repo, organization: org)

      assert_includes foreign_user.associated_repository_ids, oopf.id
      refute_includes T.must(org).repositories_associated_with(foreign_user), oopf

      GitHub.flipper[:bypass_oopfs_query].enable
      foreign_user.reload
      refute_includes foreign_user.associated_repository_ids, oopf.id
    end

    test "returns an empty list for unaffiliated users" do
      repos = @org.repositories_associated_with(@non_org_member)
      assert_empty repos
    end

    test "returns an empty list for a nil user" do
      repos = @org.repositories_associated_with(nil)
      assert_empty repos
    end
  end

  context "private_repositories" do
    test "returns all of the org's private repositories" do
      repos = @org.private_repositories
      assert_same_elements [@repo], repos
    end
  end

  test "billing_email must be unicode 3" do
    funny_character = [0x1F514].pack("U")
    funny_address   = "#{funny_character}blah@example.com"

    @org.billing_email = funny_address

    assert !@org.valid?
    assert_includes @org.errors[:billing_email], "doesn't accept 4-byte Unicode"
  end

  test "billing_email cannot be sanctioned" do
    @org.billing_email = "test-user@justice.ir"

    assert !@org.valid?
    assert_equal 1, @org.errors[:billing_email].count
    assert_includes @org.errors[:billing_email].first, "cannot add test-user@justice.ir - may be for an entity restricted under U.S. trade controls"
  end

  test "billing_email cannot be a disposable email" do
    GitHub.stubs(prevent_disposable_email_verification?: true) # Make sure test also works for enterprise
    @org.billing_email = "test-user@mailinator.com"

    assert !@org.valid?
    assert_equal 1, @org.errors[:billing_email].count
    assert_equal @org.errors[:billing_email].first, "cannot add test-user@mailinator.com - domain could not be verified"
  end

  test "sets the enterprise cloud trial for business plus after adding a member" do
    new_member = create(:user)
    add_member_to_org(@org, new_member)

    refute_equal :enterprise_cloud_trial, GlobalNoticeNext.new(viewer: new_member).current_notice_name

    business_plus_org = create(:organization, plan: GitHub::Plan.business_plus)
    perform_enqueued_jobs(only: [OrganizationOrchestrationJob, EnterpriseCloudTrialNoticeForNewMembersJob]) do
      add_member_to_org(business_plus_org, new_member, skip_perform_organization_orchestration_job: true)
    end

    assert_equal :enterprise_cloud_trial, GlobalNoticeNext.new(viewer: new_member.reload).current_notice_name
  end

  context "#pending_members" do
    test "includes users who have non-accepted, non-cancelled invitations to the organization" do
      accepted  = @org.invite(create(:user), inviter: @org_admin).accept
      cancelled = @org.invite(create(:user), inviter: @org_admin).cancel(actor: @org_admin)
      pending   = @org.invite(create(:user), inviter: @org_admin)

      assert_equal [pending.invitee], @org.pending_members
    end
  end

  # Looking for Organization#invite related tests? Try
  # test/models/organization/invitations_dependency_test.rb

  context "pending_invitations" do
    test "contains only non-accepted, non-cancelled invitations for the organization" do
      accepted  = @org.invite(create(:user), inviter: @org_admin).accept
      cancelled = @org.invite(create(:user), inviter: @org_admin).cancel(actor: @org_admin)
      pending   = @org.invite(create(:user), inviter: @org_admin)

      assert_same_elements [pending], @org.pending_invitations
    end
  end

  context "pending_invitation_for" do
    test "returns the user's pending invitation scoped by invitee" do
      invitee    = create(:user, login: "invitee")
      invitation = @org.invite(invitee, inviter: @org_admin, teams: [@team])

      assert_equal invitation, @org.pending_invitation_for(invitee)
    end

    test "returns the user's pending invitation scoped by email" do
      email = "garrett@github.com"
      invitation = @org.invite(email: email, inviter: @org_admin, teams: [@team])

      assert_equal invitation, @org.pending_invitation_for(email: email)
    end

    test "returns pending invitations for an equivalent normalized email address" do
      invitation = @org.invite(email:  "john.smith@gmail.com", inviter: @org_admin, teams: [@team])

      assert_equal invitation, @org.pending_invitation_for(email: "JohnSmith@gmail.com")
    end

    test "returns pending invitations based on either invitee or email address" do
      invitee = create(:user, login: "invitee")
      invitee.emails.build(email: "invitee@example.com")
      invitation = @org.invite(email: "invitee@example.com", inviter: @org_admin, teams: [@team])

      assert_equal invitation, @org.pending_invitation_for(invitee, email: "invitee@example.com")
    end

    test "returns pending invitations based on all verified emails for a user" do
      invitee = create(:user, login: "invitee")
      invitee.emails << create(:user_email, :verified, email: "verified@example.com")
      refute_equal invitee.email, "verified@example.com" # should not be the default/primary email address

      invitation = @org.invite(email: "verified@example.com", inviter: @org_admin, teams: [@team])

      assert_equal invitation, @org.pending_invitation_for(invitee, email: "verified@example.com")
    end

    test "does not return an invitation for an unverified user email address" do
      invitee = create(:user, login: "invitee")
      invitee.emails.delete_all
      invitee.emails << create(:user_email, :verified, email: "verified@example.com")
      invitee.emails << create(:user_email, email: "unverified@example.com")

      assert_same_elements ["unverified@example.com"], invitee.emails.unverified.map(&:email)

      invitation = @org.invite(email: "unverified@example.com", inviter: @org_admin, teams: [@team])

      assert_nil @org.pending_invitation_for(invitee)
    end

    test "does not return invite for private email if include_private_emails is false" do
      user = create(:user)
      user.emails.delete_all

      user.add_email("verified-private@example.com", is_primary: true)
      user.primary_user_email.verify!
      user.primary_user_email.toggle_visibility
      refute user.primary_user_email.public?

      @org.invite(email: "verified-private@example.com", inviter: @org.admin)

      assert_nil @org.pending_invitation_for(user, include_private_emails: false)
    end

    test "does not return invite for private emails by default" do
      user = create(:user)
      user.emails.delete_all

      user.add_email("verified-private@example.com", is_primary: true)
      user.primary_user_email.verify!
      user.primary_user_email.toggle_visibility
      refute user.primary_user_email.public?

      invite = @org.invite(email: "verified-private@example.com", inviter: @org.admin)

      assert_equal invite, @org.pending_invitation_for(user)
    end

    test "is nil when there are no invitations for the user" do
      assert_nil @org.pending_invitation_for(create(:user, login: "uninvited"))
    end

    test "is nil when invitee or email is not provided" do
      invitee    = create(:user, login: "invitee")
      @org.invite(invitee, inviter: @org_admin, role: :direct_member)

      assert_nil @org.pending_invitation_for(invitee = nil, email: nil)
    end

    test "is nil when all invitations for the user have been accepted" do
      invitee = create(:user, login: "invitee")
      @org.invite(invitee, inviter: @org_admin, teams: [@team]).accept

      assert_nil @org.pending_invitation_for(invitee)
    end

    test "limits to invitations with a specified role" do
      invitee    = create(:user, login: "invitee")
      invitation = @org.invite(invitee, inviter: @org_admin, role: :admin)

      assert_equal invitation, @org.pending_invitation_for(invitee, role: :admin)
    end

    test "returns nil when there are no invitations with a specified role" do
      invitee    = create(:user, login: "invitee")
      @org.invite(invitee, inviter: @org_admin, role: :direct_member)

      assert_nil @org.pending_invitation_for(invitee, role: :admin)
    end

    test "given an email and no User, returns nil if the email is invalid" do
      invitee = "name-email.com"

      invites = @org.pending_invitation_for(email: invitee, role: :admin)

      assert_nil invites
    end

    test "given an INVITEE and no email, returns nil if not a User" do
      invites = @org.pending_invitation_for("name@email.com", role: :admin)

      assert_nil invites
    end
  end

  context "invited_admins" do
    test "returns all the users with owner invitations" do
      admin_invitees = Array.new(2) do |i|
        invitee = create(:user, login: "admin-invitee-#{i}")
        @org.invite(invitee, inviter: @org_admin, role: :admin)
        invitee
      end

      @org.invite(create(:user, login: "direct-member-invitee"), inviter: @org_admin, role: :direct_member)

      assert_same_elements admin_invitees, @org.invited_admins
    end
  end

  context "has_seat_for?" do
    test "true if a user has pending private repository invitations" do
      org = create(:organization, seats: 5, plan: "business")
      3.times { add_member_to_org(org, create(:user)) }
      repo = create(:private_repository, :minimal, owner: org)
      user = create(:user)
      create(:repository_invitation, repository: repo, invitee: user)

      # Does not have seat for a user without pending invitation
      refute org.has_seat_for?(create(:user))
      assert org.has_seat_for?(user)
    end

    test "true if a user has a pending invitation" do
      org = create(:organization, plan: "business", seats: 5)
      3.times { add_member_to_org(org, create(:user)) }
      invitee = create(:user, login: "invitee")
      invitation = org.invite(invitee, inviter: org.admins.first, teams: [create(:team, organization: org)])

      assert org.has_seat_for? invitee
      refute org.has_seat_for? create(:user)
    end

    test "false if a user has a pending email invitation" do
      org = create(:organization, plan: "business", seats: 5)
      3.times { add_member_to_org(org, create(:user)) }
      invitee = create(:user, login: "invitee")
      invitee.emails.first.update_attribute(:state, "verified")
      invitation = org.invite(nil, email: invitee.email, inviter: org.admins.first)

      assert_equal invitation, org.pending_invitation_for(invitee)
      refute org.has_seat_for? invitee
    end

    test "true if there are seats available" do
      org = create(:organization, plan: "business", seats: 5)
      assert org.has_seat_for? create(:user)
    end

    test "true if at seat limit but user is already a member" do
      user = create(:user)
      org = create(:organization, plan: "business", seats: 5, admin: user)
      4.times { add_member_to_org(org, create(:user)) }
      add_member_to_org(org, user)
      assert org.has_seat_for? user
    end

    test "true if at seat limit but user is already an outside collaborator on a private repository" do
      user = create(:user)
      org = create(:organization, plan: "business", seats: 5, admin: create(:user))
      repo = create(:repository, :minimal, owner: org, public: 0)
      3.times { repo.add_member(create(:user)) }
      repo.add_member(user)

      assert org.at_seat_limit?
      assert org.has_seat_for? user
    end

    test "true if on a per-repository plan" do
      assert @org.has_seat_for? create(:user)
    end

    test "true if at seat limit but org is on 100% coupon" do
      org = create(:organization, plan: "business", seats: 5)
      org.redeem_coupon create(:coupon, discount: 1)

      refute org.at_seat_limit?
      assert org.has_seat_for? create(:user)
    end

    test "false if no pending invitation and no seats left" do
      org = create(:organization, plan: "business", seats: 5)
      4.times { add_member_to_org(org, create(:user)) }
      refute org.has_seat_for? create(:user)
    end

    if !GitHub.single_business_environment?
      test "true if user is member of another organization in the business" do
        business = create(:business, seats: 2)
        user = create(:user)
        org = create(:organization, business: business)
        other_org = create(:organization, business: business)

        add_member_to_org(org, user)
        perform_enqueued_jobs only: BusinessUpdateLicenseUsageJob

        business.reload
        org.reload
        other_org.reload

        assert org.at_seat_limit?
        assert other_org.at_seat_limit?
        assert other_org.has_seat_for? user
      end

      test "false if a user has a pending email invitation in the business" do
        business = create(:business, seats: 3)
        org = create(:organization, business: business)
        other_org = create(:organization, business: business)
        invitee = create(:user, login: "invitee")
        invitee.emails.first.update_attribute(:state, "verified")

        inviter = OrganizationInviter.new(
          org,
          actor: org.admins.first,
          email: invitee.email,
        )
        assert inviter.invite_user
        perform_enqueued_jobs only: BusinessUpdateLicenseUsageJob

        business.reload
        org.reload
        other_org.reload

        assert org.at_seat_limit?
        assert other_org.at_seat_limit?
        refute other_org.has_seat_for? invitee
      end
    end
  end

  context "has_seat_for?(pending_cycle: true)" do
    test "true if there is no pending change & current plan has available seats" do
      org = create(:organization, plan: "business", seats: 6)
      4.times { add_member_to_org(org, create(:user)) }

      assert org.has_seat_for? create(:user), pending_cycle: true
    end

    test "false if no pending invite and no seats left past pending cycle seat amount" do
      org = create(:organization, plan: "business", seats: 6)
      4.times { add_member_to_org(org, create(:user)) }

      create :billing_pending_plan_change,
        user: org,
        actor: org,
        seats: 5

      refute org.has_seat_for? create(:user), pending_cycle: true
    end

    test "true if pending downgrade to free plan" do
      org = create(:organization, plan: "business", seats: 6)
      4.times { add_member_to_org(org, create(:user)) }

      create :billing_pending_plan_change,
        user: org,
        actor: org,
        plan: "free"

      assert org.has_seat_for? create(:user), pending_cycle: true
    end

    test "true if at seat limit but user is already a member" do
      user = create(:user)
      org = create(:organization, plan: "business", seats: 6, admin: user)
      5.times { add_member_to_org(org, create(:user)) }

      create :billing_pending_plan_change,
        user: org,
        actor: org,
        seats: 5

      assert org.has_seat_for? user, pending_cycle: true
    end

    test "true if a user has pending private repository invitations" do
      org = create(:organization, seats: 6, plan: "business")
      3.times { add_member_to_org(org, create(:user)) }
      repo = create(:private_repository, :minimal, owner: org)
      user = create(:user)
      create(:repository_invitation, repository: repo, invitee: user)

      create :billing_pending_plan_change,
        user: org,
        actor: org,
        seats: 5

      # Does not have seat for a user without pending invitation
      refute org.has_seat_for? create(:user), pending_cycle: true
      assert org.has_seat_for? user, pending_cycle: true
    end

    test "true if a user has a pending invitation" do
      org = create(:organization, plan: "business", seats: 6)
      3.times { add_member_to_org(org, create(:user)) }
      invitee = create(:user, login: "invitee")
      org.invite(invitee, inviter: org.admins.first, teams: [create(:team, organization: org)])

      create :billing_pending_plan_change,
        user: org,
        actor: org,
        seats: 5

      assert org.has_seat_for? invitee, pending_cycle: true
      refute org.has_seat_for? create(:user), pending_cycle: true
    end

    test "false if a user has a pending email invitation" do
      org = create(:organization, plan: "business", seats: 6)
      3.times { add_member_to_org(org, create(:user)) }
      invitee = create(:user, login: "invitee")
      invitee.emails.first.update_attribute(:state, "verified")
      invitation = org.invite(nil, email: invitee.email, inviter: org.admins.first)
      create :billing_pending_plan_change,
        user: org,
        actor: org,
        seats: 5

      assert_equal invitation, org.pending_invitation_for(invitee)
      refute org.has_seat_for? invitee, pending_cycle: true
    end

    test "true if at seat limit but user is already an outside collaborator on a private repository" do
      user = create(:user)
      org = create(:organization, plan: "business", seats: 6, admin: create(:user))
      repo = create(:repository, :minimal, owner: org, public: 0)
      3.times { repo.add_member(create(:user)) }
      repo.add_member(user)

      create :billing_pending_plan_change,
        user: org,
        actor: org,
        seats: 5

      refute org.at_seat_limit?
      assert org.at_seat_limit? pending_cycle: true
      assert org.has_seat_for? user, pending_cycle: true
    end

    test "true if on a per-repository plan" do
      org = create(:organization, plan: "gold")
      4.times { add_member_to_org(org, create(:user)) }

      create :billing_pending_plan_change,
        user: org,
        actor: org,
        plan: "bronze"

      assert org.has_seat_for? create(:user), pending_cycle: true
    end

    test "true if at seat limit but org is on 100% coupon" do
      org = create(:organization, plan: "business", seats: 6)
      4.times { add_member_to_org(org, create(:user)) }
      org.redeem_coupon create(:coupon, discount: 1)

      create :billing_pending_plan_change,
        user: org,
        actor: org,
        seats: 5

      refute org.at_seat_limit?(pending_cycle: true)
      assert org.has_seat_for? create(:user), pending_cycle: true
    end
  end

  context "S4 error handling" do
    test "#has_s4_stats? returns false" do
      S4::V1::Client.any_instance.stubs(:count).raises(S4::V1::Client::ResponseError.new(Twirp::Error.internal("whoops")))
      refute @org.has_s4_stats?
    end

    test "#s4_usage_metrics returns empty metrics hash" do
      S4::V1::Client.any_instance.stubs(:filtered_metrics).raises(S4::V1::Client::ResponseError.new(Twirp::Error.internal("whoops")))
      assert_equal(GitHub::Connect::S4::ERROR_METRICS_RESPONSE, @org.s4_usage_metrics)
    end
  end

  context "membership_state_of" do
    test "is :pending when the user is invited" do
      invitee = create(:user, login: "invitee")
      @org.invite(invitee, inviter: @org.admins.first, teams: [create(:team, organization: @org)])

      assert_equal :pending, @org.membership_state_of(invitee)
    end

    test "is :active when the user is an org member" do
      member = create(:user, login: "member")
      add_member_to_org(@org, member)

      assert_equal :active, @org.membership_state_of(member)
    end

    test "is :inactive when the user is unaffiliated with the organization" do
      assert_equal :inactive, @org.membership_state_of(create(:user))
    end
  end

  context "outside_collaborators" do
    test "returns users who have access to org repos but aren't org members" do
      @repo.add_member(@non_org_member)

      assert_same_elements [@non_org_member], @org.outside_collaborators
    end

    # Regression test for #47102
    test "does not return users who are not associated with the org's repos" do
      @repo2.add_member @non_org_member
      assert_same_elements [], @org.outside_collaborators
    end

    # Regression test for #47102
    test "does not return users with access to inactive repositories" do
      @repo.add_member @non_org_member
      if GitHub.flipper[:collaborator_cache_read].enabled?
        perform_enqueued_jobs only: [OrganizationCollaboratorBackfillJob, RepositoryOrchestrationJob] do
          perform_enqueued_hydro_jobs only: [HydroOrganizationCollaboratorUpdateOnRepoChangeJob] do
            @repo.remove(@owner)
          end
        end
      else
        perform_enqueued_jobs only: OrganizationCollaboratorBackfillJob do
          @repo.update active: nil
        end
      end
      assert_same_elements [], @org.outside_collaborators
    end

    test "returns only one instance of each user" do
      @repo.add_member(@non_org_member)
      create(:repository, :minimal, owner: @org).add_member(@non_org_member)

      assert_same_elements [@non_org_member], @org.outside_collaborators
    end

    test "excludes org members who have repo access through a team" do
      add_member_to_org(@org, @org_member)
      @team.add_member(@org_member)
      @repo.add_member(@non_org_member)

      assert_same_elements [@non_org_member], @org.outside_collaborators
    end

    test "excludes org members who have direct repo access" do
      add_member_to_org(@org, @org_member)
      @repo.add_member(@org_member)
      @repo.add_member(@non_org_member)

      assert_same_elements [@non_org_member], @org.outside_collaborators
    end

    test "excludes fork members" do
      add_member_to_org(@org, @org_member)
      @repo.add_member(@org_member)
      @repo.add_member(@non_org_member)
      forked = create(:fork_repository, forker: @non_org_member, fork_repo: @repo)
      forked.add_member(forked_member = create(:user))

      refute_includes @org.outside_collaborators(include_forks: false), forked_member
    end

    test "can include only those collaborating on repos of specific visibility" do
      @repo.add_member(user_1 = create(:user))
      @repo.add_member(user_2 = create(:user))
      @pub_repo.add_member(user_3 = create(:user))
      @pub_repo.add_member(user_4 = create(:user))

      PermissionCache.enable do
        assert_equal [user_3, user_4], @org.outside_collaborators(on_repositories_with_visibility: [:public])
        assert_equal [user_1, user_2], @org.outside_collaborators(on_repositories_with_visibility: [:private])
        assert_equal [user_1, user_2], @org.outside_collaborators(on_repositories_with_visibility: [:private, :bad_visibility])
        assert_equal [user_1, user_2, user_3, user_4], @org.outside_collaborators(on_repositories_with_visibility: [:private, :public])
        assert_equal [user_1, user_2, user_3, user_4], @org.outside_collaborators
      end
    end
  end

  context "collaborating_repositories_for" do
    test "includes repos that the user has collaborator access on" do
      @repo.add_member(@non_org_member)
      assert_same_elements [@repo], @org.collaborating_repositories_for(@non_org_member.id)[@non_org_member.id]
    end

    test "works for multiple users" do
      other_non_org_member = create(:user, login: "other-non-org-member")
      @repo.add_member(other_non_org_member)
      @repo.add_member(@non_org_member)

      result = @org.collaborating_repositories_for([@non_org_member.id, other_non_org_member.id])
      assert_same_elements [@repo], result[@non_org_member.id]
      assert_same_elements [@repo], result[other_non_org_member.id]
    end

    test "excludes repos that the user has access to because of being an org owner" do
      assert_empty @org.collaborating_repositories_for(@org_admin.id)
    end

    test "excludes repos that the user has team access to" do
      assert_empty @org.collaborating_repositories_for(@org_member.id)
    end

    test "excludes forks that the user owns" do
      create(:fork_repository, forker: @org_member, fork_repo: @repo)

      assert_empty @org.collaborating_repositories_for(@org_member.id)
    end
  end

  context "collaborating_repository_ids_for" do
    test "includes repo ids that the user has collaborator access on" do
      @repo.add_member(@non_org_member)
      other_repo = create :private_repository, :minimal, owner: @org
      other_repo.add_member(@non_org_member)
      results = @org.collaborating_repository_ids_for(@non_org_member.id)
      assert_same_elements [[@non_org_member.id, @repo.id], [@non_org_member.id, other_repo.id]], results
    end

    test "works for multiple users" do
      other_non_org_member = create(:user, login: "other-non-org-member")
      @repo.add_member(other_non_org_member)
      @repo.add_member(@non_org_member)
      other_repo = create :private_repository, :minimal, owner: @org
      other_repo.add_member(@non_org_member)
      other_repo.add_member(other_non_org_member)

      results = @org.collaborating_repository_ids_for([@non_org_member.id, other_non_org_member.id])
      assert_same_elements [[@non_org_member.id, @repo.id], [@non_org_member.id, other_repo.id], [other_non_org_member.id, @repo.id], [other_non_org_member.id, other_repo.id]], results
    end

    test "excludes repo ids that the user has access to because of being an org owner" do
      assert_empty @org.collaborating_repository_ids_for(@org_admin.id)
    end

    test "excludes repos that the user has team access to" do
      assert_empty @org.collaborating_repository_ids_for(@org_member.id)
    end

    test "excludes forks that the user owns" do
      create(:fork_repository, forker: @org_member, fork_repo: @repo)

      assert_empty @org.collaborating_repository_ids_for(@org_member.id)
    end
  end

  context "#collaborating_repositories_for_user" do
    test "delegates to #collaborating_repositories_for" do
      user = create(:user)
      org = create(:organization)

      org.expects(:collaborating_repositories_for).with(user.id, equals({ limit: 50000 }))

      org.collaborating_repositories_for_user(user)
    end

    test "returns an Array of Repositories" do
      user = create(:user)
      @repo.add_member(user)

      results = @org.collaborating_repositories_for_user(user)

      assert_instance_of Array, results
      assert results.all? { |result| result.is_a?(Repository) }
    end
  end

  context "remove_direct_repo_access" do
    test "removes direct repo access" do
      @repo.add_member(@non_org_member)
      assert @repo.pushable_by?(@non_org_member)

      @org.remove_direct_repo_access(@non_org_member)

      refute @repo.pullable_by?(@non_org_member)
    end

    test "preserves indirect repo access" do
      direct_member = create(:user, login: "direct-member")
      add_member_to_org(@org, direct_member)
      @team.add_member(direct_member)
      @team.update_repository_permission(@repo, :push)
      assert @repo.pushable_by?(direct_member)

      @org.remove_direct_repo_access(direct_member)

      assert @repo.pullable_by?(direct_member)
    end

    test "preserves stars on private repos that the user has indirect access to" do
      Stars.domain.star_repository(repository: @repo, user: @org_member)

      assert @repo.pullable_by?(@org_member)
      assert Stars.domain.repo_starred_by_user?(@repo.id, @org_member.id)

      @org.remove_direct_repo_access(@org_member)

      assert @repo.pullable_by?(@org_member)
      assert Stars.domain.repo_starred_by_user?(@repo.id, @org_member.id)
    end
  end

  context "#can_leave?" do
    test "returns true for an org member" do
      direct_member = create(:user, login: "direct-member")
      add_member_to_org(@org, direct_member)

      assert @org.can_leave?(direct_member)
    end

    test "returns true for an owner, when not the last one" do
      admin_member = create(:user, login: "admin-member")
      @org.add_admin admin_member

      assert @org.admins.include? admin_member
      assert @org.admins.size > 1

      assert @org.can_leave?(admin_member)
    end

    test "returns false for the last owner" do
      assert @org.admins.include? @org_admin
      assert_equal 1, @org.admins.size

      refute @org.can_leave?(@org_admin)
    end
  end

  context "legacy_owners_team" do
    test "doesn't return an owners team manually created" do
      org = create(:organization)
      create(:team, organization: org, name: "Owners")

      assert_nil org.legacy_owners_team
    end
  end

  context "tried_to_destroy_owners_team_recently?" do
    test "returns true if a destroy owners team attempt was made recently" do
      Timecop.freeze do
        @org.update_attribute(:destroy_owners_team_attempted_at, 9.minutes.ago)
        assert @org.tried_to_destroy_owners_team_recently?
      end
    end

    test "returns false if a destroy owners team attempt was made a while ago" do
      Timecop.freeze do
        @org.update_attribute(:destroy_owners_team_attempted_at, 11.minutes.ago)
        refute @org.tried_to_destroy_owners_team_recently?
      end
    end

    test "returns false if a destroy owners team attempt was never made" do
      refute @org.tried_to_destroy_owners_team_recently?
    end
  end

  context "last_active" do
    test "returns No activity if there are no admins" do
      # Specifically tests the github-enterprise org on Enterprise instances,
      # which sometimes has no admins.
      org_without_admins = create :organization, login: "github-enterprise"
      org_without_admins.stubs admins: []

      assert_empty org_without_admins.admins
      assert_equal "No activity", org_without_admins.last_active
    end

    test "returns No activity if there are admins, but no admin events" do
      assert_equal "No activity", @org.last_active
    end

    test "returns date of the most recent event" do
      last_active_date = Time.rfc2822("Tue, 15 Jul 2008 17:40:30 -0700").utc
      Timecop.freeze(last_active_date) do
        only = [ProcessEventJob, UpdateEventFeedsJob]
        repo = perform_enqueued_jobs(only: only) do
          create :repository, :full_creation, owner: @org
        end
      end
      events = @org_admin.events(type: :org, param: @org)
      assert_equal last_active_date.in_time_zone, @org.last_active
    end
  end

  context "migrate_legacy_admin_teams!" do
    test "migrates legacy admin teams to regular teams" do
      regular_team       = create(:team, organization: @org)
      legacy_admin_teams = Array.new(2) { create(:team, organization: @org, permission: "admin") }

      refute_predicate regular_team, :legacy_admin?
      legacy_admin_teams.each { |team| assert_predicate team, :legacy_admin? }

      @org.migrate_legacy_admin_teams!

      ([regular_team] + legacy_admin_teams).each do |team|
        team.reload
        refute_predicate team, :legacy_admin?
      end
    end
  end

  context "#email_eligible_domain_urls" do
    test "returns urls from org verified or approved domains for an org not belonging to a business" do
      verified_url = "verified.org"
      approved_url = "approved.org"
      create(:verifiable_domain, owner: @org, domain: verified_url, verified: true)
      create(:verifiable_domain, owner: @org, domain: approved_url, approved: true)
      create(:verifiable_domain, owner: @org, domain: "unknown.org")

      assert_same_elements [verified_url, approved_url], @org.email_eligible_domain_urls
    end

    test "can return only verified domains" do
      verified_url = "verified.org"
      approved_url = "approved.org"
      create(:verifiable_domain, owner: @org, domain: verified_url, verified: true)
      create(:verifiable_domain, owner: @org, domain: approved_url, approved: true)

      assert_equal [verified_url], @org.email_eligible_domain_urls(include_approved: false)
    end

    test "can return only approved domains" do
      verified_url = "verified.org"
      approved_url = "approved.org"
      create(:verifiable_domain, owner: @org, domain: verified_url, verified: true)
      create(:verifiable_domain, owner: @org, domain: approved_url, approved: true)

      assert_equal [approved_url], @org.email_eligible_domain_urls(include_verified: false)
    end

    test "returns nothing if asked not to include verified or approved domains" do
      verified_url = "verified.org"
      approved_url = "approved.org"
      create(:verifiable_domain, owner: @org, domain: verified_url, verified: true)
      create(:verifiable_domain, owner: @org, domain: approved_url, approved: true)
      create(:verifiable_domain, owner: @org, domain: "unknown.org")

      assert_empty @org.email_eligible_domain_urls(include_verified: false, include_approved: false)
    end

    test "returns urls from both org and parent business verified or approved domains for an org belonging to a business" do
      verified_url = "verified.org"
      verified_business_url = "verified.biz"
      approved_url = "approved.org"
      approved_business_url = "approved.biz"
      create(:verifiable_domain, owner: @business_org, domain: verified_url, verified: true)
      create(:verifiable_domain, owner: @business, domain: verified_business_url, verified: true)
      create(:verifiable_domain, owner: @business_org, domain: approved_url, approved: true)
      create(:verifiable_domain, owner: @business, domain: approved_business_url, approved: true)
      create(:verifiable_domain, owner: @business_org, domain: "unknown.org")
      create(:verifiable_domain, owner: @business, domain: "unknown.biz")

      assert_same_elements [
        verified_url,
        verified_business_url,
        approved_url,
        approved_business_url
      ], @business_org.email_eligible_domain_urls
    end

    test "returns de-duplicated urls list if org and parent business have verified or approved the same domain" do
      verified_url = "verified.com"
      approved_url = "approved.com"
      create(:verifiable_domain, owner: @business_org, domain: verified_url, verified: true)
      create(:verifiable_domain, owner: @business, domain: verified_url, verified: true)
      create(:verifiable_domain, owner: @business_org, domain: approved_url, approved: true)
      create(:verifiable_domain, owner: @business, domain: approved_url, approved: true)

      assert_same_elements [verified_url, approved_url], @business_org.email_eligible_domain_urls
    end
  end

  context "#domain_emails_for_member_ids" do
    test "returns organization members emails with verified or approved domains" do
      verified_domain = create(:verifiable_domain, owner: @org, verified: true)
      approved_domain = create(:verifiable_domain, owner: @org, approved: true)
      owner_email = @org_admin.add_email("mercy@#{verified_domain.domain}")
      owner_other_email = @org_admin.add_email("orisa@#{verified_domain.domain}")
      member_email = @org_member.add_email("sombra@#{verified_domain.domain}")
      member_other_email = @org_member.add_email("sombra@#{approved_domain.domain}")
      teammate = create(:user)
      other_teammate = create(:user)
      team = create(:team, organization: @org)
      team.add_member teammate
      team.add_member other_teammate
      team_member_email = teammate.add_email("junkrat@#{approved_domain.domain}")

      [
        owner_email, owner_other_email, member_email,
        member_other_email, team_member_email
      ].each do |email|
        email.verify!
      end

      expected = {
        @org_admin.id => [owner_email, owner_other_email],
        @org_member.id => [member_email, member_other_email],
        other_teammate.id => [],
        teammate.id => [team_member_email],
      }

      got = @org.domain_emails_for_member_ids(
        member_ids: [@org_admin.id, @org_member.id, teammate.id, other_teammate.id]
      )

      assert_equal expected.sort.each { |_, v| v.sort! }, got.sort.each { |_, v| v.sort! }
    end

    test "returns empty emails arrays for org without verified or approved domains" do
      expected = {
        @org_admin.id => [],
        @org_member.id => []
      }
      assert_equal expected, @org.domain_emails_for_member_ids(
        member_ids: [@org_admin.id, @org_member.id]
      )
    end
  end

  context "#verified_profile_domains" do
    test "returns nothing when there is a profile website but it is not yet verified" do
      @org.update_attribute(:profile_blog, "some_great_website.example.com")
      assert @org.profile_email.blank?
      refute @org.verifiable_domains.any?
      org_website = create(:verifiable_domain, owner: @org, domain: @org.profile_blog)
      unrelated_website = create(:verifiable_domain, owner: @org,
                                 verified: true, domain: "some_unrelated_website.example.com")

      assert_empty @org.verified_profile_domains
      refute @org.is_verified?
    end

    test "returns nothing when there is a profile website but it is not yet verified by the parent business" do
      @business_org.update_attribute(:profile_blog, "some_great_website.example.com")
      assert @business_org.profile_email.blank?
      refute @business_org.verifiable_domains.any?
      enterprise_domain = create(:verifiable_domain, owner: @business,
                                 domain: @business_org.profile_blog)
      unrelated_website = create(:verifiable_domain, owner: @business,
                                 verified: true,
                                 domain: "some_unrelated_website.example.com")

      assert_empty @business_org.verified_profile_domains
      refute @business_org.is_verified?
    end

    test "returns the profile website when it has been verified" do
      @org.update_attribute(:profile_blog, "some_great_website.example.com")
      org_website = create(:verifiable_domain, owner: @org, verified: true, domain: @org.profile_blog)

      # The domain has been verified and matches the org website
      assert_equal [org_website.domain], @org.verified_profile_domains
      assert @org.is_verified?
    end

    test "returns the profile website when it has been verified by the parent business" do
      @business_org.update_attribute(:profile_blog, "some_great_website.example.com")
      org_website = create(:verifiable_domain, owner: @business,
                           verified: true, domain: @business_org.profile_blog)

      # The domain has been verified and matches the org website
      assert_equal [org_website.domain], @business_org.verified_profile_domains
      assert @business_org.is_verified?
    end

    test "returns only verified profile domains when there is also another verified domain" do
      @org.update_attribute(:profile_blog, "some_great_website.example.com")
      org_website = create(:verifiable_domain, owner: @org, verified: true, domain: @org.profile_blog)
      random_domain = create(:verifiable_domain, verified: true, owner: @org)

      # The domain has been verified and matches the org website
      assert_equal [org_website.domain], @org.verified_profile_domains
      assert @org.is_verified?
    end

    test "returns only verified profile domains when there is also another verified domain when all domains verified by parent business" do
      @business_org.update_attribute(:profile_blog, "some_great_website.example.com")
      org_website = create(:verifiable_domain, owner: @business, verified: true, domain: @business_org.profile_blog)
      random_domain = create(:verifiable_domain, verified: true, owner: @business)

      # The domain has been verified and matches the org website
      assert_equal [org_website.domain], @business_org.verified_profile_domains
      assert @business_org.is_verified?
    end

    test "returns nothing when the profile website has been verified but the email has not" do
      @org.update_attribute(:profile_blog, "some_great_website.example.com")
      org_website = create(:verifiable_domain, owner: @org, verified: true, domain: @org.profile_blog)
      @org.update_attribute(:profile_email, "a_great_email@another.example.com")

      assert_empty @org.verified_profile_domains
      refute @org.is_verified?
    end

    test "returns nothing when the profile website has been verified but the email has not when verified by parent business" do
      @business_org.update_attribute(:profile_blog, "some_great_website.example.com")
      org_website = create(:verifiable_domain, owner: @business,
                           verified: true, domain: @business_org.profile_blog)
      @business_org.update_attribute(:profile_email, "a_great_email@another.example.com")

      assert_empty @business_org.verified_profile_domains
      refute @business_org.is_verified?
    end

    test "returns the profile email and website when they have both been verified" do
      @org.update_attribute(:profile_blog, "some_great_website.example.com")
      org_website = create(:verifiable_domain, owner: @org,
                           verified: true, domain: @org.profile_blog)
      @org.update_attribute(:profile_email, "a_great_email@another.example.com")
      org_email = create(:verifiable_domain, owner: @org,
                         verified: true, domain: @org.profile_email.split("@").last)

      assert_same_elements [org_website.domain, org_email.domain], @org.verified_profile_domains
    end

    test "returns the profile email and website when they have both been verified by parent business" do
      @business_org.update_attribute(:profile_blog, "some_great_website.example.com")
      org_website = create(:verifiable_domain, owner: @business,
                           verified: true, domain: @business_org.profile_blog)
      @business_org.update_attribute(:profile_email, "a_great_email@another.example.com")
      org_email = create(:verifiable_domain, owner: @business,
                         verified: true, domain: @business_org.profile_email.split("@").last)

      assert_same_elements [org_website.domain, org_email.domain], @business_org.verified_profile_domains
    end

    test "returns the profile email and website when they have both been verified, one by org, one by parent business" do
      @business_org.update_attribute(:profile_blog, "some_great_website.example.com")
      org_website = create(:verifiable_domain, owner: @business,
                           verified: true, domain: @business_org.profile_blog)
      @business_org.update_attribute(:profile_email, "a_great_email@another.example.com")
      org_email = create(:verifiable_domain, owner: @business_org,
                         verified: true, domain: @business_org.profile_email.split("@").last)

      assert_same_elements [org_website.domain, org_email.domain], @business_org.verified_profile_domains
    end

    test "returns a single domain if the blog and email domains are the same" do
      @org.update_attribute(:profile_blog, "example.com")
      @org.update_attribute(:profile_email, "a_great_email@example.com")

      verified = create(:verifiable_domain, owner: @org, verified: true, domain: "example.com")

      assert_equal [verified.domain], @org.verified_profile_domains
    end

    test "returns a single domain if the blog and email domains are the same and are verified by the parent business" do
      @business_org.update_attribute(:profile_blog, "example.com")
      @business_org.update_attribute(:profile_email, "a_great_email@example.com")

      verified = create(:verifiable_domain, owner: @business, verified: true, domain: "example.com")

      assert_equal [verified.domain], @business_org.verified_profile_domains
    end

    test "normalizes domains prior to comparison" do
      @org.update_attribute(:profile_blog, "some_great_website.example.com")
      org_website = create(:verifiable_domain, owner: @org, verified: true, domain: @org.profile_blog)
      @org.update_attribute(:profile_blog, "#{@org.profile_blog}/about")

      assert_equal [org_website.domain], @org.verified_profile_domains
    end

    test "normalizes domains prior to comparison when verified by parent business" do
      @business_org.update_attribute(:profile_blog, "some_great_website.example.com")
      org_website = create(:verifiable_domain, owner: @business,
                           verified: true, domain: @business_org.profile_blog)
      @business_org.update_attribute(:profile_blog, "#{@business_org.profile_blog}/about")

      assert_equal [org_website.domain], @business_org.verified_profile_domains
    end
  end

  context "#email_eligible_domains" do
    test "only returns verified and approved domains associated with this org or its parent business" do
      rando_domain = create(:verifiable_domain, verified: true)
      rando_approved_domain = create(:verifiable_domain, approved: true)
      org_domain = create(:verifiable_domain, owner: @business_org, verified: true)
      approved_org_domain = create(:verifiable_domain, owner: @business_org, approved: true)
      unverified_org_domain = create(:verifiable_domain, owner: @business_org)
      business_domain = create(:verifiable_domain, owner: @business, verified: true)
      approved_business_domain = create(:verifiable_domain, owner: @business, approved: true)
      unverified_business_domain = create(:verifiable_domain, owner: @business)

      assert_same_elements [org_domain, business_domain, approved_org_domain, approved_business_domain],
        @business_org.email_eligible_domains
    end

    test "can return only verified domains" do
      verified_org_domain = create(:verifiable_domain, owner: @business_org, verified: true)
      approved_org_domain = create(:verifiable_domain, owner: @business_org, approved: true)
      verified_business_domain = create(:verifiable_domain, owner: @business, verified: true)
      approved_business_domain = create(:verifiable_domain, owner: @business, approved: true)

      assert_same_elements [verified_org_domain, verified_business_domain],
                           @business_org.email_eligible_domains(include_approved: false)
    end

    test "can return only approved domains" do
      verified_org_domain = create(:verifiable_domain, owner: @business_org, verified: true)
      approved_org_domain = create(:verifiable_domain, owner: @business_org, approved: true)
      verified_business_domain = create(:verifiable_domain, owner: @business, verified: true)
      approved_business_domain = create(:verifiable_domain, owner: @business, approved: true)

      assert_same_elements [approved_org_domain, approved_business_domain],
                           @business_org.email_eligible_domains(include_verified: false)
    end

    test "returns nothing if asked not to include verified or approved domains" do
      create(:verifiable_domain, owner: @business_org, verified: true)
      create(:verifiable_domain, owner: @business_org, approved: true)
      create(:verifiable_domain, owner: @business, verified: true)
      create(:verifiable_domain, owner: @business, approved: true)

      @business_org.expects(:async_email_eligible_domains).never
      assert_empty @business_org.email_eligible_domains(include_verified: false, include_approved: false)
    end
  end

  context "#ip_allowlist_entries" do
    test "returns IP allow list entries owned by the organization" do
      org = create :business_plus_org
      entry = create :ip_allowlist_entry, owner: org
      assert_same_elements [entry], org.reload.ip_allowlist_entries
    end
  end

  context ".with_team_sync_status", team_synchronization_available: true do
    test "returns organizations with the appropriate status(es)" do
      team_sync_tenant = create(:team_sync_tenant, status: :pending)
      pending_organization = team_sync_tenant.organization

      team_sync_tenant = create(:team_sync_tenant, status: :failed)
      failed_organization = team_sync_tenant.organization

      team_sync_tenant = create(:team_sync_tenant, status: :ready)
      ready_organization = team_sync_tenant.organization

      team_sync_tenant = create(:team_sync_tenant, status: :enabled)
      enabled_organization = team_sync_tenant.organization

      disabled_team_sync_tenant = create(:team_sync_tenant, status: :disabled)
      disabled_organization = disabled_team_sync_tenant.organization

      assert_same_elements [enabled_organization], Organization.with_team_sync_status(:enabled)
      assert_same_elements [disabled_organization], Organization.with_team_sync_status(:disabled)
      assert_same_elements [pending_organization, disabled_organization], Organization.with_team_sync_status([:pending, :disabled])
      assert_same_elements [], Organization.with_team_sync_status([])
      assert_same_elements [], Organization.with_team_sync_status(nil)
      assert_raises ArgumentError do
        assert_same_elements [], Organization.with_team_sync_status
      end
    end
  end

  context "default repo visibility" do
    test "is public for a dotcom user" do
      assert_equal "public", @rando.default_repo_visibility
    end unless GitHub.enterprise?

    test "is private for a free org on dotcom, internal on GHES" do
      free_org = create(:free_organization)
      expected = GitHub.enterprise? ? "internal" : "private"
      assert_equal expected, free_org.default_repo_visibility
    end

    test "is private for a paid org on dotcom, internal on GHES" do
      paid_org = create(:organization)
      expected = GitHub.enterprise? ? "internal" : "private"
      assert_equal expected, paid_org.default_repo_visibility
    end

    test "honors config setting for a GHES org" do
      GitHub.set_default_repo_visibility("private", @org_admin)
      assert_equal "private", @org.default_repo_visibility
      GitHub.set_default_repo_visibility("public", @org_admin)
      assert_equal "public", @org.default_repo_visibility
      GitHub.set_default_repo_visibility("internal", @org_admin)
      assert_equal "internal", @org.default_repo_visibility
    end if GitHub.enterprise?

    test "honors config setting for a GHES user" do
      GitHub.set_default_repo_visibility("private", @org_admin)
      assert_equal "private", @rando.default_repo_visibility
      GitHub.set_default_repo_visibility("public", @org_admin)
      assert_equal "public", @rando.default_repo_visibility

      GitHub.set_default_repo_visibility("internal", @org_admin)
      # Users can't own internal repos. User repos default to private
      # if site config default is internal.
      assert_equal "private", @rando.default_repo_visibility
    end if GitHub.enterprise?

    test "is internal for a dotcom org in an enterprise" do
      assert_equal "internal", @internal_repo_org.default_repo_visibility
    end unless GitHub.enterprise?

    test "is private for a dotcom org in an enterprise when internal is disallowed" do
      @internal_repo_org.allow_members_can_create_repositories_with_visibilities(actor: @org_admin, internal_visibility: false)
      assert_equal "private", @internal_repo_org.default_repo_visibility
    end unless GitHub.enterprise?
  end

  context "#bypass_org_invitations?" do
    test "returns false for organizations not in enterprise mode or owned by EMU business" do
      org = @business.organizations.first
      refute GitHub.enterprise?
      refute org.business.enterprise_managed_user_enabled?
      refute org.bypass_org_invitations?
    end unless GitHub.single_business_environment?

    test "returns true for enterprise environment" do
      assert GitHub.enterprise?
      assert @org.bypass_org_invitations?
    end if GitHub.single_business_environment?

    test "returns true for organizations in an EMU business" do
      new_org = create(:organization)
      emu_business = create(:business, :enterprise_managed, organizations: [new_org])
      assert new_org.reload.bypass_org_invitations?
    end unless GitHub.single_business_environment?
  end

  context "spammy notice" do
    test "sets spammy notice if user is spammy" do
      member = create(:user)
      other_admin = create(:user)
      org = create(:organization, admin: @org_admin)
      org.add_admin(other_admin)
      add_member_to_org(org, member)

      perform_enqueued_jobs(only: SpammyOrgCheckJob) do
        org.spammy = true
        org.save
      end

      assert_equal :spammy_orgs, GlobalNoticeNext.new(viewer: @org_admin).current_notice_name
      assert_equal :spammy_orgs, GlobalNoticeNext.new(viewer: other_admin).current_notice_name
      refute_equal :spammy_orgs, GlobalNoticeNext.new(viewer: member).current_notice_name
    end

    test "does not set spammy notice if user is not spammy" do
      member = create(:user)
      other_admin = create(:user)
      org = create(:organization, admin: @org_admin)
      org.add_admin(other_admin)
      add_member_to_org(org, member)

      assert_enqueued_jobs 0, only: SpammyOrgCheckJob do
        org.spammy = false
        org.save
      end

      refute_equal :spammy_orgs, GlobalNoticeNext.new(viewer: @org_admin).current_notice_name
      refute_equal :spammy_orgs, GlobalNoticeNext.new(viewer: other_admin).current_notice_name
      refute_equal :spammy_orgs, GlobalNoticeNext.new(viewer: member).current_notice_name
    end

    test "sets spammy delist apps for organization" do
      listing = create(:marketplace_listing, :verified,
        listable: create(:oauth_application))
      plan = create :marketplace_listing_plan, :published,
        listing: listing
      org = listing.owner

      org.spammy = true
      org.save

      assert_equal listing.reload.state, Marketplace::Listing.state_value(:archived)
    end
  end unless GitHub.single_business_environment?

  context "#team_search_for_user" do
    test "default returns all visible teams for user" do
      query = TeamSearchQuery.new(nil)
      teams = @org.team_search_for_user(query, @org.user)

      assert_same_elements [@parent_team, @child_team, @team], teams
    end

    test "filters for all teams where user is a member" do
      user = create(:user)
      add_member_to_org(@org, user)
      @child_team.add_member(user)

      query = TeamSearchQuery.new("members:me")
      teams = @org.team_search_for_user(query, user)

      assert_same_elements [@child_team], teams
    end

    test "filters for all empty teams" do
      query = TeamSearchQuery.new("members:empty")
      teams = @org.team_search_for_user(query, @org.admin)

      assert_same_elements [@parent_team, @child_team], teams
    end

    test "filters by member query" do
      user = create(:user, login: "monalisa")
      add_member_to_org(@org, user)
      @child_team.add_member(user)

      query = TeamSearchQuery.new("@monalisa")
      teams = @org.team_search_for_user(query, @org.admin)

      assert_same_elements [@child_team], teams
    end

    test "filters by query string" do
      syrup_team = create(:team, name: "Waffles with Syrup", organization: @org, privacy: :closed)

      query = TeamSearchQuery.new("Syrup")
      teams = @org.team_search_for_user(query, @org.admin)

      assert_same_elements [syrup_team], teams
    end

    test "immediate_only returns only root teams" do
      query = TeamSearchQuery.new(nil)
      teams = @org.team_search_for_user(query, @org.admin, immediate_only: true)

      assert_same_elements [@parent_team, @team], teams
    end

    test "filters by visibility secret" do
      query = TeamSearchQuery.new("visibility:secret")
      teams = @org.team_search_for_user(query, @org.admin)

      assert_same_elements [@team], teams
    end

    test "filters by visibility closed" do
      query = TeamSearchQuery.new("visibility:visible")
      teams = @org.team_search_for_user(query, @org.admin)

      assert_same_elements [@parent_team, @child_team], teams
    end

    test "can filter by member and query string" do
      user = create(:user, login: "monalisa")
      syrup_team = create(:team, name: "Waffles with Syrup", organization: @org, privacy: :closed)
      add_member_to_org(@org, user)
      syrup_team.add_member(user)

      query = TeamSearchQuery.new("Syrup @monalisa")
      teams = @org.team_search_for_user(query, @org.admin)

      assert_same_elements [syrup_team], teams
    end

    context "organization profile emails" do
      test "destroys organization profile email records when org is destroyed" do
        org = create(:organization)
        org_id = org.id
        org.update(profile_email: "github@github.com")
        org_profile_email = create(:organization_profile_email, organization: org)

        assert org_profile_email

        perform_enqueued_jobs(only: [DestroyDependentRecordsJob]) do
          assert_difference("OrganizationProfileEmail.count", -1) do
            org.destroy
          end
        end

        assert_raises ActiveRecord::RecordNotFound do
          Organization.find(org_id)
        end
        assert_nil OrganizationProfileEmail.find_by(organization_id: org_id)
      end

      test "does not save organization profile email when email is invalid" do
        org = create(:organization)
        org.update(profile_email: "abc")
        refute org.add_profile_email_to_verify(org.admin).valid?
        assert_nil OrganizationProfileEmail.find_by(organization_id: org.id)
      end

      test "saves organization profile email when email is valid" do
        org = create(:organization)
        org.update(profile_email: "github@github.com")
        assert org.add_profile_email_to_verify(org.admin).valid?
        assert OrganizationProfileEmail.find_by(organization_id: org.id)
      end
    end
  end

  context "#all_org_repos_for_user" do
    test "uses org scoping for users in the feature flag" do
      org = create(:organization)
      repo = create(:repository, :minimal, owner: org)
      GitHub.flipper[:org_scoped_ari].enable(@rando)
      org.expects(:unscoped_repo_ids_with_team_membership).never
      org.expects(:org_scoped_repo_ids_with_team_membership).once.returns([repo.id])

      assert_equal [repo.id], org.all_org_repo_ids_for_user(@rando)
    end

    test "does not use org scoping for users not in the feature flag" do
      org = create(:organization)
      repo = create(:repository, :minimal, owner: org)
      GitHub.flipper[:org_scoped_ari].disable(@rando)
      org.expects(:unscoped_repo_ids_with_team_membership).once.returns([repo.id])
      org.expects(:org_scoped_repo_ids_with_team_membership).never

      assert_equal [repo.id], org.all_org_repo_ids_for_user(@rando)
    end

    test "don't show deleted repos" do
      repo_ids = @org.all_org_repo_ids_for_user(@org_member)
      assert_same_elements [@repo.id, @pub_repo.id, @pub_push_repo.id, @org_repo2.id], repo_ids
    end
  end

  # Tests regarding initialization of Workflow Permissions
  context "Organization Workflow Permission Settings" do
    test "new org outside business has restrictive github token permissions" do
      org = create(:organization)

      if GitHub.flipper[:actions_default_workflow_permissions_new_repos].enabled?
        assert org.actions_default_workflow_permissions_read_only?
        assert_equal org, org.actions_default_workflow_permissions_source
      else
        refute org.actions_default_workflow_permissions_read_only?
        assert_nil org.actions_default_workflow_permissions_source
      end

      org.set_default_workflow_permissions("write", @org_admin)
      refute org.actions_default_workflow_permissions_read_only?
      assert_nil org.actions_default_workflow_permissions_source
    end

    test "new org outside busines always have PR approval permissions default to false" do
      org = create(:organization)

      refute org.actions_workflow_permission_can_approve_pr?
      assert_equal org, org.actions_workflow_permission_can_approve_pr_source

      org.set_actions_workflow_permission_can_approve_pr(true, @org_admin)

      assert org.actions_workflow_permission_can_approve_pr?
      assert_nil org.actions_workflow_permission_can_approve_pr_source
    end

    test "new org in business inherits github token permissions" do
      @business.add_owner(@org_admin, actor: nil)
      @business.set_default_workflow_permissions("read", @org_admin)
      org1 = create(:organization, business: @business)

      assert org1.actions_default_workflow_permissions_read_only?
      assert_equal @business, org1.actions_default_workflow_permissions_source

      @business.set_default_workflow_permissions("write", @org_admin)
      org2 = create(:organization, business: @business)
      org1.reload

      refute org1.actions_default_workflow_permissions_read_only?
      assert_nil org1.actions_default_workflow_permissions_source
      refute org2.actions_default_workflow_permissions_read_only?
      assert_nil org2.actions_default_workflow_permissions_source
    end

    test "existing org in business has restrictive github token permissions" do
      @business.add_owner(@org_admin, actor: nil)
      @business.set_default_workflow_permissions("write", @org_admin)
      org = create(:organization, business: @business)

      refute org.actions_default_workflow_permissions_read_only?
      assert_nil org.actions_default_workflow_permissions_source

      org.set_default_workflow_permissions("read", @org_admin)

      assert org.actions_default_workflow_permissions_read_only?
      assert org, org.actions_default_workflow_permissions_source
    end

    test "new org in business always have PR approval permissions default to false" do
      @business.add_owner(@org_admin, actor: nil)
      @business.set_actions_workflow_permission_can_approve_pr(false, @org_admin)
      org1 = create(:organization, business: @business)

      refute org1.actions_workflow_permission_can_approve_pr?
      assert_equal org1, org1.actions_workflow_permission_can_approve_pr_source

      @business.set_actions_workflow_permission_can_approve_pr(true, @org_admin)
      org2 = create(:organization, business: @business)
      org1.reload

      refute org1.actions_workflow_permission_can_approve_pr?
      assert_equal org1, org1.actions_workflow_permission_can_approve_pr_source
      refute org2.actions_workflow_permission_can_approve_pr?
      assert_equal org2, org2.actions_workflow_permission_can_approve_pr_source
    end

    test "existing org in business has restrictive PR approval permissions" do
      @business.add_owner(@org_admin, actor: nil)
      @business.set_actions_workflow_permission_can_approve_pr(true, @org_admin)
      org = create(:organization, business: @business)

      refute org.actions_workflow_permission_can_approve_pr?
      assert_equal org, org.actions_workflow_permission_can_approve_pr_source

      org.set_actions_workflow_permission_can_approve_pr(false, @org_admin)

      refute org.actions_workflow_permission_can_approve_pr?
      assert_equal org, org.actions_workflow_permission_can_approve_pr_source

      org.set_actions_workflow_permission_can_approve_pr(true, @org_admin)

      assert org.actions_workflow_permission_can_approve_pr?
      assert_nil org.actions_workflow_permission_can_approve_pr_source
    end
  end

  context "#scim_managed_enterprise?" do
    test "returns false" do
      refute_predicate @org, :scim_managed_enterprise?
    end
  end

  context "#enterprise_server_scim_enabled?" do
    test "returns false" do
      refute_predicate @org, :enterprise_server_scim_enabled?
    end

    test "async returns false" do
      refute @org.async_enterprise_server_scim_enabled?.sync
    end
  end

  context "#belongs_to_a_soft_deleted_business?", skip_enterprise: true do
    test "returns true if belongs to a soft deleted business" do
      @business.update(deleted_at: Time.now)
      @business_org.soft_delete!

      assert @business_org.reload.belongs_to_a_soft_deleted_business?
    end

    test "returns false if belongs to a soft deleted business" do
      refute @business_org.belongs_to_a_soft_deleted_business?
    end
  end

  context "#eligible_for_legacy_upsell" do
    test "false for orgs with non-legacy plans" do
      org = create(:organization, plan: GitHub::Plan.business)
      org.seats = rand(60)

      refute org.eligible_for_legacy_upsell?
    end

    test "true for orgs with less than 100 seats" do
      org = create(:organization, plan: GitHub::Plan.gold)
      org.seats = rand(60..99)
      assert org.eligible_for_legacy_upsell?
    end

    test "false for orgs with 100 or more seats" do
      org = create(:organization, plan: GitHub::Plan.gold)
      org.seats = rand(100..105)

      refute org.eligible_for_legacy_upsell?
    end

    test "false for archived orgs" do
      org = create(:archived_organization, plan: GitHub::Plan.gold)
      org.seats = rand(60..99)

      refute org.eligible_for_legacy_upsell?
    end
  end

  context "#advanced_security_eligible?" do
    test "when billing is enabled and plan is business_plus" do
      GitHub.stubs(billing_enabled?: true)
      org = create(:organization, plan: GitHub::Plan.business_plus)
      assert org.advanced_security_eligible?
    end

    test "when billing is enabled and plan is not business_plus" do
      GitHub.stubs(billing_enabled?: true)
      org = create(:organization)
      refute org.advanced_security_eligible?
    end

    test "When billing is not enabled" do
      GitHub.stubs(billing_enabled?: false)
      org = create(:organization, plan: GitHub::Plan.business_plus)
      refute org.advanced_security_eligible?
    end
  end

  context "#can_disable_audit_log_ip_disclosure?" do
    test "returns true for free organizations" do
      org = create(:organization, admin: @org_admin, plan: "free")

      assert org.can_disable_audit_log_ip_disclosure?
    end

    test "returns false for organizations with enabled businesses" do
      org = create(:organization, business: @business)
      @business.stubs(:source_ip_disclosure_enabled?).returns(true)

      refute org.can_disable_audit_log_ip_disclosure?
    end

    test "returns true for organizations with disabled businesses" do
      org = create(:organization, business: @business)
      @business.stubs(:source_ip_disclosure_enabled?).returns(false)

      assert org.can_disable_audit_log_ip_disclosure?
    end
  end

  # High Profile organizations are defined by the following Trust & Safety criteria:
  # https://github.com/github/trust-safety/blob/main/docs/operations/escalation-procedures/high-profile-escalation.md
  context "#high_profile?" do
    test "false if high profile criteria not met" do
      org = create(:organization)
      org_repo = create(:repository, owner: org, name: "org-repo")

      high_profile, high_profile_reason = HighProfileSignals.high_profile_user?(org)
      refute high_profile
      assert_nil high_profile_reason
    end

    test "true if high profile criteria for enterprise customer is met" do
      org = create(:business_plus_organization, admin: @org_admin)

      high_profile, high_profile_reason = HighProfileSignals.high_profile_user?(org)

      assert high_profile
      assert_equal "Organization meets criteria threshold: current Premium, Premium Plus, or Enterprise customer", high_profile_reason
    end

    test "true if high profile criteria for org members count is met" do
      org = create(:organization)

      24.times do
        user = create(:user)
        add_member_to_org(org, user)
      end

      high_profile, high_profile_reason = HighProfileSignals.high_profile_user?(org)

      assert high_profile
      assert_equal "Organization meets criteria threshold: member count", high_profile_reason
    end

    test "true if high profile criteria for org admins count is met" do
      org = create(:organization)

      4.times do
        user = create(:user)
        add_member_to_org(org, user, action: :admin)
      end

      org.reload.admins

      high_profile, high_profile_reason = HighProfileSignals.high_profile_user?(org)

      assert high_profile
      assert_equal "Organization meets criteria threshold: admin count", high_profile_reason
    end

    test "true if org owns one or more high profile repositories" do
      org = create(:organization)
      org_repo = create(:repository, owner: org, name: "org-repo")
      org_high_profile_repo = create(:repository, owner: org, name: "org-high-profile-repo")

      4.times do
        user = create(:user)
        add_member_to_org(org, user, action: :admin)
      end

      org.reload.admins

      50.times do
        forker = create(:user)
        fork = create(:fork_repository, forker: forker, fork_repo: org_high_profile_repo)
      end

      high_profile, high_profile_reason = HighProfileSignals.high_profile_user?(org)

      assert high_profile
      assert_equal "Organization meets criteria threshold: admin count, owns one or more high profile repositories", high_profile_reason
    end

    test "true for multiple high profile criteria" do
      org = create(:organization)
      org_repo = create(:repository, owner: org, name: "org-repo")
      org_high_profile_repo = create(:repository, owner: org, name: "org-high-profile-repo")

      50.times do
        forker = create(:user)
        fork = create(:fork_repository, forker: forker, fork_repo: org_high_profile_repo)
      end

      high_profile, high_profile_reason = HighProfileSignals.high_profile_user?(org)

      assert high_profile
      assert_equal "Organization meets criteria threshold: owns one or more high profile repositories", high_profile_reason
    end
  end

  context "#publicize_members_bulk" do
    test "inserts users into public_org_members table" do
      users = create_list(:user, 2).each do |user|
        add_member_to_org(@business_org, user)
      end

      @business_org.bulk_publicize_members(users)

      sql_bindings = {
        user_one_id: users.first.id,
        user_two_id: users.second.id,
        organization_id: @business_org.id
      }

      sql = Arel.sql <<-SQL, **sql_bindings
        SELECT user_id, organization_id FROM public_org_members
        WHERE organization_id = :organization_id AND (user_id = :user_one_id OR user_id = :user_two_id)
      SQL

      results = Organization.connection.select_rows(sql)
      assert_equal results.count, 2
      assert_same_elements [users.first.id, @business_org.id], results.first
      assert_same_elements [users.second.id, @business_org.id], results.second
    end

    test "ignores when organization_membership entry is not unique" do
      Organization.any_instance.stubs(:add_organization_membership_entry).raises(ActiveRecord::RecordNotUnique)
      user = create(:user)
      refute @business_org.direct_member?(user)
      @business_org.add_member(user)
      assert @business_org.direct_member?(user)
    end

    test "skips inserting users that are not members into public_org_members table" do
      users = create_list(:user, 2)
      @business_org.add_member users.first
      @business_org.bulk_publicize_members(users)

      sql_bindings = {
        user_one_id: users.first.id,
        user_two_id: users.second.id,
        organization_id: @business_org.id
      }

      sql = Arel.sql <<-SQL, **sql_bindings
        SELECT user_id, organization_id FROM public_org_members
        WHERE organization_id = :organization_id AND (user_id = :user_one_id OR user_id = :user_two_id)
      SQL

      results = Organization.connection.select_rows(sql)
      assert_equal results.count, 1
      assert_same_elements [users.first.id, @business_org.id], results.first
    end

    test "calls synchronize_search_index on org members after inserting" do
      users = create_list(:user, 2)
      @business_org.add_member users.first
      users.first.expects(:synchronize_search_index).once
      users.second.expects(:synchronize_search_index).never

      @business_org.bulk_publicize_members(users)
    end
  end

  context "issue types" do
    test "destroys issue type record when org is destroyed", feature_disabled: :hydro_issue_types_deletion_on_user_destroyed_kill_switch do
      owner = create(:organization)
      owner_id = owner.id
      queue = HydroIssueTypesDeletionOnUserDestroyedJob.queue_name
      schema = "github.v1.UserDestroy"
      message = {
        user: UserEntitySerializer.serialize(owner),
      }

      perform_enqueued_jobs(only: [DestroyDependentRecordsJob]) do
        assert_difference("IssueType.count", -3) do
          owner.destroy
          perform_hydro_message_job(message, schema: schema, queue: queue)
        end
      end

      assert_raises ActiveRecord::RecordNotFound do
        Organization.find(owner_id)
      end
      assert_nil IssueType.find_by(owner_id: owner_id)
    end
  end

  context "#disable_business_plus_features", skip_enterprise: true do
    test "destroys associated EnterpriseInstallations" do
      org = create :business_plus_organization
      create :enterprise_installation, owner: org
      refute_empty org.enterprise_installations

      org.disable_business_plus_features(actor: org.admins.first)

      assert_empty org.reload.enterprise_installations
    end

    test "disables notification restrictions" do
      org = create :business_plus_organization
      create :verifiable_domain, owner: org, domain: "sub.github.com", verified: true
      org.enable_notification_restrictions(actor: org.admins.first, notify_members: false)
      assert_predicate org, :restrict_notifications_to_verified_domains?

      org.disable_business_plus_features(actor: org.admins.first)

      refute_predicate org.reload, :restrict_notifications_to_verified_domains?
    end

    test "disables IP allow list" do
      org = create :business_plus_organization
      create :ip_allowlist_entry, owner: org
      org.enable_ip_allowlist actor: org.admins.first
      assert_predicate org, :ip_allowlist_enabled?

      org.disable_business_plus_features(actor: org.admins.first)

      refute_predicate org.reload, :ip_allowlist_enabled?
    end

    test "disables IP allow list app access" do
      org = create :business_plus_organization
      create :ip_allowlist_entry, owner: org
      org.enable_ip_allowlist actor: org.admins.first
      org.enable_ip_allowlist_app_access actor: org.admins.first
      assert_predicate org, :ip_allowlist_enabled?
      assert_predicate org, :ip_allowlist_app_access_enabled?

      org.disable_business_plus_features(actor: org.admins.first)

      refute_predicate org.reload, :ip_allowlist_enabled?
      refute_predicate org, :ip_allowlist_app_access_enabled?
    end

    test "destroys Organization::SamlProvider" do
      org = create :business_plus_organization
      create :organization_saml_provider, organization: org
      assert org.saml_provider

      org.disable_business_plus_features(actor: org.admins.first)

      assert_nil org.reload.saml_provider
    end

    test "resets repository creation setting" do
      org = create :business_plus_organization
      org.config.set! \
        Configurable::MembersCanCreateRepositories::KEY,
        Configurable::MembersCanCreateRepositories::PUBLIC,
        org.admins.first,
        false

      org.disable_business_plus_features(actor: org.admins.first)

      assert_equal \
        Configurable::MembersCanCreateRepositories::ALL,
        org.config.get(Configurable::MembersCanCreateRepositories::KEY)
    end
  end
end

module SCIMMangedOrganizationSharedTests
  include ExternalGroupHelpers

  def test_prevent_removal_of_scim_managed_user_returns_false_if_the_user_is_not_a_member_of_the_organization
    refute @organization.prevent_removal_of_scim_managed_user?(user: @user, reason: :any)
  end

  def test_prevent_removal_of_scim_managed_user_returns_false_if_the_reason_is_invalid
    refute @organization.prevent_removal_of_scim_managed_user?(user: @organization_mixed_user, reason: :invalid)
  end

  def test_prevent_removal_of_scim_managed_user_returns_false_if_the_user_has_no_linked_team_membership_with_scope_derived
    refute @organization.prevent_removal_of_scim_managed_user?(user: @organization_explicit_user, reason: :derived)
  end

  def test_prevent_removal_of_et_managed_user_returns_false_if_the_user_has_no_linked_team_membership_with_scope_enterprise_team
    refute @organization.prevent_removal_of_scim_managed_user?(user: @organization_explicit_user, reason: :enterprise_team)
  end

  def test_prevent_removal_of_scim_managed_user_returns_true_if_the_user_has_linked_team_membership_with_scope_derived
    assert @organization.prevent_removal_of_scim_managed_user?(user: @organization_mixed_user, reason: :derived)
    assert @organization.prevent_removal_of_scim_managed_user?(user: @organization_derived_user, reason: :derived)
  end

  def test_prevent_removal_of_et_managed_user_returns_true_if_the_user_has_linked_team_membership_with_scope_enterprise_team
    user = create @user_factory, business: @business
    team = create :team, organization: @organization

    # Gives direct read abilities
    team.add_member(user)
    ability = Ability.user_direct_read_on_organization(actor_id: user.id, subject_id: @organization.id).pluck(:id)

    # Force enterprise team membership
    OrganizationMembershipEntry.create_entry(user: user, organization_id: @organization.id, ability_id: ability.first, derived: true, adder_id: team.id, adder_type: :enterprise_team)

    if EnterpriseTeam.enabled_for_organizations?(business: @business)
      assert @organization.prevent_removal_of_scim_managed_user?(user: user, reason: :enterprise_team)
    else
      refute @organization.prevent_removal_of_scim_managed_user?(user: user, reason: :enterprise_team)
    end
  end

  def test_prevent_removal_of_et_managed_user_returns_true_if_the_user_has_any_team_membership_with_scope_enterprise_team
    user = create @user_factory, business: @business
    team = create :team, organization: @organization

    # fakes direct read abilities
    ability_id = 1
    abilities = [{ id: ability_id }]
    Ability.stubs(:user_direct_read_on_organization).returns(abilities)

    # Force enterprise team membership
    OrganizationMembershipEntry.create_entry(user: user, organization_id: @organization.id, ability_id: ability_id, derived: true, adder_id: team.id, adder_type: :enterprise_team)

    assert @organization.prevent_removal_of_scim_managed_user?(user: user, reason: :any)
  end

  def test_prevent_removal_of_scim_managed_user_returns_true_if_the_user_has_any_team_membership_with_scope_any
    assert @organization.prevent_removal_of_scim_managed_user?(user: @organization_explicit_user, reason: :any)
    assert @organization.prevent_removal_of_scim_managed_user?(user: @organization_mixed_user, reason: :any)
    assert @organization.prevent_removal_of_scim_managed_user?(user: @organization_derived_user, reason: :any)
  end

  def test_prevent_removal_of_scim_managed_user_returns_false_if_the_user_is_removed_from_organization_with_scope_any
    assert @organization.prevent_removal_of_scim_managed_user?(user: @organization_explicit_user, reason: :any)

    perform_enqueued_jobs(only: [RemoveOrgMemberJob, RevokeOrgMembershipAbilitiesJob]) do
      @organization.remove_member(@organization_explicit_user)
    end

    refute @organization.prevent_removal_of_scim_managed_user?(user: @organization_explicit_user, reason: :any)
  end

  def test_prevent_removal_of_scim_managed_user_returns_false_if_the_user_was_removed_from_linked_team_with_scope_derived_with_reconcile_job
    GitHub.flipper[:disable_external_group_team_reconcile_job].disable

    assert @organization.prevent_removal_of_scim_managed_user?(user: @organization_derived_user, reason: :derived)
    assert @organization.prevent_removal_of_scim_managed_user?(user: @organization_derived_user, reason: :any)

    perform_enqueued_jobs(only: [RemoveOrgMemberJob, RevokeOrgMembershipAbilitiesJob]) do
      @derived_membership.destroy
    end

    reconcile_external_group_teams(external_group: @external_group)

    refute @organization.prevent_removal_of_scim_managed_user?(user: @organization_derived_user, reason: :derived)
    refute @organization.prevent_removal_of_scim_managed_user?(user: @organization_derived_user, reason: :any)
  end

  def test_prevent_removal_of_scim_managed_user_returns_true_if_the_user_was_removed_from_linked_team_but_has_explicit_membership_with_scope_any_with_reconcile_job
    GitHub.flipper[:disable_external_group_team_reconcile_job].disable

    assert @organization.prevent_removal_of_scim_managed_user?(user: @organization_mixed_user, reason: :any)
    assert @organization.prevent_removal_of_scim_managed_user?(user: @organization_mixed_user, reason: :derived)

    perform_enqueued_jobs(only: [RemoveOrgMemberJob, RevokeOrgMembershipAbilitiesJob]) do
      @mixed_membership.destroy
    end

    reconcile_external_group_teams(external_group: @external_group)

    refute @organization.prevent_removal_of_scim_managed_user?(user: @organization_mixed_user, reason: :derived)
    assert @organization.prevent_removal_of_scim_managed_user?(user: @organization_mixed_user, reason: :any)
  end

  def test_prevent_removal_of_scim_managed_user_returns_true_if_the_user_with_more_than_one_derived_membership_was_removed_from_one_of_two_team_with_scope_derived_with_reconcile_job
    another_external_group = create :external_group, business: @business
    external_membership = ExternalIdentityGroupMembership.create(
      external_group: another_external_group,
      external_identity: @organization_derived_user.external_identities.first,
    )
    reconcile_external_group_teams(external_group: another_external_group)

    another_team = create :team, organization: @organization
    external_group_team = ExternalGroupTeam.create(external_group: another_external_group, team: another_team)
    ExternalGroupTeamLinkJob.perform_now(external_group_team.id, caller: self.class.name)

    assert @organization.prevent_removal_of_scim_managed_user?(user: @organization_derived_user, reason: :derived)

    perform_enqueued_jobs(only: [RemoveOrgMemberJob, RevokeOrgMembershipAbilitiesJob]) do
      external_membership.destroy
    end
    reconcile_external_group_teams(external_group: another_external_group)

    assert @organization.prevent_removal_of_scim_managed_user?(user: @organization_derived_user, reason: :derived)
  end

  def test_add_member_adds_organization_membership_derived_entry
    refute_includes @organization.members, @user

    assert_difference ["OrganizationMembershipEntry.count"], 1 do
      T.unsafe(self).add_member_to_org(@organization, @user)

      refute @organization.prevent_removal_of_scim_managed_user?(user: @user, reason: :derived)
    end
  end

  def test_scim_managed_enterprise_returns_true
    assert_predicate @organization, :scim_managed_enterprise?
  end

  def test_parent_teams_search_for_does_not_return_teams_linked_to_external_groups
    linked_team = create :team, organization: @organization, privacy: :closed
    external_group_team = ExternalGroupTeam.create(external_group: @external_group, team: linked_team)
    ExternalGroupTeamLinkJob.perform_now(external_group_team.id, caller: self.class.name)

    unlinked_team = create :team, organization: @organization, privacy: :closed

    result = @organization.parent_teams_search_for(nil, @organization_admin)

    assert_includes result, unlinked_team
    refute_includes result, linked_team
  end
end

class EMUOrganizationTest < GitHub::TestCase
  include SCIMMangedOrganizationSharedTests
  include OrganizationHelper

  fixtures do
    @user_factory = :emu
    @business = create :business, :enterprise_managed
    @provider = create :business_saml_provider, business: @business

    @organization_admin = create :emu, business: @business
    @organization = create :organization, business: @business, admin: @organization_admin

    @user = create :emu, business: @business
    @guest_collaborator = create(:emu, :guest_collaborator, business: @business)

    @external_group = create :external_group, :with_members, business: @business, number_of_members: 2

    @mixed_membership = @external_group.members[0]
    @organization_mixed_user = @mixed_membership.external_identity.user
    add_member_to_org(@organization, @organization_mixed_user)

    @organization_explicit_user = create :emu, business: @business
    add_member_to_org(@organization, @organization_explicit_user)

    @derived_membership = @external_group.members[1]
    @organization_derived_user = @derived_membership.external_identity.user

    @team = create :team, organization: @organization
    external_group_team = ExternalGroupTeam.create(external_group: @external_group, team: @team)
    ExternalGroupTeamLinkJob.perform_now(external_group_team.id, caller: self.class.name)

    @another_team = create :team, organization: @organization
    another_external_group_team = ExternalGroupTeam.create(external_group: @external_group, team: @another_team)
    ExternalGroupTeamLinkJob.perform_now(another_external_group_team.id, caller: self.class.name)
  end

  context "#after_destroy" do
    test "destroys memex_project_links" do
      memex_project = create(:memex_project, owner: @organization)
      memex_template = create(:memex_template, memex_project: memex_project)
      memex_project_link = create(:memex_project_link, source_type: "Organization", source_id: @organization.id, memex_project: memex_project)

      assert_difference "MemexProjectLink.count", -1 do
        @organization.destroy
      end

      assert_nil MemexProjectLink.find_by(id: memex_project_link.id)
    end

    test "business user accounts are removed after destroy", skip_enterprise: true do
      assert_no_difference("BusinessUserAccount.count") do
        @organization.destroy
      end
    end

    test "organization membership entries are removed after destroy", skip_enterprise: true do
      emu = create :business, :enterprise_managed
      org_admin = create :emu, business: emu
      org = create :organization, business: emu, admin: org_admin
      add_member_to_org(org, create(:emu, business: emu))

      perform_enqueued_jobs(only: [DestroyDependentRecordsJob]) do
        assert_difference("OrganizationMembershipEntry.count", -2) do
          org.destroy
        end
      end

      assert_raises ActiveRecord::RecordNotFound do
        Organization.find(org.id)
      end
      assert_nil OrganizationMembershipEntry.find_by(organization_id: org.id)
    end
  end

  context "#remove_business_user_accounts_for_members?" do
    test "return false if organization is not enterprise managed", skip_enterprise: true do
      refute_predicate @organization, :remove_business_user_accounts_for_members?
    end
  end

  context "#enterprise_server_scim_enabled?" do
    test "returns false for EMU" do
      refute_predicate @organization, :enterprise_server_scim_enabled?
    end

    test "async returns false for EMU" do
      refute @organization.async_enterprise_server_scim_enabled?.sync
    end
  end

  context "#visible_repositories_for" do
    test "returns repos to emu by default when emu is member of an organization" do
      private_repo = create(:private_repository, :minimal, owner: @organization)
      internal_repo = create(:internal_repository, owner: @organization)
      add_member_to_org(@organization, @user, action: :read)
      repos = @organization.reload.visible_repositories_for(@user)

      assert repos.include?(internal_repo)
      assert repos.include?(private_repo)
    end

    test "does not return repos to guest collaborator emu by default" do
      private_repo = create(:private_repository, :minimal, owner: @organization)
      internal_repo = create(:internal_repository, owner: @organization)
      repos = @organization.reload.visible_repositories_for(@guest_collaborator)

      refute repos.include?(internal_repo)
      refute repos.include?(private_repo)
    end

    test "returns repos to guest collaborator emu who belongs to a team" do
      group_with_team = create :external_group, :with_team, business: @business

      team = group_with_team.external_group_teams.first.team
      org = team.organization

      ExternalIdentityGroupMembership.create(external_group: group_with_team, external_identity: @guest_collaborator.external_identities.first)

      team.add_member(@guest_collaborator)

      ExternalIdentityGroupMembership.create(external_group: @external_group, external_identity: @guest_collaborator.external_identities.first)
      externally_managed_team = create :team, organization: @organization
      external_group_team = ExternalGroupTeam.create(external_group: @external_group, team: externally_managed_team)
      ExternalGroupTeamLinkJob.perform_now(external_group_team.id, caller: self.class.name)

      externally_managed_team.add_member(@guest_collaborator)

      assert externally_managed_team.member?(@guest_collaborator)
      assert org.member?(@guest_collaborator)

      private_repo = create(:private_repository, :minimal, owner: org)
      internal_repo = create(:internal_repository, owner: org)
      private_repo.add_team(externally_managed_team, action: :read)
      internal_repo.add_team(externally_managed_team, action: :read)
      repos = org.reload.visible_repositories_for(@guest_collaborator)

      assert repos.include?(internal_repo)
      assert repos.include?(private_repo)
    end

    test "returns repos to guest collaborator emu who belongs to an org" do
      org = create :organization, business: @business, admin: @organization_admin
      add_member_to_org(org, @guest_collaborator, action: :read)

      assert org.member?(@guest_collaborator)

      private_repo = create(:private_repository, :minimal, owner: org)
      internal_repo = create(:internal_repository, owner: org)
      repos = org.reload.visible_repositories_for(@guest_collaborator)

      assert repos.include?(internal_repo)
      assert repos.include?(private_repo)
    end

    test "does not return repos to guest collaborator emu who belongs to an org with default permission none" do
      perform_enqueued_jobs(only: [SyncOrganizationDefaultRepositoryPermissionJob]) do
        org = create(:organization, admin: @organization_admin, business: @business)
        org.update_default_repository_permission(:none, actor: @organization_admin)
        add_member_to_org(org, @guest_collaborator, action: :read)

        assert org.member?(@guest_collaborator)

        private_repo = create(:private_repository, :minimal, owner: org)
        internal_repo = create(:internal_repository, owner: org)
        repos = org.reload.visible_repositories_for(@guest_collaborator)

        refute repos.include?(internal_repo)
        refute repos.include?(private_repo)
      end
    end
  end

  context "#guest_collaborators" do
    test "returns guest collaborators associated with the org" do
      GitHub.flipper[:members_without_2fa_allowed].disable

      org = create :organization, business: @business, admin: @organization_admin
      team = create :team, organization: org
      team_2 = create :team, organization: org
      guest_collaborator = create(:emu, :guest_collaborator, business: @business)
      guest_collaborator_2 = create(:emu, :guest_collaborator, business: @business)
      guest_collaborator_3 = create(:emu, :guest_collaborator, business: @business)
      team.add_member(guest_collaborator)
      add_member_to_org(org, guest_collaborator_2, action: :read)
      assert_same_elements [guest_collaborator, guest_collaborator_2], org.guest_collaborators

      team_2.add_member(guest_collaborator)
      assert_same_elements [guest_collaborator, guest_collaborator_2], org.guest_collaborators

      team_2.add_member(guest_collaborator_3)
      assert_same_elements [guest_collaborator, guest_collaborator_2, guest_collaborator_3], org.guest_collaborators

      add_member_to_org(org, guest_collaborator_3, action: :read)
      assert_same_elements [guest_collaborator, guest_collaborator_2, guest_collaborator_3], org.guest_collaborators
      assert_same_elements [guest_collaborator], org.guest_collaborators(guest_collaborator.login)
    end

    context "#add_member" do
      test "query counts stay the same for EMUs" do
        GitHub.flipper[:add_org_member_bulk_refactor].disable
        GitHub.flipper[:members_without_2fa_allowed].disable
        GitHub.flipper[:collaborator_cache_write].disable
        GitHub.flipper[:collaborator_cache_read].disable

        emu = create :emu, business: @business
        ExternalIdentityGroupMembership.create(external_group: @external_group, external_identity: emu.external_identities.first)
        another_externally_managed_team = create :team, organization: @organization
        external_group_team = ExternalGroupTeam.create(external_group: @external_group, team: another_externally_managed_team)

        # Expect 1 extra queries in single tenant enterprise environments, because they hit KV directly
        # when the user contribution history changes
        expected_query_count = TestEnv.test_all_features? ? 73 : 20
        expected_query_count += 1 if GitHub.single_tenant_enterprise?

        assert_query_count(expected_query_count, ignore_feature_flags: true) do
          add_member_to_org(@organization, emu)
        end
      end

      test "multiple membership add query counts stay the same for EMUs" do
        GitHub.flipper[:add_org_member_bulk_refactor].disable
        GitHub.flipper[:members_without_2fa_allowed].disable
        GitHub.flipper[:collaborator_cache_write].disable
        GitHub.flipper[:collaborator_cache_read].disable

        emus = create_list(:emu, 10, business: @business).each do |emu|
          ExternalIdentityGroupMembership.create(external_group: @external_group, external_identity: emu.external_identities.first)
        end
        another_externally_managed_team = create :team, organization: @organization
        external_group_team = ExternalGroupTeam.create(external_group: @external_group, team: another_externally_managed_team)

        # Expect 10 extra queries in single tenant enterprise environments, because they hit KV directly
        # when the user contribution history changes
        expected_query_count = TestEnv.test_all_features? ? 685 : 146
        expected_query_count += 10 if GitHub.single_tenant_enterprise?

        assert_query_count(expected_query_count, ignore_feature_flags: true) do
          emus.each do |emu|
            add_member_to_org(@organization, emu)
          end
        end
      end

      test "OrganizationMembershipEntry gets created appropriate by ET" do
        EnterpriseTeam.stubs(:enabled_for_organizations?).returns(true)

        et = create :enterprise_team, business: @business
        et_managed_team = create :team, organization: @organization
        EnterpriseTeamOrganizationMapping.create(enterprise_team: et, organization: @organization, team: et_managed_team)

        emu = create :emu, business: @business
        @organization.add_member(emu, team: et_managed_team, caller_type: :enterprise_team)

        ability_id = Ability.user_direct_read_on_organization(actor_id: emu.id, subject_id: @organization.id).pluck(:id)
        assert OrganizationMembershipEntry.enterprise_team_managed?(user: emu, organization_id: @organization.id, ability_id: ability_id)
      end

      test "OrganizationMembershipEntry gets created appropriate by ET when not scim_managed_enterprise" do
        EnterpriseTeam.stubs(:enabled_for_organizations?).returns(true)
        @organization.stubs(:scim_managed_enterprise?).returns(false)

        et = create :enterprise_team, business: @business
        et_managed_team = create :team, organization: @organization
        EnterpriseTeamOrganizationMapping.create(enterprise_team: et, organization: @organization, team: et_managed_team)

        emu = create :emu, business: @business
        @organization.add_member(emu, team: et_managed_team, caller_type: :enterprise_team)

        ability_id = Ability.user_direct_read_on_organization(actor_id: emu.id, subject_id: @organization.id).pluck(:id)
        assert OrganizationMembershipEntry.enterprise_team_managed?(user: emu, organization_id: @organization.id, ability_id: ability_id)
      end

      test "OrganizationMembershipEntry is not created by ET when team isn't ET managed" do
        EnterpriseTeam.stubs(:enabled_for_organizations?).returns(true)

        et = create :enterprise_team, business: @business
        regular_team = create :team, organization: @organization

        emu = create :emu, business: @business
        @organization.add_member(emu, team: regular_team)

        ability_id = Ability.user_direct_read_on_organization(actor_id: emu.id, subject_id: @organization.id).pluck(:id)
        refute OrganizationMembershipEntry.enterprise_team_managed?(user: emu, organization_id: @organization.id, ability_id: ability_id)
      end

      test "OrganizationMembershipEntry gets created appropriately by admin (ff disabled)" do
        EnterpriseTeam.stubs(:enabled_for_organizations?).returns(false)

        emu = create :emu, business: @business
        ExternalIdentityGroupMembership.create(external_group: @external_group, external_identity: emu.external_identities.first)
        another_externally_managed_team = create :team, organization: @organization
        external_group_team = ExternalGroupTeam.create(external_group: @external_group, team: another_externally_managed_team)

        # creates membership in organization + results in an organization membership entry
        add_member_to_org(@organization, emu)

        entries = OrganizationMembershipEntry.where(user_id: emu.id, organization_id: @organization.id)
        assert_equal 1, entries.count
        assert_equal :admin.to_s, entries.first&.adder_type
      end

      test "OrganizationMembershipEntry gets created appropriately be external team (ff disabled)" do
        EnterpriseTeam.stubs(:enabled_for_organizations?).returns(false)

        emu = create :emu, business: @business
        ExternalIdentityGroupMembership.create(external_group: @external_group, external_identity: emu.external_identities.first)
        another_externally_managed_team = create :team, organization: @organization
        external_group_team = ExternalGroupTeam.create(external_group: @external_group, team: another_externally_managed_team)

        @team.add_member(emu)

        entries = OrganizationMembershipEntry.where(user_id: emu.id, organization_id: @organization.id)
        assert_equal 1, entries.count
        assert_equal :external_team.to_s, entries.first&.adder_type
      end

      test "OrganizationMembershipEntry gets created appropriately by admin (ff enabled)" do
        EnterpriseTeam.stubs(:enabled_for_organizations?).returns(true)

        emu = create :emu, business: @business
        ExternalIdentityGroupMembership.create(external_group: @external_group, external_identity: emu.external_identities.first)
        another_externally_managed_team = create :team, organization: @organization
        external_group_team = ExternalGroupTeam.create(external_group: @external_group, team: another_externally_managed_team)

        # creates membership in organization + results in an organization membership entry
        add_member_to_org(@organization, emu)

        entries = OrganizationMembershipEntry.where(user_id: emu.id, organization_id: @organization.id)
        assert_equal 1, entries.count
        assert_equal :admin.to_s, entries.first&.adder_type
      end

      test "OrganizationMembershipEntry gets created appropriately by external team (ff enabled)" do
        EnterpriseTeam.stubs(:enabled_for_organizations?).returns(true)

        emu = create :emu, business: @business
        ExternalIdentityGroupMembership.create(external_group: @external_group, external_identity: emu.external_identities.first)
        another_externally_managed_team = create :team, organization: @organization
        external_group_team = ExternalGroupTeam.create(external_group: @external_group, team: another_externally_managed_team)

        @team.add_member(emu)

        entries = OrganizationMembershipEntry.where(user_id: emu.id, organization_id: @organization.id)
        assert_equal 1, entries.count
        assert_equal :external_team.to_s, entries.first&.adder_type
      end

      test "EMUs get appropriate organization membership entries" do
        emu = create :emu, business: @business
        ExternalIdentityGroupMembership.create(external_group: @external_group, external_identity: emu.external_identities.first)
        another_externally_managed_team = create :team, organization: @organization
        external_group_team = ExternalGroupTeam.create(external_group: @external_group, team: another_externally_managed_team)

        # creates membership in organization + results in an organization membership entry
        add_member_to_org(@organization, emu)

        assert @organization.member?(emu)

        # creates membership in team + will add a derived organization membership entry
        @team.add_member(emu)
        # creates membership in team + will add a derived organization membership entry
        ExternalGroupTeamLinkJob.perform_now(external_group_team.id, caller: self.class.name)

        assert @team.member?(emu)
        assert another_externally_managed_team.member?(emu)

        refute_nil ability = emu.get_organization_ability(@organization)

        org_membership_entries = OrganizationMembershipEntry.where(user_id: emu.id, organization_id: @organization.id, ability_id: ability.id)
        assert_same_elements [another_externally_managed_team.id, @team.id, @organization.admins.first.id], org_membership_entries.pluck(:adder_id)
        assert_same_elements %w[external_team external_team admin], org_membership_entries.pluck(:adder_type)
      end

      test "guest collaborators added to a an external team in an org are org members" do
        ExternalIdentityGroupMembership.create(external_group: @external_group, external_identity: @guest_collaborator.external_identities.first)

        @team.add_member(@guest_collaborator)

        refute_nil ability = @guest_collaborator.get_organization_ability(@organization)
        org_membership_entries = OrganizationMembershipEntry.where(user_id: @guest_collaborator.id, organization_id: @organization.id, ability_id: ability.id)

        assert @team.member?(@guest_collaborator)
        assert @organization.member?(@guest_collaborator)
        assert_same_elements [@team.id], org_membership_entries.pluck(:adder_id)
        assert_same_elements ["external_team"], org_membership_entries.pluck(:adder_type)

        normal_team = create :team, organization: @organization

        normal_team.add_member(@guest_collaborator)

        assert @organization.member?(@guest_collaborator)
        refute_nil ability = @guest_collaborator.get_organization_ability(@organization)

        org_membership_entries = OrganizationMembershipEntry.where(user_id: @guest_collaborator.id, organization_id: @organization.id, ability_id: ability.id)

        assert_same_elements [@organization.admins.first.id, @team.id], org_membership_entries.pluck(:adder_id)
        assert_same_elements %w[admin external_team], org_membership_entries.pluck(:adder_type)
      end

      test "raise ActiveRecord::RecordNotUnique when granting ability raises ActiveRecord::RecordNotUnique and rescue_not_unique false" do
        GitHub.flipper[:organization_add_remove_orchestrator].disable
        Ability::Grant.any_instance.stubs(:apply).raises(ActiveRecord::RecordNotUnique)

        assert_raises ActiveRecord::RecordNotUnique do
          @organization.add_member(@user, rescue_not_unique: false)
        end
      end
    end

    context "#bulk_add_members" do
      test "query counts stay the same and lower than single user org add for EMUs" do
        GitHub.flipper[:collaborator_cache_write].disable
        GitHub.flipper[:collaborator_cache_read].disable
        emu = create :emu, business: @business
        ExternalIdentityGroupMembership.create(external_group: @external_group, external_identity: emu.external_identities.first)
        another_externally_managed_team = create :team, organization: @organization
        external_group_team = ExternalGroupTeam.create(external_group: @external_group, team: another_externally_managed_team)

        # Expect 1 extra queries in single tenant enterprise environments, because they hit KV directly
        # when the user contribution history changes
        expected_query_count = TestEnv.test_all_features? ? 24 : 18
        expected_query_count += 1 if GitHub.single_tenant_enterprise?

        assert_query_count(expected_query_count, ignore_feature_flags: true) do
          @organization.bulk_add_members [emu]
        end
      end

      test "bulk membership add query counts stay the same for EMUs" do
        GitHub.flipper[:collaborator_cache_write].disable
        GitHub.flipper[:collaborator_cache_read].disable
        emus = create_list(:emu, 10, business: @business).each do |emu|
          ExternalIdentityGroupMembership.create(external_group: @external_group, external_identity: emu.external_identities.first)
        end
        another_externally_managed_team = create :team, organization: @organization
        external_group_team = ExternalGroupTeam.create(external_group: @external_group, team: another_externally_managed_team)

        # Expect 1 extra queries in single tenant enterprise environments, because they hit KV directly
        # when the user contribution history changes
        expected_query_count = TestEnv.test_all_features? ? 33 : 36
        expected_query_count += 1 if GitHub.single_tenant_enterprise?

        assert_query_count(expected_query_count, ignore_feature_flags: true) do
          @organization.bulk_add_members emus
        end
      end

      test "EMUs get appropriate organization membership entries" do
        emu = create :emu, business: @business
        ExternalIdentityGroupMembership.create(external_group: @external_group, external_identity: emu.external_identities.first)
        another_externally_managed_team = create :team, organization: @organization
        external_group_team = ExternalGroupTeam.create(external_group: @external_group, team: another_externally_managed_team)

        # creates membership in organization + results in an organization membership entry
        @organization.bulk_add_members [emu]

        assert @organization.member?(emu)

        # creates membership in team + will add a derived organization membership entry
        @team.add_member(emu)
        # creates membership in team + will add a derived organization membership entry
        ExternalGroupTeamLinkJob.perform_now(external_group_team.id, caller: self.class.name)

        assert @team.member?(emu)
        assert another_externally_managed_team.member?(emu)

        refute_nil ability = emu.get_organization_ability(@organization)

        org_membership_entries = OrganizationMembershipEntry.where(user_id: emu.id, organization_id: @organization.id, ability_id: ability.id)
        assert_same_elements [another_externally_managed_team.id, @team.id, @organization.admins.first.id], org_membership_entries.pluck(:adder_id)
        assert_same_elements %w[external_team external_team admin], org_membership_entries.pluck(:adder_type)
      end

      test "sets the enterprise cloud trial for business plus for added members" do
        emus = create_list(:emu, 2, business: @business).each do |emu|
          ExternalIdentityGroupMembership.create(external_group: @external_group, external_identity: emu.external_identities.first)
        end
        another_externally_managed_team = create :team, organization: @organization
        external_group_team = ExternalGroupTeam.create(external_group: @external_group, team: another_externally_managed_team)

        emus.each do |emu|
          refute_equal :enterprise_cloud_trial, GlobalNoticeNext.new(viewer: emu).current_notice_name
        end

        perform_enqueued_jobs(only: [OrganizationOrchestrationJob, EnterpriseCloudTrialNoticeForNewMembersJob]) do
          @organization.bulk_add_members emus
        end

        emus.each do |emu|
          assert_equal :enterprise_cloud_trial, GlobalNoticeNext.new(viewer: emu.reload).current_notice_name
        end
      end
    end

    context "invitation_rate_limit_exceeded?" do
      if GitHub.enterprise?
        test "returns false in Enterprise mode" do
          Organization.any_instance.expects(:rate_limit_increment).never  # Rate limit check should never happen
          org = create :organization

          refute org.invitation_rate_limit_exceeded?
        end
      else
        test "returns true if the org has exceeded the rate limit" do
          Organization.any_instance.expects(:rate_limit_increment).returns(stub(at_limit?: true))
          org = create :organization

          assert org.invitation_rate_limit_exceeded?
        end

        test "returns false if the org has not exceeded the rate limit" do
          Organization.any_instance.expects(:rate_limit_increment).returns(stub(at_limit?: false))
          org = create :organization

          refute org.invitation_rate_limit_exceeded?
        end

        test "returns false if the org is EMU" do
          Organization.any_instance.expects(:rate_limit_increment).never  # Rate limit check should never happen
          assert_predicate @organization, :enterprise_managed_user_enabled?

          refute @organization.invitation_rate_limit_exceeded?
        end
      end
    end
  end

  context "#visible_user_ids_for" do
    test ":guest_collaborators uses guest_collaborators method internally for filtering" do
      @organization.expects(:guest_collaborators).once.returns([])
      @organization.visible_user_ids_for(@organization_admin, type: :guest_collaborator)
    end

    test ":guest_collaborators returns all guest collaborators in org" do
      @organization.add_member @guest_collaborator
      assert_same_elements @organization.guest_collaborators, [@guest_collaborator]
      assert_same_elements @organization.guest_collaborators.pluck(:id), @organization.visible_user_ids_for(@organization_admin, type: :guest_collaborator)
    end

    test ":guest_collaborators returns an empty array when the org is not an EMU" do
      admin = create :user
      non_emu_org = create :organization, admin: admin

      refute non_emu_org.enterprise_managed_user_enabled?

      non_emu_org.expects(:guest_collaborators).never
      assert_empty non_emu_org.visible_user_ids_for(admin, type: :guest_collaborator)
    end
  end
end unless GitHub.single_business_environment?

class GHESWithSCIMOrganizationTest < GitHub::TestCase
  include AuthenticationHelpers::SAML
  include SCIMMangedOrganizationSharedTests
  include OrganizationHelper

  fixtures do
    setup_saml_auth_mode(with_scim: true)

    @user_factory = :ghes_scim_user

    @business = create(:global_business)
    @provider = @business.external_provider

    @organization_admin = create :ghes_scim_user, business: @business
    @organization = create :organization, business: @business, admin: @organization_admin

    @user = create :ghes_scim_user, business: @business

    @external_group = create :external_group, :with_members, business: @business, number_of_members: 2

    @mixed_membership = @external_group.members[0]
    @organization_mixed_user = @mixed_membership.external_identity.user
    add_member_to_org(@organization, @organization_mixed_user)

    @organization_explicit_user = create :ghes_scim_user, business: @business
    add_member_to_org(@organization, @organization_explicit_user)

    @derived_membership = @external_group.members[1]
    @organization_derived_user = @derived_membership.external_identity.user

    @team = create :team, organization: @organization
    external_group_team = ExternalGroupTeam.create(external_group: @external_group, team: @team)
    ExternalGroupTeamLinkJob.perform_now(external_group_team.id, caller: self.class.name)
  end

  setup do
    setup_saml_auth_mode(with_scim: true)
  end

  context "#enterprise_server_scim_enabled?" do
    test "returns true for GHES with SCIM" do
      assert_predicate @organization, :enterprise_server_scim_enabled?
    end

    test "async returns true for GHES with SCIM" do
      assert @organization.async_enterprise_server_scim_enabled?.sync
    end
  end

  context "#add_member" do
    test "user without external identity (basic auth) can be added to organization with GHES SCIM enabled" do
      user = create :user, business: @business
      assert_empty user.external_identities

      @organization.add_member(user)

      assert @organization.member?(user)
    end
  end

  context "#bulk_add_members" do
    test "users without external identities (basic auth) can be added to organization with GHES SCIM enabled" do
      user1 = create :user, business: @business
      user2 = create :user, business: @business
      assert_empty user1.external_identities
      assert_empty user2.external_identities

      @organization.bulk_add_members([user1, user2])

      assert @organization.member?(user1)
      assert @organization.member?(user2)
    end
  end
end if GitHub.single_business_environment?

class MultiTenantOrganizationTest < GitHub::TestCase
  include OrganizationHelper

  PackageNamespaceResultMock = Struct.new(
    :retired_namespace_exists,
    :first_retired_namespace
  )
  SHARED_ORG_NAME = "engineering"

  fixtures do
    on_multi_tenant_enterprise do
      @user_factory = :emu
      @user = create :emu
      @business = @user.enterprise_managed_business
      @org = create :organization, :with_org_namespacing, name: SHARED_ORG_NAME, business: @business

      @other_user = create :emu
      @other_business = @other_user.enterprise_managed_business
    end
  end

  setup do
    on_multi_tenant_enterprise
    GitHub::CurrentTenant.set(@business)
    res = PackageNamespaceResultMock.new(retired_namespace_exists: false, first_retired_namespace: "")
    ::PackageRegistry::Twirp::MetadataClient.any_instance.stubs(:check_packages_retired_namespace).returns(res)
  end

  teardown do
    GitHub::CurrentTenant.remove
  end

  context "default scope" do
    test "query by login finds org in CurrentTenant business" do
      result = Organization.where(login: @org.name)

      assert_equal 1, result.count
      assert_equal @org, result.first
    end

    test "query by login returns no orgs when scoped to a different business" do
      GitHub::CurrentTenant.set(@other_business)

      result = Organization.where(login: @org.name)

      assert_empty result
    end

    test "unscoped query returns orgs from other business" do
      GitHub::CurrentTenant.set(@other_business)

      GitHub::CurrentTenant.unscope do
        result = Organization.where(login: @org.login)

        assert_equal 1, result.count
        assert_equal @org, result.first
        refute_equal GitHub::CurrentTenant.get.id, result.first&.business_id
      end
    end

    # Skipping because we still have UNIQUE KEY `index_users_on_login` for users table
    # which prevents us from creating orgs with the same name in different businesses.
    # Once we remove the uniqueness from that index, we can enable this test.
    test "query by login does not include org from other business" do
      skip

      @other_org = create :organization, :with_org_namespacing, name: SHARED_ORG_NAME, business: @other_business

      unscoped_result = GitHub::CurrentTenant.unscope { Organization.where(login: SHARED_ORG_NAME) }
      assert_equal 2, unscoped_result.count
      assert_same_elements unscoped_result, [@org, @other_org]

      result = Organization.where(login: SHARED_ORG_NAME)
      assert_equal 1, result.count
      assert_equal @org, result.first
    end
  end

  context "#scope_to_current_tenant?" do
    test "true if CurrentTenant is scoped and Organization" do
      assert Organization.scope_to_current_tenant?
    end
  end
end unless GitHub.single_business_environment?
