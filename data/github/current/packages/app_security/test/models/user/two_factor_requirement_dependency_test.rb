# typed: true
# frozen_string_literal: true

require "test_helper"

class UserTwoFactorRequirementRelationsTest < GitHub::TestCase
  test "destroys two_factor_requirement_metadata when user is destroyed" do
    user = create(:user)
    create(:two_factor_requirement_metadata, user_id: user.id)
    refute_empty TwoFactorRequirementMetadata.where(user_id: user.id)

    user.destroy

    assert_empty TwoFactorRequirementMetadata.where(user_id: user.id)
  end
end

class UserTwoFactorRequirementMetByTest < GitHub::TestCase
  test "returns true" do
    assert_equal true, User.new.two_factor_requirement_met_by?(nil)
  end
end

class UserTwoFactorAuthCanBeDisabledTest < GitHub::TestCase
  include ResiliencyHelpers

  fixtures do
    @org_2fa = create(:two_factor_credential_org)
    @org_2fa.allow_private_repository_forking(actor: @org_2fa.admins.first)
    @org_non_2fa = create(:organization)
  end

  test "returns false if 2FA User is a member of any 2FA-requiring orgs" do
    GitHub.flipper[:members_without_2fa_allowed].disable
    user = create(:two_factor_credential_user)
    @org_non_2fa.add_member(user)
    @org_2fa.add_member(user)
    assert @org_2fa.members.exists?(user.id)

    refute_predicate user, :two_factor_auth_can_be_disabled?
  end

  test "returns false if :members_without_2fa_allowed flag not enabled for all 2FA-requiring orgs" do
    user = create(:two_factor_credential_user)
    another_2fa_org = create(:two_factor_credential_org)
    another_2fa_org.allow_private_repository_forking(actor: another_2fa_org.admins.first)
    @org_non_2fa.add_member(user)
    @org_2fa.add_member(user)
    another_2fa_org.add_member(user)

    assert @org_non_2fa.members.exists?(user.id)
    assert @org_2fa.members.exists?(user.id)
    assert another_2fa_org.members.exists?(user.id)

    GitHub.flipper[:members_without_2fa_allowed].disable
    GitHub.flipper[:members_without_2fa_allowed].enable(@org_2fa)
    GitHub.flipper[:members_without_2fa_allowed].enable(@org_non_2fa)

    refute_predicate user, :two_factor_auth_can_be_disabled?
  end

  test "returns false if 2FA User is a billing manager of any 2FA-requiring orgs" do
    user = create(:two_factor_credential_user)
    @org_non_2fa.add_member(user)
    @org_2fa.billing.add_manager(user, actor: @org_2fa.admin)
    refute @org_2fa.members.exists?(user.id)

    refute_predicate user, :two_factor_auth_can_be_disabled?
  end

  test "returns false if 2FA User is an outside collaborator on a public repo of any 2FA-requiring orgs" do
    GitHub.flipper[:members_without_2fa_allowed].disable
    user = create(:two_factor_credential_user)
    @org_non_2fa.add_member(user)
    repo = create(:repository, owner: @org_2fa)
    repo.add_member(user)

    refute_predicate user, :two_factor_auth_can_be_disabled?
  end

  test "returns false if 2FA User is an outside collaborator on a private repo of any 2FA-requiring orgs" do
    GitHub.flipper[:members_without_2fa_allowed].disable
    user = create(:two_factor_credential_user)
    @org_non_2fa.add_member(user)
    repo = create(:private_repository, owner: @org_2fa)
    repo.add_member(user)
    assert @org_2fa.user_is_outside_collaborator?(user.id)

    refute_predicate user, :two_factor_auth_can_be_disabled?
  end

  test "returns false if 2FA User is an outside collaborator on a fork of a private repo of any 2FA-requiring orgs" do
    GitHub.flipper[:members_without_2fa_allowed].disable
    forker = create(:two_factor_credential_user)
    @org_2fa.add_member(forker)
    user = create(:two_factor_credential_user)
    repo = create(:private_repository, owner: @org_2fa)
    forked_repo = create(:fork_repository, forker: forker, fork_repo: repo)
    forked_repo.add_member(user)
    assert @org_2fa.user_is_outside_collaborator?(user.id)

    refute_predicate user, :two_factor_auth_can_be_disabled?
  end

  test "returns false if user is an owner of any 2FA-requiring business" do
    user = create :two_factor_credential_user
    business = create :business, owners: [create(:two_factor_credential_user)]
    business.enable_two_factor_required actor: business.owners.first, force: true
    business.add_owner user, actor: business.owners.first
    assert business.owner?(user)

    refute_predicate user, :two_factor_auth_can_be_disabled?
  end

  test "returns false if user is a billing manager of any 2FA-requiring business" do
    user = create :two_factor_credential_user
    business = create :business, owners: [create(:two_factor_credential_user)]
    business.enable_two_factor_required actor: business.owners.first, force: true
    business.billing.add_manager user, actor: business.owners.first
    assert business.billing_manager?(user)

    refute_predicate user, :two_factor_auth_can_be_disabled?
  end

  test "returns true if user is only an owner of a non-2FA-requiring business" do
    user = create :two_factor_credential_user
    business = create :business
    business.add_owner user, actor: business.owners.first
    assert business.owner?(user)

    assert_predicate user, :two_factor_auth_can_be_disabled?
  end

  test "returns true if user is only a billing manager of a non-2FA-requiring business" do
    user = create :two_factor_credential_user
    business = create :business
    business.billing.add_manager user, actor: business.owners.first
    assert business.billing_manager?(user)

    assert_predicate user, :two_factor_auth_can_be_disabled?
  end

  test "returns true if 2FA User is an outside collaborator on a fork of a public repo of any 2FA-requiring orgs" do
    forker = create(:two_factor_credential_user)
    @org_2fa.add_member(forker)
    user = create(:two_factor_credential_user)
    repo = create(:repository, owner: @org_2fa)
    forked_repo = create(:fork_repository, forker: forker, fork_repo: repo)
    forked_repo.add_member(user)
    refute @org_2fa.user_is_outside_collaborator?(user.id)

    assert_predicate user, :two_factor_auth_can_be_disabled?
  end

  test "returns true if 2FA User is affiliated with no 2FA-requiring orgs" do
    user = create(:two_factor_credential_user)
    @org_non_2fa.add_member(user)

    assert_predicate user, :two_factor_auth_can_be_disabled?
  end

  test "returns true if 2FA User is affiliated with no orgs" do
    user = create(:two_factor_credential_user)

    assert_predicate user, :two_factor_auth_can_be_disabled?
  end

  test "returns false if User does not have 2FA enabled" do
    user = create(:user)

    refute_predicate user, :two_factor_auth_can_be_disabled?
  end

  test "returns false if User has two_factor_locked" do
    user = create(:user)
    make_two_factor_credential(user)
    user.lock_two_factor do
      refute user.two_factor_auth_can_be_disabled?
    end
  end

  test "returns true if User has two_factor_locked and KV is unavailable" do
    user = create(:user)
    make_two_factor_credential(user)
    assert_nothing_raised do
      user.lock_two_factor do
        prevent_connections_to(ApplicationRecord::Authnd) do
          assert user.two_factor_auth_can_be_disabled?
        end
      end
    end
  end

  test "returns true if KV is unavailable while obtaining 2FA lock" do
    user = create(:user)
    make_two_factor_credential(user)

    assert_nothing_raised do
      prevent_connections_to(ApplicationRecord::Authnd) do
        user.lock_two_factor do
          assert user.two_factor_auth_can_be_disabled?
        end
      end
    end
  end
