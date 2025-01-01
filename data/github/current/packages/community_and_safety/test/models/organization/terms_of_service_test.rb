# typed: true
# frozen_string_literal: true

require "test_helper"

class OrganizationTermsOfServiceTest < GitHub::TestCase
  setup do
    skip if GitHub.enterprise?
  end

  fixtures do
    @staff = create(:staff_admin_user)
    @org_admin = create(:user)
    @org = create(:organization, admin: @org_admin)
  end

  test "has OrganizationTermsOfServiceType enum for each terms of service name" do
    values = Platform::Enums::OrganizationTermsOfServiceType.values.values.map(&:value)

    Organization::TermsOfService::TERMS_OF_SERVICE_TYPES.each do |name|
      assert_includes values, name,
        "OrganizationTermsOfServiceType enum value not defined for #{name}"
    end
  end

  test "defaults all orgs to `Standard` terms type" do
    another_org = create(:organization, admin: @org_admin)

    assert_predicate another_org.terms_of_service, :standard?
  end

  test "does not create the organization's terms_of_service_acceptance when a tos is initialized" do
    assert_no_difference "Organization::TermsOfServiceAcceptance.count" do
      assert_predicate @org.terms_of_service, :standard?
    end
  end

  context "#async_name" do
    test "returns Standard if no key is set" do
      assert_equal "Standard", @org.terms_of_service.async_name.sync
    end

    test "returns Standard for an org that is not persisted with no id" do
      org = build(:organization)
      assert_equal "Standard", org.terms_of_service.async_name.sync
    end

    test "returns accepted ToS for an org that is not persisted with an id" do
      org = build(:organization, admin: @org_admin, id: 123456)
      org.terms_of_service.update(type: "Corporate", actor: @org_admin)

      assert_equal "Corporate", org.terms_of_service.async_name.sync
    end

    test "returns accepted ToS for org" do
      @org.terms_of_service.update(type: "Corporate", actor: @org_admin)
      assert_equal "Corporate", @org.terms_of_service.async_name.sync
    end
  end

  context "accepted type predicates" do
    test "#standard? true if on standard ToS" do
      assert @org.terms_of_service.standard?
    end

    test "#custom? true if on custom ToS" do
      @org.terms_of_service.update(type: "Custom", actor: @org_admin)
      assert @org.terms_of_service.custom?
    end

    test "#corporate? true if on corporate ToS" do
      @org.terms_of_service.update(type: "Corporate", actor: @org_admin)
      assert @org.terms_of_service.corporate?
    end

    test "#evaluation? true if on evaluation ToS" do
      @org.terms_of_service.update(type: "Evaluation", actor: @org_admin)
      assert @org.terms_of_service.evaluation?
    end

    test "#esa_education? true if on esa_education ToS" do
      @org.terms_of_service.update(type: "ESA+Education", actor: @org_admin)
      assert @org.terms_of_service.esa_education?
    end
  end

  context "#corporate_upgrade_prompt_enabled?" do
    test "true if prompt has been enabled by staff actor" do
      assert @org.terms_of_service.enable_corporate_upgrade_prompt
      assert @org.terms_of_service.corporate_upgrade_prompt_enabled?
    end

    test "false if prompt has not been enabled by staff actor" do
      refute @org.terms_of_service.corporate_upgrade_prompt_enabled?
    end
  end

  context "#corporate_upgrade_prompt_enabled_at" do
    test "returns time prompt was enabled at" do
      Timecop.freeze do
        time = Time.current.to_s
        assert @org.terms_of_service.enable_corporate_upgrade_prompt
        assert_equal time, @org.terms_of_service.corporate_upgrade_prompt_enabled_at
      end
    end

    test "nil if prompt is not enabled" do
      assert_nil @org.terms_of_service.corporate_upgrade_prompt_enabled_at
    end
  end

  context "#esa_education_upgrade_prompt_enabled?" do
    test "true if prompt has been enabled by staff actor" do
      @org.terms_of_service.enable_esa_education_upgrade_prompt
      assert @org.terms_of_service.esa_education_upgrade_prompt_enabled?
    end

    test "false if prompt has not been enabled by staff actor" do
      refute @org.terms_of_service.esa_education_upgrade_prompt_enabled?
    end
  end

  context "#esa_education_upgrade_prompt_enabled_at" do
    test "returns time prompt was enabled at" do
      Timecop.freeze do
        time = Time.current.to_s
        @org.terms_of_service.enable_esa_education_upgrade_prompt
        assert_equal time, @org.terms_of_service.esa_education_upgrade_prompt_enabled_at
      end
    end

    test "nil if prompt is not enabled" do
      assert_nil @org.terms_of_service.esa_education_upgrade_prompt_enabled_at
    end
  end

  context "#enable_corporate_upgrade_prompt" do
    test "resets banner notice for all org admins" do
      other_admin = create(:user)
      @org.add_admin(other_admin, adder: @org_admin)
      @org_admin.dismiss_notice("org_corporate_tos_banner")
      other_admin.dismiss_notice("org_corporate_tos_banner")
      assert @org_admin.dismissed_notice?("org_corporate_tos_banner")
      assert other_admin.dismissed_notice?("org_corporate_tos_banner")

      Timecop.freeze do
        assert @org.terms_of_service.enable_corporate_upgrade_prompt
        time = Time.current.to_s
        assert @org.terms_of_service.enable_corporate_upgrade_prompt
        assert_equal time, @org.terms_of_service.corporate_upgrade_prompt_enabled_at
      end

      refute @org_admin.dismissed_notice?("org_corporate_tos_banner")
      refute other_admin.dismissed_notice?("org_corporate_tos_banner")
    end

    test "creates the organization's terms_of_service_upgrade_prompt when it doesn't exist" do
      assert_changes -> { Organization::TermsOfServiceUpgradePrompt.count }, from: 0, to: 1 do
        assert @org.terms_of_service.enable_corporate_upgrade_prompt
      end
      assert_predicate Organization::TermsOfServiceUpgradePrompt.first, :corporate?
    end

    test "creates the organization's terms_of_service_upgrade_prompt when a different terms exists" do
      assert @org.terms_of_service.enable_esa_education_upgrade_prompt

      assert_predicate Organization::TermsOfServiceUpgradePrompt.last, :esa_education?

      assert_changes -> { Organization::TermsOfServiceUpgradePrompt.count }, from: 1, to: 2 do
        assert @org.terms_of_service.enable_corporate_upgrade_prompt
      end

      assert_predicate Organization::TermsOfServiceUpgradePrompt.last, :corporate?
    end

    test "updates rather than creating the organization's terms_of_service_acceptance when it exists" do
      assert @org.terms_of_service.enable_corporate_upgrade_prompt

      assert_no_difference "Organization::TermsOfServiceUpgradePrompt.count" do
        assert @org.terms_of_service.enable_corporate_upgrade_prompt
      end

      result = Organization::TermsOfServiceUpgradePrompt.first!

      assert_predicate result, :corporate?
      refute_equal result.updated_at, result.created_at
    end
  end

  context "#enable_esa_education_upgrade_prompt" do
    test "resets banner notice for all org admins" do
      other_admin = create(:user)
      @org.add_admin(other_admin, adder: @org_admin)

      @org.terms_of_service.enable_esa_education_upgrade_prompt

      @org_admin.dismiss_notice("org_esa_education_tos_banner")
      other_admin.dismiss_notice("org_esa_education_tos_banner")

      assert @org_admin.dismissed_notice?("org_esa_education_tos_banner")
      assert other_admin.dismissed_notice?("org_esa_education_tos_banner")

      Timecop.freeze do
        @org.terms_of_service.enable_esa_education_upgrade_prompt
        time = Time.current.to_s
        @org.terms_of_service.enable_esa_education_upgrade_prompt
        assert_equal time, @org.terms_of_service.esa_education_upgrade_prompt_enabled_at
      end

      refute @org_admin.dismissed_notice?("org_esa_education_tos_banner")
      refute other_admin.dismissed_notice?("org_esa_education_tos_banner")
    end

    test "creates the organization's terms_of_service_upgrade_prompt when it doesn't exist" do
      assert_changes -> { Organization::TermsOfServiceUpgradePrompt.count }, from: 0, to: 1 do
        assert @org.terms_of_service.enable_esa_education_upgrade_prompt
      end
      assert_predicate Organization::TermsOfServiceUpgradePrompt.first, :esa_education?
    end

    test "creates the organization's terms_of_service_upgrade_prompt when a different terms exists" do
      assert @org.terms_of_service.enable_corporate_upgrade_prompt

      assert_predicate Organization::TermsOfServiceUpgradePrompt.last, :corporate?

      assert_changes -> { Organization::TermsOfServiceUpgradePrompt.count }, from: 1, to: 2 do
        assert @org.terms_of_service.enable_esa_education_upgrade_prompt
      end

      assert_predicate Organization::TermsOfServiceUpgradePrompt.last, :esa_education?
    end

    test "updates rather than creating the organization's terms_of_service_acceptance when it exists" do
      assert @org.terms_of_service.enable_esa_education_upgrade_prompt

      assert_no_difference "Organization::TermsOfServiceUpgradePrompt.count" do
        assert @org.terms_of_service.enable_esa_education_upgrade_prompt
      end

      result = Organization::TermsOfServiceUpgradePrompt.first!

      assert_predicate result, :esa_education?
      refute_equal result.updated_at, result.created_at
    end
  end

  context "#update" do
    test "updates the terms of service for an organization" do
      assert_predicate @org.terms_of_service, :standard?
      assert @org.terms_of_service.update(type: "Corporate", actor: @org_admin)
      assert_predicate @org.terms_of_service, :corporate?
    end

    test "requires change note for staff actor" do
      assert_predicate @org.terms_of_service, :standard?
      refute @org.terms_of_service.update(type: "Corporate", actor: @staff, staff_actor: true)
      assert_predicate @org.terms_of_service, :standard?
    end

    test "returns false for an organization with no id" do
      org = build(:organization, admin: @org_admin)

      assert_predicate org.terms_of_service, :standard?
      refute org.terms_of_service.update(type: "Corporate", actor: @org_admin)
      assert_predicate org.terms_of_service, :standard?
    end

    test "updates the terms of service for an organization that is not persisted but has an id" do
      org = build(:organization, admin: @org_admin, id: 123456)

      assert_predicate org.terms_of_service, :standard?
      assert org.terms_of_service.update(type: "Corporate", actor: @org_admin)
      assert_predicate org.terms_of_service, :corporate?
    end

    test "returns false if invalid ToS" do
      assert_predicate @org.terms_of_service, :standard?
      refute @org.terms_of_service.update(type: "not a valid tos type", actor: @org_admin)
      assert_predicate @org.terms_of_service, :standard?
    end

    test "updates company name if specified" do
      company = Company.create!(name: "Winston's Peanut Butter Co.")
      @org.company = company
      assert_equal "Winston's Peanut Butter Co.", @org.company.name
      assert_predicate @org.terms_of_service, :standard?
      assert @org.terms_of_service.update(type: "Corporate", actor: @org_admin, company_name: "Example, Inc.")
      assert_predicate @org.terms_of_service, :corporate?
      assert_equal "Example, Inc.", @org.reload.company.name
    end

    test "company can be removed by passing a blank string in for company_name" do
      org = create(:organization, company_name: "Company Name")
      org.terms_of_service.update(
        type: "Corporate",
        actor: org.admins.first,
        company_name: "Company Name",
      )

      assert_equal "Company Name", org.company.name

      org.terms_of_service.update(
        type: "Standard",
        actor: org.admins.first,
        company_name: "",
      )

      assert_nil org.reload.company
    end

    test "company can be removed by setting the terms type to Standard" do
      org = create(:organization, company_name: "Company Name")
      org.terms_of_service.update(
        type: "Corporate",
        actor: org.admins.first,
        company_name: "Company Name",
      )

      assert_equal "Company Name", org.company.name

      org.terms_of_service.update(
        type: "Standard",
        actor: org.admins.first
      )

      assert_nil org.reload.company
    end

    test "does not change company name if company_name is not specified" do
      org = create(:organization, company_name: "Company Name")
      company = Company.create!(name: "Company Name")
      org.company = company
      assert_equal "Company Name", org.company.name
      assert org.terms_of_service.update(type: "Corporate", actor: org.admins.first)
      assert_equal "Company Name", org.reload.company.name
    end

    test "sets company name to nil if organization removed from business" do
      @org.company = Company.create!(name: "Example, Inc.")
      @org.update!(company_name: @org.company.name)
      refute_nil @org.reload.company_name
      assert @org.terms_of_service.update(type: "Corporate", actor: @org_admin, removed_from_business: true)
      assert_nil @org.reload.company_name
    end

    test "unlinks trade screening record if organization terms of service change" do
      org_admin = create(:user, :with_trade_screening_record)
      org = create(:organization, admin: org_admin)
      org_admin.link_trade_screening_record_to_org(organization: org)
      assert_predicate @org.terms_of_service, :standard?

      org.terms_of_service.update(type: "Corporate", actor: org_admin)

      assert_predicate org.terms_of_service, :corporate?
      refute_predicate org.reload, :has_linked_trade_screening_record?
    end

    test "updating terms of service creates an audit log event" do
      # Uses the AuditLogSubscriber to listen for org.update_terms_of_service events
      events = subscribe "org.update_terms_of_service"

      expected_payload = {
        actor: @org_admin.login,
        actor_id: @org_admin.id,
        org_id: @org.id,
        org: @org.login,
        terms_of_service_type: {
          old_value: "Standard",
          new_value: "Corporate",
        },
      }

      @org.terms_of_service.update(
        type: "Corporate",
        actor: @org_admin,
      )

      assert event = events.pop, "an event was expected"
      assert_equal "org.update_terms_of_service", event.name
      assert_equal expected_payload, event.payload
    end

    test "updating terms of service as staff creates an audit log event" do
      # Uses the AuditLogSubscriber to listen for staff.update_terms_of_service events
      events = subscribe "staff.update_terms_of_service"

      expected_payload = {
        org_id: @org.id,
        org: @org.login,
        terms_of_service_type: {
          old_value: "Standard",
          new_value: "Corporate",
        },
        terms_of_service_change_reason: "Changed stuff",
        staff_actor: @staff.login,
        staff_actor_id: @staff.id,
        actor: User.staff_user.login,
        actor_id: User.staff_user.id,
      }

      @org.terms_of_service.update(
        type: "Corporate",
        actor: @staff,
        staff_actor: true,
        change_note: "Changed stuff",
      )

      assert event = events.pop, "an event was expected"
      assert_equal "staff.update_terms_of_service", event.name
      assert_equal expected_payload, event.payload
    end

    test "refuses to update terms of service if the organization is archived" do
      org = create(:archived_organization, admin: @org_admin)
      refute org.terms_of_service.update(
        type: "Corporate",
        actor: @org_admin,
      )
      assert_equal org.errors.full_messages.to_sentence, "This organization cannot change terms of service because it is archived."
    end

    test "sets the terms of service type" do
      assert_predicate @org.terms_of_service, :standard?

      @org.terms_of_service.update(type: "Custom", actor: @org_admin)
      assert_predicate @org.terms_of_service, :custom?
    end

    test "does not create the organization's terms_of_service_acceptance when it exists" do
      @org.terms_of_service.update(type: "Custom", actor: @org_admin)

      assert_no_difference "Organization::TermsOfServiceAcceptance.count" do
        @org.terms_of_service.update(type: "Corporate", actor: @org_admin)
      end

      assert_predicate @org.terms_of_service, :corporate?
      assert_predicate Organization::TermsOfServiceAcceptance.last, :corporate?
    end
  end
end
