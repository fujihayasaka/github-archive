# typed: false
# frozen_string_literal: true

require "test_helper"

module ExternalIdentitySharedTests
  include GitHub::LoggerHelper

  def saml_data(
    name_id: nil,
    external_id: nil,
    first_name: nil,
    last_name: nil
  )
    user_data = Platform::Provisioning::SamlUserData.new
    user_data.append("NameID", name_id) if name_id
    user_data.append("http://schemas.microsoft.com/identity/claims/objectidentifier", external_id) if external_id
    user_data.append("first_name", first_name) if first_name
    user_data.append("last_name", last_name) if last_name

    Platform::Provisioning::AttributeMappedUserData.new(user_data)
  end

  def scim_data(
    external_id: nil,
    user_name: nil,
    active: "true",
    emails: nil,
    first_name: nil,
    roles: nil
  )
    user_data = Platform::Provisioning::ScimUserData.new
    user_data.append("externalId", external_id) if external_id
    user_data.append("userName", user_name) if user_name
    user_data.append("active", active)
    user_data.append("first_name", first_name) if first_name
    Array(emails).each do |email|
      user_data.append("emails", email) if email
    end if emails
    Array(roles).each do |role|
      user_data.append("roles", role) if role
    end if roles

    Platform::Provisioning::AttributeMappedUserData.new(user_data)
  end

  def test_event_context_includes_guid_nameid_and_username
    name_id = "nameid:johndoe"
    user_name = "username:johndoe"

    external_identity = create :external_identity,
      provider: @provider,
      saml_user_data: saml_data(name_id: name_id),
      scim_user_data: scim_data(user_name: user_name)

    event_context = external_identity.event_context

    assert_equal event_context[:external_identity_guid], external_identity.guid
    assert_equal event_context[:external_identity_nameid], name_id
    assert_equal event_context[:external_identity_username], user_name
  end

  def test_event_context_includes_scim_user_roles_when_roles_present
    name_id = "nameid:johndoe"
    user_name = "username:johndoe"

    external_identity = create :external_identity,
      provider: @provider,
      saml_user_data: saml_data(name_id: name_id),
      scim_user_data: scim_data(user_name: user_name, roles: %w(enterprise_owner user))

    event_context = external_identity.event_context

    assert_equal event_context[:external_identity_scim_roles], "Enterprise Owner, User"
  end

  def test_mark_deleted_returns_true_after_successfully_deleting_the_external_identity
    external_identity = create :external_identity,
      provider: @provider, saml_user_data: saml_data(name_id: "johndoe")
    assert_nil(external_identity.deleted_at, "deleted_at should be nil for newly created external identities")

    delete_result = external_identity.mark_deleted
    assert delete_result, "delete should return true to set the deleted_at value for valid external identity"
    refute_nil(external_identity.deleted_at, "deleted_at should not be nil for deleted external identities")
  end

  def test_mark_deleted_returns_false_after_calling_delete_on_invalid_external_identity
    valid_external_identity = create :external_identity, user: create(:user, login: "johndoe"),
      provider: @provider, saml_user_data: saml_data(name_id: "johndoe")

    invalid_external_identity = build :external_identity,
      provider: @provider, saml_user_data: saml_data(name_id: "johndoe")

    refute_predicate invalid_external_identity, :valid?

    delete_result = invalid_external_identity.mark_deleted
    refute delete_result, "delete should return false to set the deleted_at value for invalid external identity"
  end

  def test_delete_associated_attributes_if_external_identity_is_deleted
    identity = create :external_identity,
      provider: @provider, saml_user_data: saml_data(first_name: "Mona")

    results = ExternalIdentity.by_saml_user_data(saml_data(first_name: "Mona"))
    assert_same_elements [identity], results

    attribute_id = identity.identity_attribute_records.first.id
    refute_nil attribute_id

    identity.destroy
    results_empty = ExternalIdentity.by_saml_user_data(saml_data(first_name: "Mona"))
    assert_equal results_empty, []

    assert_raises(ActiveRecord::RecordNotFound) { ExternalIdentityAttribute.find(attribute_id) }
  end

  def test_delete_associated_attributes_if_external_identity_is_marked_deleted
    identity = create :external_identity,
      provider: @provider, saml_user_data: saml_data(first_name: "Mona")

    results = ExternalIdentity.by_saml_user_data(saml_data(first_name: "Mona"))
    assert_same_elements [identity], results

    attribute_id = identity.identity_attribute_records.first.id
    refute_nil attribute_id

    identity.mark_deleted
    results_empty = ExternalIdentity.by_saml_user_data(saml_data(first_name: "Mona"))
    assert_equal results_empty, []

    assert_raises(ActiveRecord::RecordNotFound) { ExternalIdentityAttribute.find(attribute_id) }
  end

  def test_mark_deleted_sets_saml_external_id_to_nil
    user_data = saml_data(external_id: "mona-external-id")
    identity = create :external_identity,
      provider: @provider, saml_user_data: user_data

    results = ExternalIdentity.get_by_external_id(user_data, mapping: Platform::Provisioning::IdentityMapping.new)
    assert_same_elements [identity], results

    assert_equal "mona-external-id", identity.saml_external_id
    assert_nil identity.external_id

    identity.mark_deleted

    results_empty = ExternalIdentity.get_by_external_id(user_data, mapping: Platform::Provisioning::IdentityMapping.new)
    assert_equal results_empty, []

    assert_nil identity.saml_external_id
    assert_nil identity.external_id
  end

  def test_mark_deleted_sets_external_id_to_nil
    user_data = scim_data(external_id: "mona-external-id")
    identity = create :external_identity, :scim,
      provider: @provider, scim_user_data: user_data

    results = ExternalIdentity.get_by_external_id(user_data, mapping: Platform::Provisioning::IdentityMapping.new)
    assert_same_elements [identity], results

    assert_equal "mona-external-id", identity.external_id
    assert_nil identity.saml_external_id

    identity.mark_deleted

    results_empty = ExternalIdentity.get_by_external_id(user_data, mapping: Platform::Provisioning::IdentityMapping.new)
    assert_equal results_empty, []

    assert_nil identity.saml_external_id
    assert_nil identity.external_id
  end

  def test_disable_returns_true_after_successfully_disabling_the_external_identity
    external_identity = create :external_identity,
      provider: @provider, saml_user_data: saml_data(name_id: "johndoe")
    assert_nil(external_identity.disabled_at, "disabled_at should be nil for newly created external identities")

    disable_result = external_identity.disable
    assert disable_result, "disable should return true to set the disabled_at value for valid external identity"
    refute_nil(external_identity.disabled_at, "disabled_at should not be nil for a disabled external identities")
  end

  def test_disable_returns_false_after_calling_disable_on_invalid_external_identity
    valid_external_identity = create :external_identity, user: create(:user, login: "johndoe"),
      provider: @provider, saml_user_data: saml_data(name_id: "johndoe")

    invalid_external_identity = build :external_identity,
      provider: @provider, saml_user_data: saml_data(name_id: "johndoe")

    refute_predicate invalid_external_identity, :valid?

    disable_result = invalid_external_identity.disable
    refute disable_result, "disable should return false to set the disabled_at value for invalid external identity"
  end

  def test_enable_returns_true_after_successfully_enabling_a_disabled_external_identity
    external_identity = create :external_identity, disabled_at: Time.now,
      provider: @provider, saml_user_data: saml_data(name_id: "johndoe")
    refute_nil(external_identity.disabled_at, "disabled_at should not be nil for a disabled external identities")

    enable_result = external_identity.enable
    assert enable_result, "enable should return true to set the disabled_at value to nil for valid external identity"
    assert_nil(external_identity.disabled_at, "disabled_at should be nil for enabled external identities")
  end

  def test_enable_returns_false_after_calling_enable_on_invalid_external_identity
    valid_external_identity = create :external_identity, user: create(:user, login: "johndoe"),
      provider: @provider, saml_user_data: saml_data(name_id: "johndoe")

    invalid_external_identity = build :external_identity, disabled_at: Time.now,
      provider: @provider, saml_user_data: saml_data(name_id: "johndoe")

    refute_predicate invalid_external_identity, :valid?
    enable_result = invalid_external_identity.enable
    refute enable_result, "enable should return false to set the disabled_at value to nil for invalid external identity"
  end

  def test_validations_requires_a_provider
    external_identity = build :external_identity, provider: nil
    refute_predicate external_identity, :valid?
    assert_includes external_identity.errors[:provider], "can't be blank"
  end

  def test_validations_requires_a_valid_provider_type
    external_identity = build :external_identity, provider: create(:user)
    refute_predicate external_identity, :valid?
    assert_includes external_identity.errors[:provider_type], "is not included in the list"
  end

  def test_validations_requires_user_to_be_unique_for_the_provider
    existing = create :external_identity, provider: @provider

    external_identity = build :external_identity, user: existing.user, provider: @provider
    assert_raises ActiveRecord::RecordNotUnique do
      external_identity.save
    end

    different_provider = build :external_identity, user: existing.user, provider: create(:organization_saml_provider)
    assert different_provider.save, "expected to be able to save with duplicate user but different provider"
  end

  def test_validations_requires_saml_name_id_to_be_unique_for_the_provider
    enable_feature_flag(:add_doc_to_identity_error_msg)
    existing = create :external_identity, user: create(:user, login: "johndoe"),
      provider: @provider, saml_user_data: saml_data(name_id: "johndoe")

    external_identity = build :external_identity,
      provider: @provider, saml_user_data: saml_data(name_id: "johndoe")

    proper_owner = @provider.target.business? ? "enterprise" : "organization"
    doc_link = if proper_owner == "enterprise"
      "#{GitHub.help_url}/admin/managing-iam/understanding-iam-for-enterprises/troubleshooting-identity-and-access-management-for-your-enterprise#conflicting-saml-identity-errors"
    else
      "#{GitHub.help_url}/organizations/managing-saml-single-sign-on-for-your-organization/troubleshooting-identity-and-access-management-for-your-organization#conflicting-saml-identity-error"
    end

    refute_predicate external_identity, :valid?
    assert_includes external_identity.errors[:base], "Your GitHub user account @#{external_identity.user.login} is currently unlinked. " \
      "However, you are attempting to authenticate with your Identity Provider using the 'johndoe' SAML identity which is already " \
      "linked to a different GitHub user account in the #{proper_owner}. Please reach out to one of your GitHub #{proper_owner} owners for assistance." \
      " For troubleshooting, please use the following link: #{doc_link}"

    different_provider = build :external_identity, provider: create(:organization_saml_provider),
      saml_user_data: saml_data(name_id: "johndoe")
    assert different_provider.save, "expected to be able to save with duplicate name_id but different provider"
  end

  def test_correct_owner_reference_for_duplicate_saml_identity_error_for_org_provider
    enable_feature_flag(:add_doc_to_identity_error_msg)
    org_provider = create(:organization_saml_provider)
    existing = create :external_identity, user: create(:user, login: "johndoe"),
      provider: org_provider, saml_user_data: saml_data(name_id: "johndoe")

    external_identity = build :external_identity,
      provider: org_provider, saml_user_data: saml_data(name_id: "johndoe")

    doc_link = "#{GitHub.help_url}/organizations/managing-saml-single-sign-on-for-your-organization/troubleshooting-identity-and-access-management-for-your-organization#conflicting-saml-identity-error"

    refute_predicate external_identity, :valid?
    assert_includes external_identity.errors[:base], "Your GitHub user account @#{external_identity.user.login} is currently unlinked. " \
      "However, you are attempting to authenticate with your Identity Provider using the 'johndoe' SAML identity which is already " \
      "linked to a different GitHub user account in the organization. Please reach out to one of your GitHub organization owners for assistance." \
      " For troubleshooting, please use the following link: #{doc_link}"
  end

  def test_correct_owner_reference_for_duplicate_saml_identity_error_for_business_provider
    enable_feature_flag(:add_doc_to_identity_error_msg)
    existing = create :external_identity, user: create(:user, login: "johndoe"),
      provider: @business_provider, saml_user_data: saml_data(name_id: "johndoe")

    external_identity = build :external_identity,
      provider: @business_provider, saml_user_data: saml_data(name_id: "johndoe")

    doc_link = "#{GitHub.help_url}/admin/managing-iam/understanding-iam-for-enterprises/troubleshooting-identity-and-access-management-for-your-enterprise#conflicting-saml-identity-errors"

    refute_predicate external_identity, :valid?
    assert_includes external_identity.errors[:base], "Your GitHub user account @#{external_identity.user.login} is currently unlinked. " \
      "However, you are attempting to authenticate with your Identity Provider using the 'johndoe' SAML identity which is already " \
      "linked to a different GitHub user account in the enterprise. Please reach out to one of your GitHub enterprise owners for assistance." \
      " For troubleshooting, please use the following link: #{doc_link}"
  end

  def test_validations_requires_scim_user_name_to_be_unique_for_the_provider
    existing = create :external_identity, user: create(:user, login: "johndoe"),
      provider: @provider, scim_user_data: scim_data(user_name: "johndoe")

    external_identity = build :external_identity,
      provider: @provider, scim_user_data: scim_data(user_name: "johndoe")

    refute_predicate external_identity, :valid?
    assert_includes external_identity.errors[:base], "External login 'johndoe' is already linked to @johndoe's account."

    different_provider = build :external_identity, provider: create(:organization_saml_provider),
      scim_user_data: scim_data(user_name: "johndoe")
    assert different_provider.save, "expected to be able to save with duplicate user_name but different provider"
  end

  def test_validations_requires_external_id_to_be_unique_for_the_provider
    existing = create :external_identity, :scim, user: create(:user, login: "johndoe"),
      provider: @provider, scim_user_data: scim_data(external_id: "external-id")

    external_identity = build :external_identity, :scim,
      provider: @provider, scim_user_data: scim_data(external_id: "external-id")

    refute_predicate external_identity, :valid?
    assert_includes external_identity.errors[:base], "External ID 'external-id' is already linked to a GitHub user account."

    different_provider = build :external_identity, provider: create(:organization_saml_provider),
      scim_user_data: scim_data(external_id: "external-id")
    assert different_provider.save, "expected to be able to save with duplicate external_id but different provider"
  end

  def test_validations_does_not_require_scim_user_name_attribute_to_be_unique_for_the_provider_if_previous_record_is_marked_as_deleted
    existing = create :external_identity, :scim, user: create(:user, login: "johndoe"),
      provider: @provider, scim_user_data: scim_data(user_name: "johndoe")
    existing.mark_deleted
    existing.save!

    external_identity = build :external_identity,
      provider: @provider, scim_user_data: scim_data(user_name: "johndoe")

    assert_predicate external_identity, :valid?
  end

  def test_validations_long_user_name_is_truncated
    new_external_identity = create :external_identity, :scim,
      provider: @provider, scim_user_data: scim_data(user_name: "a" * 500)

    assert_equal 255, new_external_identity.user_name.length
  end

  def test_validations_long_name_id_is_truncated
    new_external_identity = create :external_identity,
      provider: @provider, saml_user_data: saml_data(name_id: "a" * 500)

    assert_equal 255, new_external_identity.name_id.length
  end

  def test_validations_long_external_id_is_truncated
    new_external_identity = create :external_identity, :scim,
      provider: @provider, scim_user_data: scim_data(external_id: "a" * 500)

    assert_equal 128, new_external_identity.external_id.length
  end

  def test_linked_returns_true_if_an_external_identity_exists_for_the_given_provider_and_user
    refute ExternalIdentity.linked? \
      provider: @provider,
      user: @other_user

    create :external_identity,
      provider: @provider,
      user: @other_user

    assert ExternalIdentity.linked? \
      provider: @provider,
      user: @other_user
  end

  def test_unlink_destroys_an_external_identity_linked_to_a_provider_and_a_user
    create :external_identity,
      provider: @provider,
      user: @other_user

    assert ExternalIdentity.linked? \
      provider: @provider,
      user: @other_user

    ExternalIdentity.unlink \
      provider: @provider,
      user: @other_user

    refute ExternalIdentity.linked? \
      provider: @provider,
      user: @other_user
  end

  def test_unlink_can_instrument_revoke_external_identity_event_when_identity_is_revoked
    events = subscribe @event_name

    create :external_identity,
      provider: @provider,
      user: @other_user

    ExternalIdentity.unlink \
      provider: @provider,
      user: @other_user,
      instrumentation_payload: {
        actor: @admin,
        user: @other_user,
      }

    assert event = events.pop, "#{@event_name} event was expected"
    assert events.empty?
    assert_equal @expected_payload, event.payload
  end

  def test_by_provider_finds_identities_tied_to_the_given_provider
    provider_identity = create :external_identity,
      provider: @provider,
      user: @other_user
    other_identity = create :external_identity

    assert_includes ExternalIdentity.by_provider(@provider), provider_identity
  end

  def test_by_scim_user_name_finds_external_identity_by_scim_user_name
    scim_identity = create :external_identity,
      provider: @provider, scim_user_data: scim_data(user_name: "johndoe")

    results = ExternalIdentity.by_scim_username("johndoe")
    assert_equal scim_identity, results.first
  end

  def test_by_scim_user_name_does_not_finds_external_identity_by_scim_user_name_if_user_name_does_not_exist
    scim_identity = create :external_identity,
      provider: @provider, scim_user_data: scim_data(user_name: "johndoe")

    results = ExternalIdentity.by_scim_username("invalid-user-name")
    assert_empty results
  end

  def test_by_scim_user_name_does_not_finds_external_identity_by_scim_user_name_if_there_are_no_external_identities
    ExternalIdentity.by_provider(@provider).destroy_all
    assert_empty ExternalIdentity.by_provider(@provider)

    results = ExternalIdentity.by_scim_username("invalid-user-name")
    assert_empty results
  end

  def test_by_saml_user_data_scopes_by_scheme
    saml_identity = create :external_identity,
      provider: @provider, saml_user_data: saml_data(first_name: "Mona")

    scim_identity = create :external_identity,
      scim_user_data: scim_data(first_name: "Mona")

    results = ExternalIdentity.by_saml_user_data \
      saml_data(first_name: "Mona")
    assert_same_elements [saml_identity], results
  end

  def test_by_saml_user_data_finds_identities_with_passed_attribute
    identity = create :external_identity,
      provider: @provider, saml_user_data: saml_data(first_name: "Mona")

    other_identity = create :external_identity,
      provider: @provider, saml_user_data: saml_data(first_name: "Hubot")

    results = ExternalIdentity.by_saml_user_data \
      saml_data(first_name: "Mona")
    assert_same_elements [identity], results
  end

  def test_by_saml_user_data_finds_identities_with_multiple_specified_attributes
    identity = create :external_identity,
      provider: @provider, saml_user_data: saml_data(first_name: "Mona", last_name: "Octocat")

    other_identity = create :external_identity,
      provider: @provider, saml_user_data: saml_data(first_name: "Mona", last_name: "Lisa")

    results = ExternalIdentity.by_saml_user_data \
      saml_data(first_name: "Mona", last_name: "Octocat")

    assert_same_elements [identity], results
  end

  def test_scim_user_data_sets_and_gets_scim_data
    identity = create :external_identity, provider: @provider

    identity.scim_user_data = [
      { name: "userName", value: "someone@example.com" },
      { name: "externalId", value: "my-identifier" },
      { name: "active", value: "true" },
    ]

    identity.save!
    identity.reload

    assert_equal "someone@example.com", identity.scim_user_data.fetch("userName")["value"]
    assert_equal "my-identifier", identity.scim_user_data.fetch("externalId")["value"]
    assert_equal "true", identity.scim_user_data.fetch("active")["value"]
  end

  def test_scim_filer_supports_id_eq_id_filters
    scim_identity = create :external_identity, :scim,
      provider: @provider, scim_user_data: scim_data(user_name: "johndoe")

    results = ExternalIdentity.scim_filter(%Q{id eq "#{scim_identity.guid}"})
    assert_same_elements [scim_identity], results
  end

  def test_scim_filter_supports_username_eq_username_filters
    scim_identity = create :external_identity, :scim,
      provider: @provider, scim_user_data: scim_data(user_name: "johndoe")

    results = ExternalIdentity.scim_filter('userName eq "johndoe"')
    assert_same_elements [scim_identity], results
  end

  def test_scim_filter_supports_externalid_eq_externalid_filters
    scim_identity = create :external_identity, :scim,
      provider: @provider, scim_user_data: scim_data(external_id: "johndoe-external-id")

    results = ExternalIdentity.scim_filter('externalId eq "johndoe-external-id"')
    assert_same_elements [scim_identity], results
  end

  def test_scim_filter_supports_emails_eq_email_filters
    scim_identity = create :external_identity, :scim,
      provider: @provider, scim_user_data: scim_data(emails: ["mona@github.com", "contact@github.com"])
    hubot_identity = create :external_identity, :scim,
      provider: @provider, scim_user_data: scim_data(emails: ["hubot@github.com", "contact@github.com"])

    results = ExternalIdentity.scim_filter('emails eq "mona@github.com"')
    assert_same_elements [scim_identity], results

    results = ExternalIdentity.scim_filter('emails eq "contact@github.com"')
    assert_same_elements [scim_identity, hubot_identity], results
  end

  def test_scim_filter_is_case_insensitive
    scim_identity = create :external_identity,
      provider: @provider, scim_user_data: scim_data(user_name: "Mona")

    results = ExternalIdentity.scim_filter('username EQ "mona"')
    assert_same_elements [scim_identity], results
  end

  def test_scim_filter_does_not_support_and_filters
    assert_raises SCIM::Filter::InvalidFilterError do
      ExternalIdentity.scim_filter('userName eq "mona" and emails eq "mona@github.com')
    end
  end

  def test_scim_fileter_does_not_support_other_filters_than_eq
    assert_raises SCIM::Filter::InvalidFilterError do
      ExternalIdentity.scim_filter('emails co "mona"')
    end
  end

  def test_identities_with_same_name_id_as_finds_identities_that_have_the_same_name_id_as_the_given_identity
    identity = create :external_identity,
      provider: @provider, saml_user_data: saml_data(name_id: "johndoe")

    new_identity = build :external_identity,
      provider: @provider, saml_user_data: saml_data(name_id: "johndoe")

    assert_includes ExternalIdentity.identities_with_same_name_id_as(new_identity),
      identity
  end

  def test_provisioned_by_returns_only_identities_which_have_user_data_for_the_given_scheme
    saml_provisioned = create :external_identity,
      provider: @provider,
      saml_user_data: saml_data(name_id: "johndoe"),
      scim_user_data: nil
    scim_provisioned = create :external_identity,
      :scim,
      provider: @provider,
      saml_user_data: nil

    assert_same_elements [saml_provisioned], ExternalIdentity.by_provider(@provider).provisioned_by(:saml)
    assert_includes ExternalIdentity.by_provider(@provider).provisioned_by(:scim), scim_provisioned
  end

  def test_get_by_identifier_finds_external_identity_by_name_id
    saml_identity = create :external_identity,
      provider: @provider, saml_user_data: saml_data(name_id: "johndoe")

    assert_equal "johndoe", saml_identity.name_id
    assert_nil saml_identity.user_name

    results = ExternalIdentity.get_by_identifier(saml_identity.saml_user_data, mapping: Platform::Provisioning::IdentityMapping.new)
    assert_equal saml_identity, results.first
  end

  def test_get_by_identifier_finds_external_identity_by_name_id_column
    external_identity = create :external_identity,
      provider: @provider, name_id: "johndoe"

    assert_equal "johndoe", external_identity.name_id
    assert_nil external_identity.user_name

    results = ExternalIdentity.get_by_identifier(external_identity.saml_user_data, mapping: Platform::Provisioning::IdentityMapping.new)
    assert_equal external_identity, results.first
  end

  def test_get_by_identifier_finds_external_identity_by_user_name
    scim_identity = create :external_identity, :scim,
      provider: @provider, scim_user_data: scim_data(user_name: "monalisa@contoso.com")

    assert_nil scim_identity.name_id
    assert_equal "monalisa@contoso.com", scim_identity.user_name

    results = ExternalIdentity.get_by_identifier(scim_identity.scim_user_data, mapping: Platform::Provisioning::IdentityMapping.new)
    assert_equal scim_identity, results.first
  end

  def test_get_by_external_id_finds_external_identity_by_object_identifier
    saml_identity = create :external_identity,
      provider: @provider, saml_user_data: saml_data(external_id: "3b79cea9-fa8f-4a5a-b933-538f35c45a6e")

    assert_equal "3b79cea9-fa8f-4a5a-b933-538f35c45a6e", saml_identity.saml_external_id
    assert_nil saml_identity.external_id

    results = ExternalIdentity.get_by_external_id(saml_identity.saml_user_data, mapping: Platform::Provisioning::IdentityMapping.new)
    assert_equal saml_identity, results.first
  end

  def test_get_by_external_id_finds_external_identity_by_external_id
    scim_identity = create :external_identity, :scim,
      provider: @provider, scim_user_data: scim_data(external_id: "3b79cea9-fa8f-4a5a-b933-538f35c45a6e")

    assert_equal "3b79cea9-fa8f-4a5a-b933-538f35c45a6e", scim_identity.external_id

    results = ExternalIdentity.get_by_external_id(scim_identity.scim_user_data, mapping: Platform::Provisioning::IdentityMapping.new)
    assert_equal scim_identity, results.first
  end

  def test_get_by_external_id_finds_external_identity_by_external_id_column
    identifier = "00000000-fa8f-4a5a-b933-538f35c45a6e"
    external_identity = create(:external_identity, external_id: identifier)

    assert_equal identifier, external_identity.external_id

    user_data = scim_data(external_id: identifier)

    results = ExternalIdentity.get_by_external_id(user_data, mapping: Platform::Provisioning::IdentityMapping.new)
    assert_equal external_identity, results.first
  end

  def test_with_scim_preloads_loaded_associations
    scim_identity = create :external_identity, :scim, provider: @provider

    identities = assert_query_count(6) do
      ExternalIdentity.by_provider(@provider).with_scim_preloads.to_a
    end

    assert identities.first.association(:identity_attribute_records).loaded?
    assert identities.first.association(:user).loaded?
    assert identities.first.provider.association(:target).loaded?
  end

  def test_guid_is_set_for_the_external_identity
    identity = create :external_identity, provider: @provider
    assert_predicate identity, :guid?
    refute_nil identity.guid
  end

  def test_session_are_cleaned_up_when_an_identity_is_removed
    session = create :external_identity_session

    assert_difference "ExternalIdentitySession.count", -1 do
      session.external_identity.destroy
    end

    assert_nil ExternalIdentitySession.find_by_id(session.id)
  end

  def test_instruments_event_update
    # Subscribing to an event action type.
    events = subscribe "external_identity.update"
    identity = create :external_identity, :scim, provider: @provider

    # This method call results in a call to instrument update within the model.
    identity.instrument_update

    expected_payload = {
      operation: :update,
      action: :update,
      id: identity.id,
      user: identity.user.login,
      user_id: identity.user_id,
      provider_type: identity.provider_type,
      external_identity_external_id: identity.external_id,
      scim_user_id: identity.guid
    }

    assert event = events.pop, "an event was expected"

    # Verifying the full shape of the event payload.
    assert_equal expected_payload, event.payload
  end

  def test_instruments_event_provision
    # Subscribing to an event action type.
    events = subscribe "external_identity.provision"
    identity = create :external_identity, :scim, provider: @provider

    # This method call results in a call to instrument update within the model.
    identity.instrument_provision

    expected_payload = {
      operation: :provision,
      action: :provision,
      id: identity.id,
      user: identity.user.login,
      user_id: identity.user_id,
      provider_type: identity.provider_type,
      external_identity_external_id: identity.external_id,
      scim_user_id: identity.guid
    }

    assert event = events.pop, "an event was expected"

    # Verifying the full shape of the event payload.
    assert_equal expected_payload, event.payload
  end

  def test_instruments_event_unsuspend
    # Subscribing to an event action type.
    events = subscribe "external_identity.provision"
    identity = create :external_identity, :scim, provider: @provider

    # This method call results in a call to instrument update within the model.
    identity.instrument_provision(action: :unsuspend)

    expected_payload = {
      operation: :provision,
      action: :unsuspend,
      id: identity.id,
      user: identity.user.login,
      user_id: identity.user_id,
      provider_type: identity.provider_type,
      external_identity_external_id: identity.external_id,
      scim_user_id: identity.guid
    }

    assert event = events.pop, "an event was expected"

    # Verifying the full shape of the event payload.
    assert_equal expected_payload, event.payload
  end

  def test_instruments_event_deprovision
    # Subscribing to an event action type.
    events = subscribe "external_identity.deprovision"
    identity = create :external_identity, :scim, provider: @provider

    # This method call results in a call to instrument update within the model.
    identity.instrument_deprovision

    expected_payload = {
      operation: :deprovision,
      action: :delete,
      id: identity.id,
      user: identity.user.login,
      user_id: identity.user_id,
      provider_type: identity.provider_type,
      external_identity_external_id: identity.external_id,
      scim_user_id: identity.guid
    }

    assert event = events.pop, "an event was expected"

    # Verifying the full shape of the event payload.
    assert_equal expected_payload, event.payload
  end

  def test_instruments_event_suspend
    # Subscribing to an event action type.
    events = subscribe "external_identity.deprovision"
    identity = create :external_identity, :scim, provider: @provider

    # This method call results in a call to instrument update within the model.
    identity.instrument_deprovision(action: :suspend)

    expected_payload = {
      operation: :deprovision,
      action: :suspend,
      id: identity.id,
      user: identity.user.login,
      user_id: identity.user_id,
      provider_type: identity.provider_type,
      external_identity_external_id: identity.external_id,
      scim_user_id: identity.guid
    }

    assert event = events.pop, "an event was expected"

    # Verifying the full shape of the event payload.
    assert_equal expected_payload, event.payload
  end

  def test_display_name_returns_correct_value_when_display_name_is_set
    user_data = scim_data(user_name: "johndoe")
    user_data.append("displayName", "John Dude")

    existing = create :external_identity, user: create(:user, login: "johndoe"),
      provider: @provider, scim_user_data: user_data

    assert_equal existing.display_name, "John Dude"
  end

  def test_display_name_returns_correct_value_when_name_formatted_is_set
    user_data = scim_data(user_name: "johndoe")
    user_data.append("name.formatted", "John Dude")

    existing = create :external_identity, user: create(:user, login: "johndoe"),
      provider: @provider, scim_user_data: user_data

    assert_equal existing.display_name, "John Dude"
  end

  def test_display_name_returns_correct_value_when_first_and_last_names_are_set
    user_data = scim_data(user_name: "johndoe")
    user_data.append("name.givenName", "John")
    user_data.append("name.familyName", "Dude")

    existing = create :external_identity, user: create(:user, login: "johndoe"),
      provider: @provider, scim_user_data: user_data

    assert_equal existing.display_name, "John Dude"
  end

  def test_display_name_returns_user_name_when_no_other_attribute_is_set
    user_data = scim_data(user_name: "johndoe")

    existing = create :external_identity, user: create(:user, login: "johndoe"),
      provider: @provider, scim_user_data: user_data

    assert_equal existing.display_name, "johndoe"
  end

  def test_unsupported_4byte_characters_creates_are_removed
    user_data = scim_data(user_name: "johndoe")
    user_data.append("name.formatted", "name 🎶🎶")

    user = create(:user, login: "johndoe")

    assert_raises_with_message(ActiveRecord::RecordInvalid, "Validation failed: Identity attribute records value contains invalid 4-byte characters") do
      existing = create :external_identity, user: user, provider: @provider, scim_user_data: user_data
    end
  end

  def test_emails_returns_email_in_saml_name_id
    identity = create :external_identity,
      provider: @provider, saml_user_data: saml_data(name_id: "user1@github.com")

    assert_equal ["user1@github.com"], identity.emails
  end

  def test_emails_returns_email_in_saml_username
    saml_user_data = Platform::Provisioning::SamlUserData.new([
      { "name" => "NameID", "value" => "user2" },
      { "name" => "http://schemas.xmlsoap.org/ws/2005/05/identity/claims/name", "value" => "user2@github.com" },
    ])
    identity = create :external_identity,
      provider: @provider, saml_user_data: saml_user_data

    assert_equal ["user2@github.com"], identity.emails
  end

  def test_emails_returns_email_in_saml_emails
    saml_user_data = Platform::Provisioning::SamlUserData.new([
      { "name" => "NameID", "value" => "user3" },
      { "name" => "emails", "value" => "user3@github.com" },
    ])
    identity = create :external_identity,
      provider: @provider, saml_user_data: saml_user_data

    assert_equal ["user3@github.com"], identity.emails
  end

  def test_emails_returns_email_in_scim_emails
    identity = create :external_identity,
      provider: @provider, scim_user_data: scim_data(emails: ["user4@github.com"]), saml_user_data: saml_data

    assert_equal ["user4@github.com"], identity.emails
  end

  def test_emails_returns_email_in_scim_username
    identity = create :external_identity,
      provider: @provider, scim_user_data: scim_data(user_name: "user5@github.com"), saml_user_data: saml_data

    assert_equal ["user5@github.com"], identity.emails
  end