end

class UserAffiliatedWithOrganizationTest < GitHub::TestCase
  setup do
    @org = create(:organization)
    @org.allow_private_repository_forking(actor: @org.admins.first)
    @repo = create(:private_repository, owner: @org)
  end

  test "returns true if a direct member" do
    user = create(:user)
    @org.add_member(user)

    is_affiliate = user.affiliated_with_organization?(@org)

    assert_equal true, is_affiliate
  end

  test "[filter] includes direct member, excludes random org" do
    user = create(:user)
    @org.add_member(user)
    org2 = create(:organization)

    result = user.filter_affiliated_organizations([@org, org2])

    assert_equal 1, result.size
    assert_equal @org, result.first
  end

  test "returns true if a admin" do
    admin = @org.admins.first
    is_affiliate = admin.affiliated_with_organization?(@org)
    assert_equal true, is_affiliate
  end

  test "[filter] includes admin, excludes random org" do
    admin = @org.admins.first
    org2 = create(:organization)

    result = admin.filter_affiliated_organizations([@org, org2])

    assert_equal 1, result.size
    assert_equal @org, result.first
  end

  test "returns true if a billing manager" do
    user = create(:user)
    @org.billing.add_manager(user, actor: @org.admin)

    is_affiliate = user.affiliated_with_organization?(@org)

    assert_equal true, is_affiliate
  end

  test "[filter] returns a billing manager, excludes random org" do
    user = create(:user)
    @org.billing.add_manager(user, actor: @org.admin)
    assert @org.billing_manager?(user)
    org2 = create(:organization)

    result = user.filter_affiliated_organizations([@org, org2])

    assert_equal 1, result.size
    assert_equal @org, result.first
  end

  test "returns true if an outside collaborator on a private repo" do
    user = create(:user)
    @repo.add_member(user)

    is_affiliate = user.affiliated_with_organization?(@org)

    assert_equal true, is_affiliate
  end

  test "returns true if an outside collaborator on a public repo" do
    user = create(:user)
    public_repo = create(:repository, owner: @org)
    public_repo.add_member(user)

    is_affiliate = user.affiliated_with_organization?(@org)

    assert_equal true, is_affiliate
  end

  test "returns false if an outside collaborator on a fork of a public repo" do
    user = create(:user)
    forker = create(:user)
    @org.add_member(forker)
    public_repo = create(:repository, owner: @org)
    fork = create(:fork_repository, forker: forker, fork_repo: public_repo)
    fork.add_member(user)

    is_affiliate = user.affiliated_with_organization?(@org)

    assert_equal false, is_affiliate
  end

  test "returns true if an outside collaborator on a fork of a private repo" do
    user = create(:user)
    forker = create(:user)
    @org.add_member(forker)
    fork = create(:fork_repository, forker: forker, fork_repo: @repo)
    fork.add_member(user)

    is_affiliate = user.affiliated_with_organization?(@org)

    assert_equal true, is_affiliate
  end

  test "returns false if an outside collaborator, but not include_collaboration" do
    user = create(:user)
    @repo.add_member(user)

    is_affiliate = user.affiliated_with_organization?(@org, include_collaboration: false)

    assert_equal false, is_affiliate
  end
