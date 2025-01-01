# typed: true
# frozen_string_literal: true

require "test_helper"

class Licensing::SetUserFromBusinessOnBundledLicenseAssignmentJobTest < GitHub::TestCase
  include AuditLog::IntegrationTestHelpers

  fixtures do
    @verified_user = create(:verified_user)
    @unverified_user = create(:user)
    @business = create(:business, owners: [@verified_user, @unverified_user])
  end

  test "sets user_id on bundled_license_assignment if business exist and user is verified" do
    assignment = create(:licensing_bundled_license_assignment, business: @business, email: @verified_user.email)

    assert_nil assignment.user_id

    Licensing::SetUserFromBusinessOnBundledLicenseAssignmentJob.perform_now(assignment: assignment)

    assert_equal assignment.reload.user_id, @verified_user.id
  end

  test "doesn't update user_id if user id is not changing" do
    assignment = create(
      :licensing_bundled_license_assignment,
      email: @verified_user.email, user: @verified_user, business: @business
    )

    assignment.expects(:update).never

    Licensing::SetUserFromBusinessOnBundledLicenseAssignmentJob.perform_now(assignment: assignment)
  end

  test "updates the user_id if the verified email belongs to a new user now" do
    assignment = create(
      :licensing_bundled_license_assignment,
      email: @verified_user.email, user: @unverified_user, business: @business
    )

    events = assert_performed_audit_entries(count: 1, only: "bundled_license_assignment.assigned_user") do
      Licensing::SetUserFromBusinessOnBundledLicenseAssignmentJob.perform_now(assignment: assignment)
    end

    assert_equal assignment.reload.user_id, @verified_user.id
  end

  test "doesn't update user_id if business doesn't exist" do
    assignment = create(:licensing_bundled_license_assignment, email: @verified_user.email)

    assignment.expects(:update).never

    Licensing::SetUserFromBusinessOnBundledLicenseAssignmentJob.perform_now(assignment: assignment)
  end

  test "doesn't update user_id if business exist but user isn't verified" do
    assignment = create(:licensing_bundled_license_assignment, business: @business, email: @unverified_user.email)

    assert_nil assignment.user_id
    assignment.expects(:update).never

    Licensing::SetUserFromBusinessOnBundledLicenseAssignmentJob.perform_now(assignment: assignment)
  end

  test "doesn't update user_id if business exist but verified user isn't member of business" do
    verified_user = create(:verified_user)
    assignment = create(:licensing_bundled_license_assignment, business: @business, email: verified_user.email)

    assert_nil assignment.user_id
    assignment.expects(:update).never

    Licensing::SetUserFromBusinessOnBundledLicenseAssignmentJob.perform_now(assignment: assignment)
  end

  test "doesn't update user_id on bundled_license_assignment if the assignment is revoked" do
    assignment = create(:licensing_bundled_license_assignment, business: @business, email: @verified_user.email, revoked: true)

    assert_nil assignment.user_id

    Licensing::SetUserFromBusinessOnBundledLicenseAssignmentJob.perform_now(assignment: assignment)

    assert_nil assignment.user_id
  end

  test "instruments sets user_id on bundled_license_assignment if business exist and user is verified" do
    assignment = create(:licensing_bundled_license_assignment, business: @business, email: @verified_user.email)

    assert_nil assignment.user_id

    events = assert_performed_audit_entries(count: 1, only: "bundled_license_assignment.assigned_user") do
      Licensing::SetUserFromBusinessOnBundledLicenseAssignmentJob.perform_now(assignment: assignment)
    end

    assert_equal last_performed_audit_entries, events

    expected_payload = {
      bundled_license_assignment_id: assignment.id,
      email: assignment.email,
      enterprise_agreement_number: assignment.enterprise_agreement_number,
      subscription_id: assignment.subscription_id,
      user_id: @verified_user.id
    }

    assert_subset_hash expected_payload, events.first
  end

  test "removes user_id on bundled_license_assignment if no user matches anymore" do
    verified_user = create(:verified_user)
    assignment = create(:licensing_bundled_license_assignment, business: @business, email: verified_user.email, user: verified_user)

    assert_equal assignment.reload.user_id, verified_user.id

    Licensing::SetUserFromBusinessOnBundledLicenseAssignmentJob.perform_now(assignment: assignment)

    assert_nil assignment.reload.user_id
  end

  unless GitHub.single_business_environment?
    test "enqueues license attributer cache job" do
      assignment = create(:licensing_bundled_license_assignment, business: @business, email: @verified_user.email)

      assert_nil assignment.user_id

      assert_enqueued_jobs(1, only: [BusinessUpdateLicenseUsageJob]) do
        Licensing::SetUserFromBusinessOnBundledLicenseAssignmentJob.perform_now(assignment: assignment)
      end
    end
  end
end if GitHub.billing_enabled?