end

class ExternalIdentityTest < GitHub::TestCase
  include ExternalIdentitySharedTests

  fixtures do
    @org = create(:organization)
    @provider = @org.create_saml_provider \
      sso_url: "https://githubtest.okta.com/app/github_githubtestsamlorg_1/abcd1234/sso/saml",
      issuer: "http://okta.com/abcd1234",
      idp_certificate: Rails.root.join("test/fixtures/misc/saml/okta.pem").read
    @business_provider = create(:business_saml_provider)

    @user = create(:user)
    @other_user = create(:user)
    @org.add_member @user
    @org.add_member @other_user

    @admin = @org.admins.first
    @event_name = "org.revoke_external_identity"
    @expected_payload = {
      org: @org.login,
      org_id: @org.id,
      actor: @admin.login,
      actor_id: @admin.id,
      user: @other_user.login,
      user_id: @other_user.id,
    }
  end

  context "delete" do
    test "delete a non scim managed user external identity does not remove emails" do
      mona_user = create(:user, email: "mona@github.com")
      mona_user_data = scim_data(
        external_id: "Mona-IdP-Id",
        user_name: "mona",
        emails: ["mona@github.com", "contact@github.com"]
      )
      mona_identity = create :external_identity,
        :scim,
        provider: @provider,
        scim_user_data: mona_user_data,
        user: mona_user

      assert_equal mona_identity, mona_user.reload.external_identities.first
      refute_nil mona_user.email

      mona_identity.destroy

      assert_empty mona_user.reload.external_identities
      refute_nil mona_user.email
    end
  end

  context "validations" do
    test "requires SCIM user_name attribute to be unique for the provider for non scim managed enterprise when the record is marked as disabled" do
      existing = create :external_identity, user: create(:user, login: "johndoe"),
        provider: @provider, scim_user_data: scim_data(user_name: "johndoe")
      existing.disable
      existing.save!

      external_identity = build :external_identity,
        provider: @provider, scim_user_data: scim_data(user_name: "johndoe")

      refute_predicate external_identity, :valid?
      assert_includes external_identity.errors[:base], "External login 'johndoe' is already linked to @johndoe's account."
    end

    test "requires SCIM user_name attribute to be unique for the provider for non scim managed enterprise when scim data is not active" do
      existing = create :external_identity, user: create(:user, login: "johndoe"),
        provider: @provider, scim_user_data: scim_data(user_name: "johndoe")

      external_identity = build :external_identity,
        provider: @provider, scim_user_data: scim_data(user_name: "johndoe", active: "false")

      refute_predicate external_identity, :valid?
      assert_includes external_identity.errors[:base], "External login 'johndoe' is already linked to @johndoe's account."
    end
  end

  context "identity_provider", team_synchronization_available: true do
    test "returns correct external identifier attribute name for azure" do
      other_provider = create(:organization_saml_provider)

      create(:team_sync_tenant, organization: other_provider.organization)
      team = create(:team, organization: other_provider.organization)

      assert_equal ExternalIdentity.identity_provider(team), "http://schemas.microsoft.com/identity/claims/objectidentifier"
    end

    test "defaults to SCIM common attribute externalId" do
      okta_tenant = create(:team_sync_tenant, :okta)
      team = create(:team, organization: okta_tenant.organization)

      assert_equal ExternalIdentity.identity_provider(team), "externalId"
    end
  end

  test "scim_managed_enterprise returns false" do
    identity = create :external_identity, user: @user,
      provider: @provider, saml_user_data: saml_data(name_id: "Mona")

    refute_predicate identity, :scim_managed_enterprise?
  end

  test "cleanup_destroyed_user_data? returns false" do
    identity = create :external_identity, user: @user,
      provider: @provider, saml_user_data: saml_data(name_id: "Mona")

    refute_predicate identity, :cleanup_destroyed_user_data?
  end