end

class UserAffiliatedOrganizationsWithTwoFactorRequirementTest < GitHub::TestCase
  test "returns affiliated organizations that require 2FA" do
    # the user in question
    user = create(:two_factor_credential_user)
    # owns org_owner
    org_owner = create(:two_factor_credential_org, admin: user)
    # is a member of org_member
    org_member = create(:two_factor_credential_org)
    org_member.add_member(user)
    # is a billing manager (but not a member) on org_billing
    org_billing = create(:two_factor_credential_org)
    org_billing.billing.add_manager(user, actor: org_billing.admin)
    # is a member of org_non_2fa, which doesn't require 2FA
    org_non_2fa = create(:organization)
    org_non_2fa.add_member(user)
    # is an outside collaborator on an org that doesn't require 2FA
    org_oc_direct_non_2fa = create(:organization)
    create(:private_repository, owner: org_oc_direct_non_2fa).add_member(user)
    # is an outside collaborator on a 2FA-requiring org's public repo
    org_oc_direct_public = create(:two_factor_credential_org)
    create(:repository, owner: org_oc_direct_public).add_member(user)
    # is an outside collaborator on a 2FA-requiring org's private repo
    org_oc_direct = create(:two_factor_credential_org)
    create(:private_repository, owner: org_oc_direct).add_member(user)
    # is an outside collaborator on a fork of a 2FA-requiring org's private repo
    org_oc_indirect = create(:two_factor_credential_org)
    org_oc_indirect.allow_private_repository_forking(actor: org_oc_indirect.admins.first)
    forker = create(:two_factor_credential_user)
    org_oc_indirect.add_member(forker)
    fork = create(:fork_repository, forker: forker, fork_repo: create(:private_repository, owner: org_oc_indirect))
    fork.add_member(user)

    affiliated_orgs = user.affiliated_organizations_with_two_factor_requirement

    expected_orgs = [
      org_billing,
      org_member,
      org_owner,
      org_oc_direct,
      org_oc_indirect,
      org_oc_direct_public,
    ]
    assert_empty expected_orgs - affiliated_orgs
    assert_empty affiliated_orgs - expected_orgs
    assert_equal expected_orgs.sort, affiliated_orgs.sort
  end
