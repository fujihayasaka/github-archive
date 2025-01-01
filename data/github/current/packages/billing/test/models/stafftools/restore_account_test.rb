# typed: true
# frozen_string_literal: true

require "test_helper"

class StafftoolsRestoreAccountTest < GitHub::TestCase
  fixtures do
    GitHub::Enterprise.ensure_business! if GitHub.single_business_environment?
  end

  test "restores a deleted user" do
    current_user = create(:user)
    user = create :credit_card_user, plan: "micro"
    user.destroy

    restoration = Stafftools::RestoreAccount.perform(current_user, {
      was_org: "false",
      id: user.id,
      email: user.email,
      login: user.login,
      plan: user.plan.name,
    })
    restored_account = restoration.account
    assert_predicate restored_account, :valid?
    refute_predicate restored_account, :new_record?
    assert_predicate restored_account, :user?
    assert_equal restored_account.id, user.id
    assert_equal restored_account.email, user.email
    assert_equal restored_account.login, user.login
    assert_equal restored_account.plan, user.plan
  end

  test "restores a deleted organization and assigns an admin" do
    current_user = create(:user)
    org = create(:organization, billing_email: "org@example.com")
    org.destroy

    restoration = Stafftools::RestoreAccount.perform(current_user, {
      was_org: "true",
      id: org.id,
      email: org.billing_email,
      login: org.login,
      plan: org.plan.name,
    })
    restored_account = restoration.account
    assert_predicate restored_account, :valid?
    refute_predicate restored_account, :new_record?
    assert_predicate restored_account, :organization?
    assert_equal restored_account.id, org.id
    assert_equal restored_account.billing_email, org.billing_email
    assert_equal restored_account.login, org.login
    assert_equal restored_account.plan, org.plan
    assert_equal restored_account.plan, org.plan
    assert_equal restored_account.admins, [current_user]
  end

  test "restores a soft deleted organization", skip_enterprise: true do
    current_user = create(:user, :staff)
    soft_deleted_org = create(:organization, :soft_deleted)

    restoration = Stafftools::RestoreAccount.perform(current_user, {
      was_org: "true",
      id: soft_deleted_org.id,
      email: soft_deleted_org.billing_email,
      login: soft_deleted_org.login,
      plan: soft_deleted_org.plan.name,
    })
    restored_account = restoration.account
    assert_equal soft_deleted_org, restored_account
    restored_account.reload
    assert_predicate restored_account, :valid?
    refute_predicate restored_account, :soft_deleted?
  end

  test "reports error if unsuccessful when restoring soft-deleted org", skip_enterprise: true do
    current_user = create(:user, :staff)
    soft_deleted_org = create(:organization, :soft_deleted)

    Organization.any_instance.stubs(:mark_not_deleted).raises(Organization::OrganizationRestorationError.new("bad"))

    restoration = Stafftools::RestoreAccount.perform(current_user, {
      was_org: "true",
      id: soft_deleted_org.id,
      email: soft_deleted_org.billing_email,
      login: soft_deleted_org.login,
      plan: soft_deleted_org.plan.name,
    })

    refute_predicate restoration, :valid?

    restored_account = restoration.account
    assert_predicate restored_account, :soft_deleted?
  end

  test "restores company associated with a deleted organization" do
    current_user = create :user
    org = create :business_plus_org, login: "my-company"
    org.terms_of_service.update \
      type: "Corporate",
      actor: org.admins.first,
      company_name: "my-company"
    refute_nil org.reload.company
    org.destroy

    restoration = Stafftools::RestoreAccount.perform(current_user, {
      was_org: "true",
      id: org.id,
      email: org.billing_email,
      login: org.login,
      plan: org.plan.name,
    })
    restored_account = T.cast(restoration.account, Organization)

    refute_nil restored_account.company
    assert_equal "my-company", restored_account.company.name
  end if GitHub.billing_enabled?

  if GitHub.single_business_environment?
    test "adds restored org to global enterprise" do
      current_user = create :user
      GitHub.stubs(:org_creation_enabled?).returns(true)
      result = ::Organization::Creator.perform \
        current_user,
        GitHub::Plan.find("enterprise"),
        {
          login: "very-new-org",
          admin_logins: [current_user.login],
          billing_email: "billing@example.com"
        }
      org = result.organization
      assert_equal GitHub.global_business, org.business
      assert_includes GitHub.global_business.organizations, org

      org.destroy
      refute_includes GitHub.global_business.organizations, org

      restoration = Stafftools::RestoreAccount.perform(current_user, {
        was_org: "true",
        id: org.id,
        email: org.billing_email,
        login: org.login,
        plan: org.plan.name,
      })
      restored_account = restoration.account
      restored_account.reload
      assert_predicate restored_account, :organization?
      assert_equal GitHub.global_business, restored_account.business
      assert_includes GitHub.global_business.organizations, restored_account
    end
  end

  test "instruments user.recreate when user successfully recreated" do
    current_user = create(:user)
    user = create :credit_card_user, plan: "micro"
    user.destroy

    events = subscribe "user.recreate"
    restoration = Stafftools::RestoreAccount.perform(current_user, {
      was_org: "false",
      id: user.id,
      email: user.email,
      login: user.login,
      plan: user.plan.name,
    })

    expected_payload = {
      user: user.login,
      user_id: user.id,
    }

    assert event = events.pop, "an event should've been created"
    assert_equal "user.recreate", event.name
    assert_equal expected_payload, event.payload
  end

  test "does not instrument user.recreate when user unsuccessfully recreated" do
    current_user = create(:user)
    user = create :credit_card_user, plan: "micro"
    user.destroy

    events = subscribe "user.recreate"
    restoration = Stafftools::RestoreAccount.perform(current_user, {
      was_org: "false",
      id: user.id,
      email: user.email,
      login: "invalid login thanks bye",
      plan: user.plan.name,
    })
    restored_account = restoration.account
    assert_empty events
    refute_predicate restored_account, :valid?
    refute_predicate restored_account, :persisted?
  end

  test "instruments org.recreate when org successfully recreated" do
    current_user = create(:user)
    org = create(:organization, billing_email: "org@example.com")
    org.destroy

    events = subscribe "org.recreate"
    restoration = Stafftools::RestoreAccount.perform(current_user, {
      was_org: "true",
      id: org.id,
      email: org.billing_email,
      login: org.login,
      plan: org.plan.name,
    })

    expected_payload = {
      org: org.login,
      org_id: org.id,
    }

    assert event = events.pop, "an event should've been created"
    assert_equal "org.recreate", event.name
    assert_equal expected_payload, event.payload
  end

  test "does not instrument org.recreate when org unsuccessfully recreated" do
    current_user = create(:user)
    org = create(:organization, billing_email: "org@example.com")
    org.destroy

    events = subscribe "org.recreate"
    restoration = Stafftools::RestoreAccount.perform(current_user, {
      was_org: "true",
      id: org.id,
      email: org.billing_email,
      login: "invalid login thanks bye",
      plan: org.plan.name,
    })
    restored_account = restoration.account
    assert_empty events
    refute_predicate restored_account, :valid?
    refute_predicate restored_account, :persisted?
  end
end