end

module ExternalIdentityManagedSharedTests
  def test_delete_external_identity_group_memberships_if_marked_as_deleted_synchronously
    external_identity = @external_group_with_teams.external_identity_group_memberships.first.external_identity
    assert_predicate @external_group_with_teams.external_group_teams, :any?
    assert_predicate external_identity.external_identity_group_memberships, :any?

    @external_group_with_teams.external_group_teams.each do |group_team|
      assert external_identity.user.in?(group_team.team.organization.members)
    end

    perform_enqueued_jobs(only: [ExternalGroupMemberReconcileJob]) do
      external_identity.disable
      external_identity.mark_deleted
      external_identity.save
    end

    perform_enqueued_jobs only: [ExternalGroupTeamReconcileJob]
    perform_enqueued_jobs only: [RemoveOrgMemberJob]
    perform_enqueued_jobs only: [RevokeOrgMembershipAbilitiesJob]

    external_identity.reload

    assert_predicate @external_group_with_teams.reload.external_group_teams, :any?
    refute_predicate external_identity.external_identity_group_memberships, :any?

    @external_group_with_teams.external_group_teams.each do |group_team|
      refute external_identity.user.in?(group_team.team.organization.members)
    end
  end

  def test_passes_and_logs_caller_param_on_external_group_membership_reconcile_job_when_deleting_identity_group_memberships
    external_identity = @external_group_with_teams.external_identity_group_memberships.first.external_identity
    assert_predicate @external_group_with_teams.external_group_teams, :any?
    assert_predicate external_identity.external_identity_group_memberships, :any?

    @external_group_with_teams.external_group_teams.each do |group_team|
      assert external_identity.user.in?(group_team.team.organization.members)
    end

    base_log = {
      "gh.caller" => "ExternalIdentity"
    }
    log_1 = base_log.merge({ "info.message" => "Starting external_group_member_reconcile_job" })
    log_2 = base_log.merge({ "info.message" => "Finished external_group_member_reconcile_job" })

    assert_logged(**log_1) do
      assert_logged(**log_2) do
        perform_enqueued_jobs(only: ExternalGroupMemberReconcileJob) do
          external_identity.disable
          external_identity.mark_deleted
          external_identity.save
        end
      end
    end
  end

  def test_delete_works_when_there_is_no_linked_team
    external_identity = @external_group.external_identity_group_memberships.first.external_identity
    refute_predicate @external_group.external_group_teams, :any?
    assert_predicate external_identity.external_identity_group_memberships, :any?

    perform_enqueued_jobs(only: [ExternalGroupMemberReconcileJob]) do
      external_identity.mark_deleted
      external_identity.save
    end

    perform_enqueued_jobs only: [ExternalGroupTeamReconcileJob]
    perform_enqueued_jobs only: [RemoveOrgMemberJob]
    perform_enqueued_jobs only: [RevokeOrgMembershipAbilitiesJob]

    external_identity.reload

    assert_predicate external_identity, :deleted_at
  end

  def test_disable_does_not_remove_external_identity_group_memberships_but_removes_organization_memberships
    external_identity = @external_group_with_teams.external_identity_group_memberships.first.external_identity
    assert_predicate @external_group_with_teams.external_group_teams, :any?
    assert_predicate external_identity.external_identity_group_memberships, :any?

    @external_group_with_teams.external_group_teams.each do |group_team|
      assert external_identity.user.in?(group_team.team.organization.members)
    end

    perform_enqueued_jobs(only: [ExternalGroupMemberReconcileJob]) do
      external_identity.disable
      external_identity.save
    end

    perform_enqueued_jobs only: [ExternalGroupTeamReconcileJob]
    perform_enqueued_jobs only: [RemoveOrgMemberJob]
    perform_enqueued_jobs only: [RevokeOrgMembershipAbilitiesJob]

    external_identity.reload

    assert_predicate @external_group_with_teams.reload.external_group_teams, :any?
    assert_predicate external_identity.external_identity_group_memberships, :any?

    @external_group_with_teams.external_group_teams.each do |group_team|
      refute external_identity.user.in?(group_team.team.organization.members)
    end
  end

  def test_disable_works_when_there_is_no_linked_team
    external_identity = @external_group.external_identity_group_memberships.first.external_identity
    refute_predicate @external_group.external_group_teams, :any?
    assert_predicate external_identity.external_identity_group_memberships, :any?

    perform_enqueued_jobs(only: [ExternalGroupMemberReconcileJob]) do
      external_identity.disable
      external_identity.save
    end

    perform_enqueued_jobs only: [ExternalGroupTeamReconcileJob]

    external_identity.reload

    assert_predicate external_identity, :disabled_at
  end

  def test_enable_reinstate_external_identity_group_memberships_in_organization
    external_identity = @external_group_with_teams.external_identity_group_memberships.first.external_identity
    assert_predicate @external_group_with_teams.external_group_teams, :any?
    assert_predicate external_identity.external_identity_group_memberships, :any?

    @external_group_with_teams.external_group_teams.each do |group_team|
      assert external_identity.user.in?(group_team.team.organization.members)
    end

    ExternalGroupTeamReconcileJob.stubs(:enqueue_interval).returns(0)

    perform_enqueued_jobs(only: [ExternalGroupMemberReconcileJob]) do
      external_identity.disable
      external_identity.save
    end

    perform_enqueued_jobs only: [ExternalGroupTeamReconcileJob]
    perform_enqueued_jobs only: [RemoveOrgMemberJob]
    perform_enqueued_jobs only: [RevokeOrgMembershipAbilitiesJob]

    external_identity.reload

    @external_group_with_teams.external_group_teams.each do |group_team|
      refute external_identity.user.in?(group_team.team.organization.members)
    end

    assert_predicate @external_group_with_teams.external_group_teams, :any?
    assert_predicate external_identity.external_identity_group_memberships, :any?

    # In essence disabling and enabling is a no-op, since ExternalGroupTeamReconcileJob will will exit early
    perform_enqueued_jobs(only: [ExternalGroupMemberReconcileJob]) do
      external_identity.enable
      external_identity.save
    end

    perform_enqueued_jobs only: [ExternalGroupTeamReconcileJob]

    external_identity.reload

    assert_predicate @external_group_with_teams.external_group_teams, :any?
    assert_predicate external_identity.external_identity_group_memberships, :any?

    @external_group_with_teams.external_group_teams.each do |group_team|
      assert external_identity.user.in?(group_team.team.organization.reload.members)
    end
  end

  def test_enable_works_when_there_is_no_linked_team
    external_identity = @external_group.external_identity_group_memberships.first.external_identity
    refute_predicate @external_group.external_group_teams, :any?
    assert_predicate external_identity.external_identity_group_memberships, :any?

    perform_enqueued_jobs(only: [RemoveOrgMemberJob, RevokeOrgMembershipAbilitiesJob, ExternalGroupTeamReconcileJob]) do
      external_identity.disable
      external_identity.save
    end

    external_identity.reload

    assert_predicate external_identity, :disabled_at

    perform_enqueued_jobs(only: [RemoveOrgMemberJob, RevokeOrgMembershipAbilitiesJob, ExternalGroupTeamReconcileJob]) do
      external_identity.enable
      external_identity.save
    end

    external_identity.reload

    refute_predicate external_identity, :disabled_at
  end

  def test_validations_does_not_require_scim_user_name_to_be_unique_for_scim_managed_provider_when_the_record_is_marked_as_disabled
    existing = create :external_identity, :scim, user: create(:user, login: "johndoe"),
      provider: @provider, scim_user_data: scim_data(user_name: "johndoe")
    existing.disable
    existing.save!

    external_identity = build :external_identity,
      provider: @provider, scim_user_data: scim_data(user_name: "johndoe")

    assert_predicate external_identity, :valid?
    assert_equal existing.scim_user_data.user_name, external_identity.scim_user_data.user_name
  end

  def test_validation_does_not_require_scim_user_name_to_be_unique_for_scim_managed_provider_when_scim_data_is_not_active
    existing = create :external_identity, :scim, user: create(:user, login: "johndoe"),
      provider: @provider, scim_user_data: scim_data(user_name: "johndoe")

    external_identity = build :external_identity,
     provider: @provider, scim_user_data: scim_data(user_name: "johndoe", active: "false")

    assert_predicate external_identity, :valid?
    assert_equal existing.scim_user_data.user_name, external_identity.scim_user_data.user_name
  end

  def test_destroy_external_identity_group_memberships_when_external_identity_destroyed
    external_identity = @external_group.external_identity_group_memberships.first.external_identity
    assert_difference "ExternalIdentityGroupMembership.count", -1 do
      external_identity.destroy
    end
  end

  def test_scim_managed_enterprise_returns_true
    identity = @user.external_identities.first

    assert_predicate identity, :scim_managed_enterprise?
  end

  def test_return_correct_team_memberships
    business = create(:business, :enterprise_managed)
    assert_difference "ExternalIdentityGroupMembership.count", 3 do
      create(:external_group, :with_members, :with_team, number_of_members: 3, business: business).reload
      assert_equal 3, ExternalIdentity.by_provider(business.external_provider).with_team_memberships.count
    end

    assert_difference "ExternalIdentityGroupMembership.count", 3 do
      create(:external_group, :with_members, number_of_members: 3, business: business).reload
      assert_equal 3, ExternalIdentity.by_provider(business.external_provider).with_team_memberships.count
    end
  end unless GitHub.single_business_environment?