class Licensing::EMUSetUserFromBusinessOnBundledLicenseAssignmentJobTest < GitHub::TestCase
  include AuditLog::IntegrationTestHelpers

  fixtures do
    @business = create(:business, :enterprise_managed)
    @user = create :emu, business: @business
    @user_name = @user.external_identities.first.scim_user_data.user_name

    @another_user = create :emu, business: @business
  end

  test "updates user_id if user already exists with feature flag enabled" do
    assignment = create(:licensing_bundled_license_assignment, business: @business, email: @user_name, user: @another_user)
    refute_nil assignment.user_id

    Licensing::SetUserFromBusinessOnBundledLicenseAssignmentJob.perform_now(assignment: assignment)
    assert_equal assignment.reload.user_id, @user.id
  end

  test "sets user_id on bundled_license_assignment if business exist" do
    assignment = create(:licensing_bundled_license_assignment, business: @business, email: @user_name)

    assert_nil assignment.user_id

    Licensing::SetUserFromBusinessOnBundledLicenseAssignmentJob.perform_now(assignment: assignment)

    assert_equal assignment.reload.user_id, @user.id
  end

  test "sets user_id on bundled_license_assignment if business exist and user has same email and upn" do
    user_with_same_email = create :emu, business: @business
    user_with_same_email_username = User::EnterpriseManagedDependency.add_shortcode(
      user_with_same_email.external_identities.first.scim_user_data.user_name,
      @business
    )

    primary_user_email = user_with_same_email.emails.build(email: user_with_same_email_username)
    primary_user_email.mark_as_verified
    user_with_same_email.set_primary_email primary_user_email
    user_with_same_email.emails.reload

    assignment = create(:licensing_bundled_license_assignment, business: @business, email: user_with_same_email_username)

    assert_nil assignment.user_id

    Licensing::SetUserFromBusinessOnBundledLicenseAssignmentJob.perform_now(assignment: assignment)

    assert_equal assignment.reload.user_id, user_with_same_email.id
  end

  test "sets user_id on bundled_license_assignment if unlinked and using oidc provider" do
    business = create :business, :enterprise_managed
    provider = create :business_oidc_provider, business: business
    user = create :verified_user, business: business
    external_identity = create :external_identity, :scim, user: user, provider: provider
    user_name = user.external_identities.first.scim_user_data.user_name
    assignment = create(:licensing_bundled_license_assignment, business: business, email: user_name)

    assert_nil assignment.user_id

    Licensing::SetUserFromBusinessOnBundledLicenseAssignmentJob.perform_now(assignment: assignment)

    assert_equal user.id, assignment.user_id
  end

  test "matches emu user if email is not for an EMU, business exists, and an EMU with corresponding exists" do
    emu = create(:emu, business: @business)
    matching_dotcom_user = create(:user)
    matching_email = emu.emails.first.deobfuscated_email

    primary_user_email = matching_dotcom_user.emails.build(email: matching_email)
    primary_user_email.mark_as_verified
    matching_dotcom_user.set_primary_email(primary_user_email)
    matching_dotcom_user.emails.reload

    assignment = create(:licensing_bundled_license_assignment, business: @business, email: matching_email)

    assert_nil assignment.user_id

    Licensing::SetUserFromBusinessOnBundledLicenseAssignmentJob.perform_now(assignment: assignment)

    assert_equal assignment.reload.user_id, emu.id
  end

  test "doesn't update user_id if business doesn't exist" do
    assignment = create(:licensing_bundled_license_assignment, email: @user_name)

    assignment.expects(:update).never

    Licensing::SetUserFromBusinessOnBundledLicenseAssignmentJob.perform_now(assignment: assignment)
  end

  test "doesn't update user_id on bundled_license_assignment if the assignment is revoked" do
    assignment = create(:licensing_bundled_license_assignment, business: @business, email: @user_name, revoked: true)

    assert_nil assignment.user_id

    Licensing::SetUserFromBusinessOnBundledLicenseAssignmentJob.perform_now(assignment: assignment)

    assert_nil assignment.user_id
  end

  test "doesn't update user_id on bundled_license_assignment if saml provider is not set" do
    business = create(:business, :enterprise_managed)
    assignment = create(:licensing_bundled_license_assignment, business: business, email: @user_name)

    assert_nil assignment.user_id

    Licensing::SetUserFromBusinessOnBundledLicenseAssignmentJob.perform_now(assignment: assignment)

    assert_nil assignment.user_id
  end

  test "doesn't update user_id on bundled_license_assignment if there are not external identities" do
    business = create(:business, :enterprise_managed)
    create(:business_saml_provider, business: business)
    assignment = create(:licensing_bundled_license_assignment, business: business, email: @user_name)

    assert_nil assignment.user_id

    Licensing::SetUserFromBusinessOnBundledLicenseAssignmentJob.perform_now(assignment: assignment)

    assert_nil assignment.user_id
  end

  test "instruments sets user_id on bundled_license_assignment if business exist and user is verified" do
    assignment = create(:licensing_bundled_license_assignment, business: @business, email: @user_name)
    assert_nil assignment.user_id

    events = assert_performed_audit_entries(count: 1, only: "bundled_license_assignment.assigned_user") do
      Licensing::SetUserFromBusinessOnBundledLicenseAssignmentJob.perform_now(assignment: assignment)
    end

    assert_equal last_performed_audit_entries, events

    expected_payload = {
      bundled_license_assignment_id: assignment.id,
      email: assignment.email,
      enterprise_agreement_number: assignment.enterprise_agreement_number,
      subscription_id: assignment.subscription_id,
      user_id: @user.id
    }

    assert_subset_hash expected_payload, events.first
  end
end if GitHub.billing_enabled?
