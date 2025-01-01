# typed: true
# frozen_string_literal: true

require "test_helper"

class BusinessOrganizationTransferTest < GitHub::TestCase
  include AuditLog::IntegrationTestHelpers
  include HydroTestHelpers

  fixtures do
    @site_admin = create :staff_admin_user
    @owner = create :user
    @organization = create :business_plus_organization
    @from_business = create :business, organizations: [@organization], owners: [@owner]
    @to_business = create :business, owners: [@owner]
  end

  context "validations" do
    test "ensure organization is present" do
      transfer = BusinessOrganizationTransfer.create \
        organization: nil,
        from_business: @from_business,
        to_business: @to_business,
        actor: @owner

      refute_predicate transfer, :valid?
      assert_includes transfer.errors[:organization], "can't be blank"
    end

    test "ensure from_business is present" do
      transfer = BusinessOrganizationTransfer.create \
        organization: @organization,
        from_business: nil,
        to_business: @to_business,
        actor: @owner

      refute_predicate transfer, :valid?
      assert_includes transfer.errors[:from_business], "can't be blank"
    end

    test "ensure to_business is present" do
      transfer = BusinessOrganizationTransfer.create \
        organization: @organization,
        from_business: @from_business,
        to_business: nil,
        actor: @owner

      refute_predicate transfer, :valid?
      assert_includes transfer.errors[:to_business], "can't be blank"
    end

    test "ensure actor is present" do
      transfer = BusinessOrganizationTransfer.create \
        organization: @organization,
        from_business: @from_business,
        to_business: @to_business,
        actor: nil

      refute_predicate transfer, :valid?
      assert_includes transfer.errors[:actor], "can't be blank"
    end

    test "ensure organization is a member of from_business" do
      random_org = create :business_plus_organization
      transfer = BusinessOrganizationTransfer.create \
        organization: random_org,
        from_business: @from_business,
        to_business: @to_business,
        actor: @from_business.owners.first

      refute_predicate transfer, :valid?
      assert_includes \
        transfer.errors[:base],
        "The organization to transfer must belong to the source enterprise."
    end

    test "ensure organization has owners" do
      @organization.admins.delete_all

      transfer = BusinessOrganizationTransfer.create \
        organization: @organization,
        from_business: @from_business,
        to_business: @to_business,
        actor: @from_business.owners.first

      refute_predicate transfer, :valid?
      assert_includes \
        transfer.errors[:base],
        "The organization to transfer must have owners."
    end

    test "ensure actor is an owner of both from_business and to_business" do
      owner_of_from_business_only = create :user
      @from_business.add_owner(owner_of_from_business_only, actor: @from_business.owners.first)

      transfer = BusinessOrganizationTransfer.create \
        organization: @organization,
        from_business: @from_business,
        to_business: @to_business,
        actor: owner_of_from_business_only

      refute_predicate transfer, :valid?
      assert_includes \
        transfer.errors[:base],
        "You must be an owner of both enterprises to perform this transfer."
    end

    test "ensure actor does not need to own both enterprises when site_admin_transfer override is set" do
      site_admin = create :staff_admin_user

      transfer = BusinessOrganizationTransfer.create \
        organization: @organization,
        from_business: @from_business,
        to_business: @to_business,
        actor: site_admin,
        site_admin_transfer: true

      assert_predicate transfer, :valid?
    end

    test "ensure from_business and to_business are not the same" do
      transfer = BusinessOrganizationTransfer.create \
        organization: @organization,
        from_business: @from_business,
        to_business: @from_business,
        actor: @owner

      refute_predicate transfer, :valid?
      assert_includes transfer.errors[:base], "The source enterprise cannot be the destination enterprise."
    end

    test "ensure spammy from_business cannot transfer organizations" do
      @from_business.mark_as_spammy
      assert_predicate @from_business, :spammy?

      transfer = BusinessOrganizationTransfer.create \
        organization: @organization,
        from_business: @from_business,
        to_business: @to_business,
        actor: @owner

      refute_predicate transfer, :valid?
      assert_includes \
        transfer.errors[:base],
        "The source enterprise has been flagged and cannot transfer organizations."
    end

    test "ensure enterprise managed from_business cannot transfer organizations" do
      emu_business = create :business, business_type: :enterprise_managed, shortcode: "vrygd",
        owners: [@owner]
      assert_predicate emu_business, :enterprise_managed?

      transfer = BusinessOrganizationTransfer.create \
        organization: @organization,
        from_business: emu_business,
        to_business: @to_business,
        actor: @owner

      refute_predicate transfer, :valid?
      assert_includes \
        transfer.errors[:base],
        "The source enterprise is externally managed and cannot transfer organizations."
    end

    test "ensure trial from_business cannot transfer organizations" do
      @from_business.update! trial_expires_at: Billing::EnterpriseCloudTrial.trial_length.from_now
      assert_predicate @from_business, :trial?

      transfer = BusinessOrganizationTransfer.create \
        organization: @organization,
        from_business: @from_business,
        to_business: @to_business,
        actor: @owner

      refute_predicate transfer, :valid?
      assert_includes \
        transfer.errors[:base],
        "The source enterprise is a trial and cannot transfer organizations."
    end

    test "ensure trial from_business can transfer organizations when site_admin_transfer override is set" do
      site_admin = create :staff_admin_user
      @from_business.update! \
        trial_expires_at: Billing::EnterpriseCloudTrial.trial_length.from_now
      assert_predicate @from_business, :trial?

      transfer = BusinessOrganizationTransfer.create \
        organization: @organization,
        from_business: @from_business,
        to_business: @to_business,
        actor: site_admin,
        site_admin_transfer: true

      assert_predicate transfer, :valid?
    end

    test "ensure spammy to_business cannot receive organizations" do
      @to_business.mark_as_spammy
      assert_predicate @to_business, :spammy?

      transfer = BusinessOrganizationTransfer.create \
        organization: @organization,
        from_business: @from_business,
        to_business: @to_business,
        actor: @owner

      refute_predicate transfer, :valid?
      assert_includes \
        transfer.errors[:base],
        "The destination enterprise has been flagged and cannot receive organizations."
    end

    test "ensure enterprise managed to_business cannot receive organizations" do
      emu_business = create :business, business_type: :enterprise_managed, shortcode: "vrygd",
        owners: [@owner]
      assert_predicate emu_business, :enterprise_managed?

      transfer = BusinessOrganizationTransfer.create \
        organization: @organization,
        from_business: @from_business,
        to_business: emu_business,
        actor: @owner

      refute_predicate transfer, :valid?
      assert_includes \
        transfer.errors[:base],
        "The destination enterprise is externally managed and cannot receive organizations."
    end

    test "ensure trial to_business cannot receive organizations" do
      @to_business.update! trial_expires_at: Billing::EnterpriseCloudTrial.trial_length.from_now
      assert_predicate @to_business, :trial?

      transfer = BusinessOrganizationTransfer.create \
        organization: @organization,
        from_business: @from_business,
        to_business: @to_business,
        actor: @owner

      refute_predicate transfer, :valid?
      assert_includes \
        transfer.errors[:base],
        "The destination enterprise is a trial and cannot receive organizations."
    end

    test "ensure to_business has sufficient seats to perform the transfer" do
      @from_business.update(seats: 10)
      @to_business.update(seats: 1)
      @organization.invite(email: "one@example.com", inviter: @organization.admins.first)
      @organization.invite(email: "two@example.com", inviter: @organization.admins.first)

      transfer = BusinessOrganizationTransfer.create \
        organization: @organization,
        from_business: @from_business,
        to_business: Business.find(@to_business.id),
        actor: @owner

      refute_predicate transfer, :valid?
      assert_includes \
        transfer.errors[:base],
        "The destination enterprise needs 2 additional seats to transfer #{@organization}."
    end

    test "ensure transfer is valid when to_business has sufficient seats to perform the transfer" do
      @from_business.update(seats: 10)
      @to_business.update(seats: 10)
      @organization.invite(email: "one@example.com", inviter: @organization.admins.first)
      @organization.invite(email: "two@example.com", inviter: @organization.admins.first)

      transfer = BusinessOrganizationTransfer.create \
        organization: @organization,
        from_business: @from_business,
        to_business: Business.find(@to_business.id),
        actor: @owner

      assert_predicate transfer, :valid?
    end

    test "bypass transfer is valid when to_business has sufficient seats to perform the transfer when metered" do
      @from_business.update(seats: 10)
      @to_business.update(seats: 0)
      @from_business.customer.update(billing_type: false)
      @to_business.customer.update(metered_ghe: true)
      @organization.invite(email: "one@example.com", inviter: @organization.admins.first)
      @organization.invite(email: "two@example.com", inviter: @organization.admins.first)

      transfer = BusinessOrganizationTransfer.create \
        organization: @organization,
        from_business: @from_business,
        to_business: Business.find(@to_business.id),
        actor: @owner

      assert_predicate transfer, :valid?
    end

    context "orgs with marketplace apps" do
      test "ensure org with marketplace app sybscriptions cannot be transferred" do
        from_business = create(:business, :with_self_serve_payment)
        owner = from_business.owners.first
        organization = create :organization, business: from_business, admins: [owner]
        plan_subscription = create :billing_plan_subscription, :business_owned, customer: from_business.customer
        create(:billing_subscription_item,
          plan_subscription: plan_subscription,
          organization: organization,
        )
        to_business = create(:business, :with_self_serve_payment, owners: [owner])

        transfer = BusinessOrganizationTransfer.create \
          organization: organization,
          from_business: from_business.reload,
          to_business: to_business,
          actor: owner

        assert_predicate transfer, :business_org_has_marketplace_subscriptions?
        refute_predicate transfer, :valid?
        assert_includes \
          transfer.errors[:base],
          "The organization to transfer must not have Marketplace App subscriptions."
      end

      test "ensure org without marketplace app subscriptions can be transferred" do
        from_business = create(:business, :with_self_serve_payment)
        owner = from_business.owners.first
        organization = create :organization, business: from_business, admins: [owner]
        to_business = create(:business, :with_self_serve_payment, owners: [owner])

        transfer = BusinessOrganizationTransfer.create \
          organization: organization,
          from_business: from_business.reload,
          to_business: to_business,
          actor: owner

        refute_predicate transfer, :business_org_has_marketplace_subscriptions?
        assert_predicate transfer, :valid?
      end
    end
  end

  context "in_progress scope" do
    test "returns transfers that have not completed and have not failed" do
      assert_empty BusinessOrganizationTransfer.in_progress

      completed = create :business_organization_transfer
      completed.touch :completed_at
      failed = create :business_organization_transfer
      failed.touch :failed_at
      in_progress = create :business_organization_transfer

      assert_same_elements [in_progress], BusinessOrganizationTransfer.in_progress
    end
  end

  context "failed scope" do
    test "returns transfers that have failed" do
      assert_empty BusinessOrganizationTransfer.failed

      completed = create :business_organization_transfer
      completed.touch :completed_at
      failed = create :business_organization_transfer
      failed.touch :failed_at
      in_progress = create :business_organization_transfer

      assert_same_elements [failed], BusinessOrganizationTransfer.failed
    end
  end

  context "not_complete scope" do
    test "returns transfers that have not completed or have failed" do
      assert_empty BusinessOrganizationTransfer.not_complete

      completed = create :business_organization_transfer
      completed.touch :completed_at
      failed = create :business_organization_transfer
      failed.touch :failed_at
      in_progress = create :business_organization_transfer

      assert_same_elements [in_progress, failed], BusinessOrganizationTransfer.not_complete
    end
  end

  context "completed scope" do
    test "returns transfers that have failed" do
      assert_empty BusinessOrganizationTransfer.completed

      completed = create :business_organization_transfer
      completed.touch :completed_at
      failed = create :business_organization_transfer
      failed.touch :failed_at
      in_progress = create :business_organization_transfer

      assert_same_elements [completed], BusinessOrganizationTransfer.completed
    end
  end

  context "#perform!" do
    test "transfers the organization to the destination enterprise" do
      assert_includes @from_business.organizations, @organization
      refute_includes @to_business.organizations, @organization

      transfer = BusinessOrganizationTransfer.create \
        organization: @organization,
        from_business: @from_business,
        to_business: @to_business,
        actor: @owner

      transfer.perform!

      refute_includes @from_business.reload.organizations, @organization
      assert_includes @to_business.reload.organizations, @organization
    end

    test "returns the new Business::OrganizationMembership for the organization" do
      transfer = BusinessOrganizationTransfer.create \
        organization: @organization,
        from_business: @from_business,
        to_business: @to_business,
        actor: @owner

      membership = transfer.perform!

      assert membership.is_a?(Business::OrganizationMembership)
      assert_predicate membership, :valid?
      assert_equal @organization, membership.organization
      assert_equal @to_business, membership.business
    end

    test "sets completed_at when organization is successfully transferred" do
      transfer = BusinessOrganizationTransfer.create \
        organization: @organization,
        from_business: @from_business,
        to_business: @to_business,
        actor: @owner
      assert_nil transfer.completed_at

      transfer.perform!

      refute_nil transfer.completed_at
      assert_nil transfer.failed_at
      assert_nil transfer.failed_reason
    end

    test "sends email when organization is successfully transferred" do
      transfer = BusinessOrganizationTransfer.create \
        organization: @organization,
        from_business: @from_business,
        to_business: @to_business,
        actor: @owner
      refute_predicate transfer, :completed?

      perform_enqueued_jobs(only: [ApplicationDeliveryJob]) do
        assert_difference "ActionMailer::Base.deliveries.size", +1 do
          transfer.perform!
        end
      end

      assert_predicate transfer, :completed?

      mail = ActionMailer::Base.deliveries.last
      assert_equal \
        "[GitHub] #{@organization} was transferred from #{@from_business.name} to #{@to_business.name}",
        mail.subject
      assert_includes mail.bcc, @from_business.owners.first.email
      assert_includes mail.bcc, @to_business.owners.first.email
      assert_includes mail.bcc, @organization.admins.first.email
      assert_includes mail.html_part.body.to_s, T.must(transfer.actor).login
      assert_includes mail.text_part.body.to_s, T.must(transfer.actor).login
    end

    test "sends email when organization is successfully transferred via site admin" do
      transfer = BusinessOrganizationTransfer.create \
        organization: @organization,
        from_business: @from_business,
        to_business: @to_business,
        actor: @site_admin,
        site_admin_transfer: true
      refute_predicate transfer, :completed?

      perform_enqueued_jobs(only: [ApplicationDeliveryJob]) do
        assert_difference "ActionMailer::Base.deliveries.size", +1 do
          transfer.perform!
        end
      end

      assert_predicate transfer, :completed?

      mail = ActionMailer::Base.deliveries.last
      assert_equal \
        "[GitHub] #{@organization} was transferred from #{@from_business.name} to #{@to_business.name}",
        mail.subject
      assert_includes mail.bcc, @from_business.owners.first.email
      assert_includes mail.bcc, @to_business.owners.first.email
      assert_includes mail.bcc, @organization.admins.first.email
      refute_includes mail.html_part.body.to_s, T.must(transfer.actor).login
      refute_includes mail.text_part.body.to_s, T.must(transfer.actor).login
      assert_includes mail.html_part.body.to_s, "GitHub staff"
      assert_includes mail.text_part.body.to_s, "GitHub staff"
    end

    test "instruments org.transfer_outgoing audit log event when organization is successfully transferred" do
      transfer = BusinessOrganizationTransfer.create \
        organization: @organization,
        from_business: @from_business,
        to_business: @to_business,
        actor: @owner
      refute_predicate transfer, :completed?

      events = assert_performed_audit_entries(count: 1, only: "org.transfer_outgoing") do
        transfer.perform!
      end

      assert_predicate transfer, :completed?
      assert_equal last_performed_audit_entries, events

      expected_payload = {
        action: "org.transfer_outgoing",
        actor: @owner.login,
        org: @organization.login,
        org_id: @organization.id,
        business: @from_business.slug,
        business_id: @from_business.id,
        from_business: @from_business.slug,
        from_business_id: @from_business.id,
        to_business: @to_business.slug,
        to_business_id: @to_business.id,
      }
      assert_subset_hash expected_payload, events.first
    end

    test "instruments org.transfer audit log event when organization is successfully transferred" do
      transfer = BusinessOrganizationTransfer.create \
        organization: @organization,
        from_business: @from_business,
        to_business: @to_business,
        actor: @owner
      refute_predicate transfer, :completed?

      events = assert_performed_audit_entries(count: 1, only: "org.transfer") do
        transfer.perform!
      end

      assert_predicate transfer, :completed?
      assert_equal last_performed_audit_entries, events

      expected_payload = {
        action: "org.transfer",
        actor: @owner.login,
        org: @organization.login,
        org_id: @organization.id,
        business: @to_business.slug,
        business_id: @to_business.id,
        from_business: @from_business.slug,
        from_business_id: @from_business.id,
        to_business: @to_business.slug,
        to_business_id: @to_business.id,
      }
      assert_subset_hash expected_payload, events.first
    end

    test "publishes Hydro message when organization is successfully transferred" do
      transfer = BusinessOrganizationTransfer.create \
        organization: @organization,
        from_business: @from_business,
        to_business: @to_business,
        actor: @owner
      refute_predicate transfer, :completed?

      transfer.perform!

      @organization.reload

      assert_hydro_published({
          organization: Hydro::EntitySerializer.organization(@organization),
          source_enterprise: Hydro::EntitySerializer.business(@from_business),
          destination_enterprise: Hydro::EntitySerializer.business(@to_business),
          actor: Hydro::EntitySerializer.user(@owner),
          completed_at: transfer.completed_at,
          site_admin_transfer: false,
        },
        schema: "github.enterprise_account.v0.OrganizationTransfer"
      )
      assert_hydro_messages count: 1, schema: "github.enterprise_account.v0.OrganizationTransfer"
      assert_predicate transfer, :completed?
    end

    test "sets failed_at and failed_reason when transfer is invalid" do
      assert_includes @from_business.organizations, @organization
      refute_includes @to_business.organizations, @organization

      transfer = BusinessOrganizationTransfer.create \
        organization: @organization,
        from_business: @from_business,
        to_business: @to_business,
        actor: @owner

      # Simulate a now invalid transfer where to_business no longer exists
      transfer.update_column :to_business_id, 0

      transfer.perform!

      assert_nil transfer.completed_at
      refute_nil transfer.failed_at
      assert_equal "Destination enterprise can't be blank", transfer.failed_reason
      assert_includes @from_business.organizations, @organization
      refute_includes @to_business.organizations, @organization
    end

    test "publishes Hydro message when transfer fails" do
      assert_includes @from_business.organizations, @organization
      refute_includes @to_business.organizations, @organization

      transfer = BusinessOrganizationTransfer.create \
        organization: @organization,
        from_business: @from_business,
        to_business: @to_business,
        actor: @owner

      # Simulate a now invalid transfer where to_business no longer exists
      transfer.update_column :to_business_id, 0

      transfer.perform!

      assert_hydro_published({
          organization: Hydro::EntitySerializer.organization(@organization),
          source_enterprise: Hydro::EntitySerializer.business(@from_business),
          destination_enterprise: nil,
          actor: Hydro::EntitySerializer.user(@owner),
          failed_at: transfer.failed_at,
          failed_reason: "Destination enterprise can't be blank",
          site_admin_transfer: false,
        },
        schema: "github.enterprise_account.v0.OrganizationTransfer"
      )
      assert_hydro_messages(count: 1, schema: "github.enterprise_account.v0.OrganizationTransfer")
      assert_predicate transfer, :failed?
    end

    test "sends email when transfer fails" do
      assert_includes @from_business.organizations, @organization
      refute_includes @to_business.organizations, @organization

      transfer = BusinessOrganizationTransfer.create \
        organization: @organization,
        from_business: @from_business,
        to_business: @to_business,
        actor: @owner

      # Simulate a now invalid transfer where to_business no longer exists
      transfer.update_column :to_business_id, 0

      transfer.perform!

      perform_enqueued_jobs(only: [ApplicationDeliveryJob]) do
        assert_difference "ActionMailer::Base.deliveries.size", +1 do
          transfer.perform!
        end
      end

      refute_predicate transfer, :completed?
      assert_predicate transfer, :failed?

      mail = ActionMailer::Base.deliveries.last
      assert_equal \
        "[GitHub] Transferring #{@organization} failed",
        mail.subject
      assert_includes mail.bcc, @from_business.owners.first.email

      assert_includes @from_business.organizations, @organization
      refute_includes @to_business.organizations, @organization
    end
  end

  context "#fail!" do
    test "sets failed_at field" do
      transfer = BusinessOrganizationTransfer.create \
        organization: @organization,
        from_business: @from_business,
        to_business: @to_business,
        actor: @owner
      assert_nil transfer.failed_at
      refute_predicate transfer, :failed?

      transfer.fail!

      refute_nil transfer.failed_at
      assert_predicate transfer, :failed?
    end

    test "sets failed_reason field when provided" do
      transfer = BusinessOrganizationTransfer.create \
        organization: @organization,
        from_business: @from_business,
        to_business: @to_business,
        actor: @owner
      assert_nil transfer.failed_reason
      refute_predicate transfer, :failed?

      transfer.fail! reason: "Reasons"

      assert_equal "Reasons", transfer.failed_reason
      assert_predicate transfer, :failed?
    end
  end

  context "#in_progress?" do
    test "returns true when not completed and not failed" do
      transfer = BusinessOrganizationTransfer.create \
        organization: @organization,
        from_business: @from_business,
        to_business: @to_business,
        actor: @owner
      assert_predicate transfer, :in_progress?
    end

    test "returns false when completed" do
      transfer = BusinessOrganizationTransfer.create \
        organization: @organization,
        from_business: @from_business,
        to_business: @to_business,
        actor: @owner
      transfer.perform!
      assert_predicate transfer, :completed?
      refute_predicate transfer, :in_progress?
    end

    test "returns false when failed" do
      transfer = BusinessOrganizationTransfer.create \
        organization: @organization,
        from_business: @from_business,
        to_business: @to_business,
        actor: @owner
      transfer.touch :failed_at
      assert_predicate transfer, :failed?
      refute_predicate transfer, :completed?
      refute_predicate transfer, :in_progress?
    end
  end

  context "#completed?" do
    test "returns true when a transfer completed successfully" do
      transfer = BusinessOrganizationTransfer.create \
        organization: @organization,
        from_business: @from_business,
        to_business: @to_business,
        actor: @owner
      transfer.perform!

      assert_predicate transfer, :completed?
    end

    test "returns false when a transfer has not been performed" do
      transfer = BusinessOrganizationTransfer.create \
        organization: @organization,
        from_business: @from_business,
        to_business: @to_business,
        actor: @owner

      refute_predicate transfer, :completed?
    end

    test "returns false when a transfer failed" do
      transfer = BusinessOrganizationTransfer.create \
        organization: @organization,
        from_business: @from_business,
        to_business: @to_business,
        actor: @owner
      transfer.touch(:failed_at)

      refute_predicate transfer, :completed?
    end
  end

  context "#failed?" do
    test "returns true when a transfer failed" do
      transfer = BusinessOrganizationTransfer.create \
        organization: @organization,
        from_business: @from_business,
        to_business: @to_business,
        actor: @owner
      transfer.touch(:failed_at)

      assert_predicate transfer, :failed?
    end

    test "returns false when a transfer has not been performed" do
      transfer = BusinessOrganizationTransfer.create \
        organization: @organization,
        from_business: @from_business,
        to_business: @to_business,
        actor: @owner

      refute_predicate transfer, :failed?
    end

    test "returns false when a transfer completed successfully" do
      transfer = BusinessOrganizationTransfer.create \
        organization: @organization,
        from_business: @from_business,
        to_business: @to_business,
        actor: @owner
      transfer.perform!

      refute_predicate transfer, :failed?
    end
  end

  context "#show_actor?" do
    test "returns true when site_admin_transfer is false" do
      transfer = create :business_organization_transfer, site_admin_transfer: false
      refute_predicate transfer, :site_admin_transfer?
      assert_predicate transfer, :show_actor?
    end

    test "returns false when site_admin_transfer is true" do
      transfer = create :business_organization_transfer, site_admin_transfer: true
      assert_predicate transfer, :site_admin_transfer?
      refute_predicate transfer, :show_actor?
    end

    test "returns false when actor is nil" do
      transfer = create :business_organization_transfer
      other_admin = create(:user)
      transfer.from_business.add_owner other_admin, actor: transfer.actor
      transfer.to_business.add_owner other_admin, actor: transfer.actor
      transfer.from_business.remove_owner transfer.actor, actor: other_admin
      transfer.to_business.remove_owner transfer.actor, actor: other_admin
      transfer.actor.destroy
      refute_predicate transfer, :site_admin_transfer?
      refute_predicate transfer.reload, :show_actor?
    end
  end
end unless GitHub.single_business_environment?