end

class EmuExternalIdentityTest < GitHub::TestCase
  include ExternalIdentitySharedTests
  include ExternalIdentityManagedSharedTests

  fixtures do
    @user = create :emu, :owner
    @business = @user.enterprise_managed_business
    @provider = @business.saml_provider
    @business_provider = @business.saml_provider

    @user_identity = @user.external_identities.first

    @admin = @first_admin = @business.find_first_emu_owner

    @other_user = create :emu, business: @business
    @other_user.external_identities.first.destroy!

    @external_group = create :external_group, :with_members, business: @business, number_of_members: 1
    @external_group_with_teams = create :external_group, :with_teams, :with_members, business: @business, number_of_members: 1

    @event_name = "business.revoke_external_identity"
    @expected_payload = {
      name: @business.name,
      business: @business.name,
      business_id: @business.id,
      actor: @admin.login,
      actor_id: @admin.id,
      user: @other_user.login,
      user_id: @other_user.id,
    }
  end

  setup do
    disable_feature_flag(:disable_external_group_member_reconcile_job)
    disable_feature_flag(:disable_external_group_team_reconcile_job)
    Dsr.stubs(:delete_user).returns(nil)
  end

  context "delete" do
    test "delete an emu first business owner user external identity does not removes emails" do
      assert_nil @first_admin.external_identities.first

      external_identity = ExternalIdentity.new(
        user: @first_admin,
        provider: @business.saml_provider,
      )
      external_identity.save

      assert_equal external_identity, @first_admin.reload.external_identities.first
      refute_empty @first_admin.emails

      external_identity.destroy

      assert_empty @first_admin.reload.external_identities
      refute_empty @first_admin.emails
    end

    test "set an emu user's refresh token" do
      assert_nil @user_identity.external_identity_refresh_token
      assert_equal 0, ExternalIdentityRefreshToken.all.count

      @user_identity.set_refresh_token("abc123")

      assert_equal "abc123", @user_identity.external_identity_refresh_token.refresh_token
      assert_equal 1, ExternalIdentityRefreshToken.all.count
    end

    test "upates an emu user's refresh token" do
      @user_identity.set_refresh_token("abc123")
      assert_equal "abc123", @user_identity.external_identity_refresh_token.refresh_token
      assert_equal 1, ExternalIdentityRefreshToken.all.count

      @user_identity.set_refresh_token("a different token")
      assert_equal "a different token", @user_identity.external_identity_refresh_token.refresh_token
      assert_equal 1, ExternalIdentityRefreshToken.all.count
    end

    test "deleting an external identity removes emails" do
      assert_equal @user_identity, @user.external_identities.first
      refute_empty @user.emails

      @user_identity.destroy

      assert_empty @user.reload.external_identities
      assert_empty @user.emails
    end unless GitHub.single_business_environment?

    test "deleting an external identity clears and does not backfill commit contributions" do
      repo = create(:repository, owner: @user)
      create(:commit_contribution, user: @user, repository: repo)

      assert_equal @user_identity, @user.external_identities.first
      refute_empty CommitContribution.for_user(@user)

      CommitContribution.stubs(:throttle).yields
      CommitContribution.expects(:backfill_user!).never
      perform_enqueued_jobs(only: [UserContributionCacheRefreshJob, UserContributionsBackfillJob]) do
        @user_identity.destroy
      end

      assert_empty @user.reload.emails
      assert_empty CommitContribution.for_user(@user)
    end unless GitHub.single_business_environment?

    test "deleting an external identity suspends user" do
      assert_equal @user_identity, @user.external_identities.first
      refute_predicate @user, :suspended?

      @user_identity.destroy

      assert_empty @user.reload.external_identities
      assert_predicate @user.reload, :suspended?
    end
  end

  context "#cleanup_destroyed_user_data?" do
    test "returns true" do
      identity = @user.external_identities.first

      assert_predicate identity, :cleanup_destroyed_user_data?
    end
  end