end

class UserAffiliatedOrganizationsTest < GitHub::TestCase
  fixtures do
    # the user in question
    @user = create(:two_factor_credential_user)
    # owns org_owner
    @org_owner = create(:organization, admin: @user)
    # is a member of org_member
    @org_member = create(:organization)
    @org_member.add_member(@user)
    # is a billing manager (but not a member) on org_billing
    @org_billing = create(:organization)
    @org_billing.billing.add_manager(@user, actor: @org_billing.admin)
    # is a member of org_non_2fa, which doesn't require 2FA
    @org_non_2fa = create(:organization)
    @org_non_2fa.add_member(@user)
    # is an outside collaborator on an org that doesn't require 2FA
    @org_oc_direct_non_2fa = create(:organization)
    create(:private_repository, owner: @org_oc_direct_non_2fa).add_member(@user)
    # is an outside collaborator on a 2FA-requiring org's public repo
    @org_oc_direct_public = create(:organization)
    create(:repository, owner: @org_oc_direct_public).add_member(@user)
    # is an outside collaborator on a 2FA-requiring org's private repo
    @org_oc_direct = create(:organization)
    create(:private_repository, owner: @org_oc_direct).add_member(@user)
    # is an outside collaborator on a fork of a 2FA-requiring org's private repo
    @org_oc_indirect = create(:organization)
    @org_oc_indirect.allow_private_repository_forking(actor: @org_oc_indirect.admins.first)
    forker = create(:two_factor_credential_user)
    @org_oc_indirect.add_member(forker)
    fork = create(:fork_repository, forker: forker, fork_repo: create(:private_repository, owner: @org_oc_indirect))
    fork.add_member(@user)
  end

  test "returns affiliated organizations, regardless of 2FA requirement" do
    affiliated_orgs = @user.affiliated_organizations

    expected_orgs = [
      @org_billing,
      @org_member,
      @org_non_2fa,
      @org_oc_direct,
      @org_oc_direct_non_2fa,
      @org_oc_direct_public,
      @org_oc_indirect,
      @org_owner,
    ]
    assert_empty expected_orgs - affiliated_orgs
    assert_empty affiliated_orgs - expected_orgs
    assert_equal expected_orgs.sort, affiliated_orgs.sort
  end

  test "User#affiliated_organizations_with_roles returns affilited organizations and the role(s) this user has with each one, and can sort them by org name" do
    # set up organizations where the user has more than one role
    @org_non_2fa.billing.add_manager(@user, actor: @org_non_2fa.admin)
    @org_oc_direct_public.billing.add_manager(@user, actor: @org_oc_direct_public.admin)

    affiliated_orgs_with_roles = @user.affiliated_organizations_with_roles.sort_by { |o| o[0].login }.to_h
    expected_orgs_with_roles = {
        @org_billing => [:billing_manager],
        @org_member => [:member],
        @org_non_2fa => [:member, :billing_manager],
        @org_oc_direct => [:outside_collaborator],
        @org_oc_direct_non_2fa => [:outside_collaborator],
        @org_oc_direct_public => [:billing_manager, :outside_collaborator],
        @org_oc_indirect => [:outside_collaborator],
        @org_owner => [:admin],      # @user is also a :member of @org_owner, but we should only return :admin access for owners
    }.sort_by { |o| o[0].login }.to_h
    assert_equal expected_orgs_with_roles, affiliated_orgs_with_roles
  end
end

class UserOutsideCollaboratorOrganizationsTest < GitHub::TestCase
  test "returns all and only organizations associated with through outside collaboratorship" do
    user = create(:user)
    org = create(:organization)
    org.add_member(user)
    repository1 = create(:repository, owner: create(:organization))
    repository1.add_member_without_validation_or_notifications(user)
    repository2 = create(:repository, owner: create(:organization))
    repository2.add_member_without_validation_or_notifications(user)
    repository3 = create(:repository, owner: org)
    repository3.add_member_without_validation_or_notifications(user)

    assert_same_elements [repository1.owner, repository2.owner],
      user.outside_collaborator_organizations.to_a
  end

  test "does not return organizations associated through only deleted repositories" do
    user = create(:user)
    org = create(:organization)
    org.add_member(user)
    repository1 = create(:repository, owner: create(:organization))
    repository1.add_member_without_validation_or_notifications(user)
    repository2 = create(:repository, owner: create(:organization))
    repository2.add_member_without_validation_or_notifications(user)
    # Mark deleted
    repository2.update active: false
    repository3 = create(:repository, owner: org)
    repository3.add_member_without_validation_or_notifications(user)

    assert_same_elements \
      [repository1.owner],
      user.outside_collaborator_organizations.to_a
  end
