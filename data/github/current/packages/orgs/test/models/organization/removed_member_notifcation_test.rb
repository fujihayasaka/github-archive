# typed: true
# frozen_string_literal: true

require "test_helper"

class OrganizationRemovedMemberNotificationTest < GitHub::TestCase
  fixtures do
    @user = create(:user)
    @org = create(:organization)
  end

  setup do
    notification = Organization::RemovedMemberNotification.new(@org, @user)
    notification.dismiss
  end

  test "dismiss removes notification after being set" do
    notification = Organization::RemovedMemberNotification.new(@org, @user)
    notification.add_two_factor_requirement_non_compliance

    assert_predicate notification, :two_factor_requirement_non_compliance?

    notification.dismiss

    refute_predicate notification, :two_factor_requirement_non_compliance?
  end

  test "dismiss returns false if org or user are invalid" do
    repo = create :repository, :minimal, id: @user.id
    notification = Organization::RemovedMemberNotification.new(@org, repo)

    assert_equal false, notification.dismiss
  end

  test "adds a two factor requirement notification for a given organization and user" do
    removal_notification = Organization::RemovedMemberNotification.new(@org, @user)
    refute_predicate removal_notification, :two_factor_requirement_non_compliance?

    removal_notification.add_two_factor_requirement_non_compliance

    assert_predicate removal_notification, :two_factor_requirement_non_compliance?
  end

  test "adds a SAML external identity requirement notification for a given organization and user" do
    notification = Organization::RemovedMemberNotification.new(@org, @user)
    refute_predicate notification, :saml_external_identity_missing?

    notification.add_saml_external_identity_missing

    assert_predicate notification, :saml_external_identity_missing?
  end

  test "only one removal notification can exist for an organization and user" do
    notification = Organization::RemovedMemberNotification.new(@org, @user)
    refute_predicate notification, :saml_external_identity_missing?
    refute_predicate notification, :two_factor_requirement_non_compliance?

    notification.add_two_factor_requirement_non_compliance
    notification.add_saml_external_identity_missing

    assert_predicate notification, :saml_external_identity_missing?
    refute_predicate notification, :two_factor_requirement_non_compliance?
  end
end