end unless GitHub.single_business_environment?

class GHESSCIMExternalIdentityTest < GitHub::TestCase
  include AuthenticationHelpers::SAML
  include ExternalIdentitySharedTests
  include ExternalIdentityManagedSharedTests

  fixtures do
    setup_saml_auth_mode(with_scim: true)
    @admin = @user = create :ghes_scim_user
    @user_identity = @user.external_identities.first

    @business = @user_identity.provider.business
    @provider = @business.saml_provider
    @business_provider = @business.saml_provider

    @other_user = create :ghes_scim_user, business: @business
    @other_user.external_identities.first.destroy!

    @external_group = create :external_group, :with_members, business: @business, number_of_members: 1
    @external_group_with_teams = create :external_group, :with_teams, :with_members, business: @business, number_of_members: 1

    @event_name = "business.revoke_external_identity"
    @expected_payload = {
      name: @business.name,
      business: @business.name,
      business_id: @business.id,
      actor: @admin.login,
      actor_id: @admin.id,
      user: @other_user.login,
      user_id: @other_user.id,
    }
  end

  setup do
    setup_saml_auth_mode(with_scim: true)
  end

  context "delete" do
    test "users are not suspended when external identity is deleted" do
      assert_equal @user_identity, @user.external_identities.first
      refute_predicate @user, :suspended?
      refute_empty @user.emails
      emails = @user.emails

      @user_identity.destroy

      assert_empty @user.reload.external_identities
      refute_predicate @user.reload, :suspended?
      assert_same_elements emails, @user.reload.emails
    end
  end

  context "#cleanup_destroyed_user_data?" do
    test "returns false" do
      refute_predicate @user_identity, :cleanup_destroyed_user_data?
    end
  end
end if GitHub.single_business_environment?