end

class MayRetainAffiliationWithout2FATest < GitHub::TestCase
  test "returns true for org member" do
    GitHub.flipper[:two_factor_cap_enforcement].enable
    GitHub.flipper[:members_without_2fa_allowed].enable
    user = create(:user)
    org = create(:organization)
    org.add_member(user)

    assert user.may_retain_affiliation_without_2fa?(org)
  end

  test "returns true for billing manager" do
    GitHub.flipper[:two_factor_cap_enforcement].enable
    GitHub.flipper[:members_without_2fa_allowed].enable
    user = create(:user)
    org = create(:organization)
    org.billing.add_manager(user, actor: org.admins.first)
    assert org.billing_managers.include?(user)

    assert user.may_retain_affiliation_without_2fa?(org)
  end

  test "returns false for outside collaborator always" do
    user = create(:user)
    org = create(:organization)
    repo = create(:repository, owner: org)
    RepositoryInvitation.invite_to_repo_without_confirmation(user, org.admins.first, repo)

    refute user.may_retain_affiliation_without_2fa?(org)
  end

  test "returns false for all users when not members_without_outside_collaborators" do
    GitHub.flipper[:two_factor_cap_enforcement].disable
    GitHub.flipper[:members_without_2fa_allowed].disable

    member = create(:user)
    billing = create(:user)
    org = create(:organization)
    org.add_member(member)
    org.billing.add_manager(billing, actor: org.admins.first)

    refute member.may_retain_affiliation_without_2fa?(org)
    refute billing.may_retain_affiliation_without_2fa?(org)
  end
end

class UserTwoFactorLockTest < GitHub::TestCase
  test "two_factor_lock_key returns a user specific lock key" do
    user = create(:user)
    key = user.two_factor_lock_key
    assert key.include? "user:#{user.id}"
  end

  test "two_factor_locked? returns false if it is not locked" do
    user = create(:user)
    refute_predicate user, :two_factor_locked?
  end

  test "two_factor_locked? returns true if it is locked" do
    user = create(:user)
    user.lock_two_factor do
      assert_predicate user, :two_factor_locked?
    end
  end
end

class UserDisallowedTwoFactorMethodsConfiguredTest < GitHub::TestCase
  skip_enterprise

  fixtures do
    @admin = create(:user)
    @org = create(:two_factor_credential_org, admin: @admin)
    @business = create(:business, owners: [@admin])
  end

  test "disallowed_methods_configured returns empty list if the org is not present" do
    assert_equal Set.new, @admin.disallowed_methods_configured(nil)
  end

  test "disallowed_methods_configured returns empty list if the org does not restrict any methods" do
    assert_equal Set.new, @admin.disallowed_methods_configured(@org)
  end

  test "disallowed_methods_configured returns empty if the business does not have 2FA required" do
    make_sms_two_factor_credential(@admin)
    @business.add_disallowed_two_factor_method(method: :insecure, actor: @admin)

    assert_equal Set.new, @admin.disallowed_methods_configured(@business)
  end

  test "disallowed_methods_configured returns SMS if the enterprise restricts it" do
    make_sms_two_factor_credential(@admin)
    @business.enable_two_factor_required actor: @admin, force: true
    @business.add_disallowed_two_factor_method(method: :insecure, actor: @admin)

    assert_equal Set.new([:sms]), @admin.disallowed_methods_configured(@business)
  end

  test "disallowed_methods_configured returns SMS if the org restricts it and user has SMS configured", skip_enterprise: true do
    make_sms_two_factor_credential(@admin)
    @org.add_disallowed_two_factor_method(method: :insecure, actor: @admin)

    assert_equal Set.new([:sms]), @admin.disallowed_methods_configured(@org)
  end
end
