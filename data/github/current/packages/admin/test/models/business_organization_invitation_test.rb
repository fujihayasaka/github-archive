# typed: true
# frozen_string_literal: true

require "test_helper"
require "github/enterprise_accounts/kv"

class BusinessOrganizationInvitationTest < GitHub::TestCase
  def deliveries
    ActionMailer::Base.deliveries
  end

  if GitHub.business_organization_invitations_available?
    fixtures do
      @staff = create(:staff_admin_user)
      @admin = create :user
      @org_admin = create :user
      @org = create :business_plus_organization, admins: [@org_admin]
      @business = create :business, owners: [@admin], organizations: []

      @invite = create :business_organization_invitation,
        business: @business, inviter: @admin, invitee: @org

      @uninvited_org = create :organization, admins: [@org_admin]
      @redundant_invitation_time = (BusinessOrganizationInvitation::REDUNDANT_INVITATION_CUTOFF + 1).days.ago.freeze
      @non_redundant_invitation_time = (BusinessOrganizationInvitation::REDUNDANT_INVITATION_CUTOFF - 1).days.ago.freeze

      @emu = create :emu, :owner
      @emu_business = @emu.enterprise_managed_business
      @emu_org = create :organization, business: @emu_business, admin: @emu

      @listing_plan = create :marketplace_listing_plan, :verified_listing
      @org_plan_subscription = create :billing_plan_subscription, user: @org
      @business_plan_subscription = create :billing_plan_subscription, :business_owned, customer: @business.customer
    end

    context "creation" do
      test "creating an invitation adds an audit log entry" do
        events = subscribe("org.invite_to_business")
        create :business_organization_invitation,
          business: @business, inviter: @admin, invitee: @uninvited_org

        assert_equal 1, events.size
        event = events.first
        assert_equal @admin.id, event.payload[:actor_id]
        assert_equal @uninvited_org.id, event.payload[:org_id]
        assert_equal @business.id, event.payload[:business_id]
      end

      test "creating an invitation that fails validation does not add an audit log entry" do
        events = subscribe("org.invite_to_business")
        invitation = build :business_organization_invitation,
          inviter: @admin, invitee: @uninvited_org
        invitation.save

        assert_equal 0, events.size
      end
    end

    context "validations" do
      if GitHub.spamminess_check_enabled?
        test "spammy Businesses cannot invite Organizations" do
          @business.mark_as_spammy
          assert_predicate @business, :spammy?

          invitation = BusinessOrganizationInvitation.new \
            business: @business, invitee: @org, inviter: @admin
          refute_predicate invitation, :valid?
          assert_includes \
            invitation.errors[:base],
            "This enterprise has been flagged and cannot invite organizations."
        end
      end

      test "does not require a self-serve business" do
        business = create :business, owners: [@admin], organizations: []
        business.stubs(:can_self_serve?).returns(false)

        invite = BusinessOrganizationInvitation.new \
          business: business,
          inviter: @admin,
          invitee: @org

        assert_predicate invite, :valid?
      end

      test "require an org that doesn't belong to an enterprise" do
        @business.add_organization(@org)
        invite = BusinessOrganizationInvitation.new(business: @business,
                                                    inviter: @admin,
                                                    invitee: @org.reload)

        refute_predicate invite, :valid?
        assert_includes invite.errors[:base], "Organization #{@org.display_login} already belongs to an enterprise."
      end

      test "emus can't invite default enterprise organizations" do
        invite = BusinessOrganizationInvitation.new(business: @emu_business,
                                                    inviter: @emu,
                                                    invitee: @org.reload)

        refute_predicate invite, :valid?
        assert_includes \
          invite.errors[:base],
          "Organization invitations are not available for externally managed enterprises."
      end

      test "supports org that is invoiced" do
        org = create :organization
        org.switch_billing_type_to_invoice(org.admins.first)

        invite = BusinessOrganizationInvitation.new \
          business: @business, inviter: @admin, invitee: org

        assert_predicate org, :invoiced?
        assert_predicate invite, :valid?
      end

      test "require a business" do
        invite = BusinessOrganizationInvitation.new(inviter: @admin,
                                                    invitee: @org)
        refute_predicate invite, :valid?
        assert_includes invite.errors[:business], "can't be blank"
      end

      test "require an inviter" do
        invite = BusinessOrganizationInvitation.new(business: @business,
                                                    invitee: @org)
        refute_predicate invite, :valid?
        assert_includes invite.errors[:inviter], "can't be blank"
      end

      test "require an invitee" do
        invite = BusinessOrganizationInvitation.new(business: @business,
                                                    inviter: @admin)
        refute_predicate invite, :valid?
        assert_includes invite.errors[:invitee], "can't be blank"
      end

      test "inviter must be a business admin" do
        invitation = BusinessOrganizationInvitation.new \
          business: @business, invitee: @org, inviter: create(:user)
        refute_predicate invitation, :valid?
        assert_includes invitation.errors[:inviter], "must be an administrator of the enterprise."
      end

      test "org must not already be invited to the business" do
        invitation = BusinessOrganizationInvitation.new \
          business: @business, invitee: @org, inviter: @admin
        refute_predicate invitation, :valid?
        assert_includes invitation.errors[:base], "Organization #{@org.display_login} has already been invited to this enterprise."
      end

      test "org must not be upgrading to business in progress" do
        invitation = BusinessOrganizationInvitation.new \
          business: @business, invitee: @org, inviter: @admin
        business = create :business
        @org.upgrade_to_enterprise_in_progress!(business)
        refute_predicate invitation, :valid?
        assert_includes invitation.errors[:base], "Organization #{@org.display_login} can not be invited because it has an upgrade to enterprise in progress."
      end

      context "orgs with marketplace apps" do
        test "self-serve business must not be in trial period" do
          @business.stubs(:self_serve_payment?).returns(true)
          @business.stubs(:trial?).returns(true)
          Organization.any_instance.stubs(:active_marketplace_listing_subscription_items).returns(["dummy_item"])
          invitation = BusinessOrganizationInvitation.new \
            business: @business, invitee: @org, inviter: @admin

          refute_predicate invitation, :valid?
          assert_includes invitation.errors[:business], "cannot accept organizations with marketplace purchases during the trial period."
        end

        test "self-serve business have valid payment information" do
          @business.stubs(:self_serve_payment?).returns(true)
          @business.stubs(:has_valid_payment_method?).returns(false)
          Organization.any_instance.stubs(:active_marketplace_listing_subscription_items).returns(["dummy_item"])
          invitation = BusinessOrganizationInvitation.new \
            business: @business, invitee: @org, inviter: @admin

          refute_predicate invitation, :valid?
          assert_includes invitation.errors[:business], "cannot accept organizations with marketplace purchases without a valid payment method."
        end
      end

      test "business must have sufficient seats for the unique Organization members being added" do
        @business.update(seats: 1)
        perform_enqueued_jobs(only: [BusinessUpdateLicenseUsageJob, BusinessUserAccountCreateForOrganizationJob]) do
          @invite.accept(@org_admin)
          @invite.confirm(@admin)
        end
        second_org = create :business_plus_organization

        # Need to load a fresh business to avoid stale memoization
        invitation = BusinessOrganizationInvitation.new \
          business: Business.find(@business.id), invitee: second_org, inviter: @admin

        refute_predicate invitation, :valid?
        assert_includes \
          invitation.errors[:business],
          "needs 1 additional seat to add #{second_org.display_login}."
      end

      test "invitation is valid if there are sufficient seats on the business" do
        @business.update(seats: 3)
        @invite.accept(@org_admin)
        @invite.confirm(@admin)
        @business.reload # make it aware of new organization

        email = "invited@example.com"
        @org.invite(email: email, inviter: @org_admin)

        organization = create(:organization)
        organization.invite(email: email, inviter: organization.admins.first)

        invitation = BusinessOrganizationInvitation.new(business: @business, invitee: organization, inviter: @admin)

        assert_predicate invitation, :valid?
      end

      test "organization must not be having an outstanding balance" do
        @org.plan_subscription.update(balance_in_cents: 100)
        invitation = BusinessOrganizationInvitation.new \
          business: @business, invitee: @org, inviter: @admin

        refute_predicate invitation, :valid?
        assert_includes invitation.errors[:base],
          "Organization #{@org.display_login} cannot be invited because it has an outstanding balance."
      end

      test "invitations fails if the organization is in dunning" do
        @org.increment_billing_attempts
        assert @org.dunning?

        invitation = BusinessOrganizationInvitation.new \
          business: @business, invitee: @org, inviter: @admin

        refute_predicate invitation, :valid?
        assert_includes invitation.errors[:base],
          "Organization #{@org.display_login} cannot be invited because it is overdue for payment."
      end
    end

    context "#status" do
      test ":created is the initial status" do
        assert_equal :created, @invite.status
      end

      test "changes to :expired upon expiration" do
        @invite.expire
        assert_equal :expired, @invite.status
      end

      test "changes to :accepted upon acceptance by org admin" do
        @invite.accept(@org_admin)
        assert_equal :accepted, @invite.status
      end

      test "changes to :expired upon expiration (after acceptance)" do
        @invite.accept(@org_admin)
        @invite.expire
        assert_equal :expired, @invite.status
      end

      test "changes to :confirmed upon confirmation by business admin" do
        @invite.accept(@org_admin)
        @invite.confirm(@admin)
        assert_equal :confirmed, @invite.status
      end

      test "changes to :completed upon completion by sales-ops" do
        @invite.accept(@org_admin)
        @invite.confirm(@admin)
        @invite.complete(@staff)
        assert_equal :completed, @invite.status
        assert_equal @staff, @invite.completed_by
      end

      test "changes to :completed upon confirmation by business admin if org is on free plan" do
        free_org = create(:organization, plan: GitHub::Plan.free)
        invite = create :business_organization_invitation,
          business: @business, inviter: @admin, invitee: free_org
        invite.accept(free_org.admins.first)
        invite.confirm(@admin)
        assert_equal :completed, invite.status
        assert_nil invite.completed_by
      end

      test "changes to :completed upon confirmation by business admin if business is self serve" do
        @business.customer.update! billing_type: Customer::BILLING_TYPE_CARD
        @invite.accept(@org_admin)
        @invite.confirm(@admin)
        assert_equal :completed, @invite.status
        assert_nil @invite.completed_by
      end

      test "changes to :canceled upon cancelation by org admin" do
        @invite.cancel(@org_admin)
        assert_equal :canceled, @invite.status
      end

      test "changes to :canceled upon cancelation (before acceptance) by business admin" do
        @invite.cancel(@admin)
        assert_equal :canceled, @invite.status
      end

      test "changes to :canceled upon cancelation (after acceptance) by business admin" do
        @invite.accept(@org_admin)
        @invite.cancel(@admin)
        assert_equal :canceled, @invite.status
      end
    end

    context "#recently_expired" do
      test "includes unaccepted invitations that expired within the cutoff" do
        invitation = Timecop.travel((BusinessOrganizationInvitation::INVITATION_EXPIRY_PERIOD + 1).days.ago) do
          create :business_organization_invitation, business: @business
        end
        assert_same_elements [invitation], BusinessOrganizationInvitation.recently_expired
      end

      test "does not include unaccepted invitations that expired before the cutoff" do
        invitation = Timecop.travel((BusinessOrganizationInvitation::INVITATION_EXPIRY_CUTOFF + 1).days.ago) do
          create :business_organization_invitation, business: @business
        end
        assert_empty BusinessOrganizationInvitation.recently_expired
      end

      test "includes accepted invitations that expired within the cutoff" do
        org = create :business_plus_organization
        invitation = create :business_organization_invitation, business: @business, invitee: org
        created_at = (BusinessOrganizationInvitation::INVITATION_EXPIRY_PERIOD + 10).days.ago
        invitation.update_columns created_at: created_at, updated_at: created_at
        Timecop.travel((BusinessOrganizationInvitation::INVITATION_EXPIRY_PERIOD + 1).days.ago) do
          invitation.accept(org.admins.first)
        end

        assert_same_elements [invitation], BusinessOrganizationInvitation.recently_expired
      end

      test "does not include accepted invitations that expired before the cutoff" do
        org = create :business_plus_organization
        invitation = create :business_organization_invitation, business: @business, invitee: org
        created_at = (BusinessOrganizationInvitation::INVITATION_EXPIRY_PERIOD + 10).days.ago
        invitation.update_columns created_at: created_at, updated_at: created_at
        Timecop.travel((BusinessOrganizationInvitation::INVITATION_EXPIRY_CUTOFF + 1).days.ago) do
          invitation.accept(org.admins.first)
        end

        assert_empty BusinessOrganizationInvitation.recently_expired
      end

      test "includes both unaccepted and accepted invitations that expired within the cutoff" do
        # Invitation that was not accepted before cutoff
        invitation_one = Timecop.travel((BusinessOrganizationInvitation::INVITATION_EXPIRY_PERIOD + 1).days.ago) do
          create :business_organization_invitation, business: @business
        end

        # Accepted invitation that was not confirmed before cutoff
        org = create :business_plus_organization
        invitation_two = create :business_organization_invitation, business: @business, invitee: org
        created_at = (BusinessOrganizationInvitation::INVITATION_EXPIRY_PERIOD + 10).days.ago
        invitation_two.update_columns created_at: created_at, updated_at: created_at
        Timecop.travel((BusinessOrganizationInvitation::INVITATION_EXPIRY_PERIOD + 1).days.ago) do
          invitation_two.accept(org.admins.first)
        end

        assert_same_elements \
          [invitation_one, invitation_two],
          BusinessOrganizationInvitation.recently_expired
      end
    end

    context "#redundant_invitations" do
      test "does not include invitations whose status is created" do
        assert_equal :created, @invite.status
        assert_empty BusinessOrganizationInvitation.redundant_invitations
      end

      test "does not include invitations whose status is accepted" do
        @invite.accept(@org_admin)

        assert_equal :accepted, @invite.reload.status
        assert_empty BusinessOrganizationInvitation.redundant_invitations
      end

      test "does not include invitations whose status is confirmed" do
        @invite.accept(@org_admin)
        @invite.confirm(@admin)

        assert_equal :confirmed, @invite.reload.status
        assert_empty BusinessOrganizationInvitation.redundant_invitations
      end

      test "does not include invitations whose status is completed" do
        @invite.accept(@org_admin)
        @invite.confirm(@admin)
        @invite.complete(@staff)

        assert_equal :completed, @invite.reload.status
        assert_empty BusinessOrganizationInvitation.redundant_invitations
      end

      test "includes invitations canceled earlier than the cutoff time" do
        Timecop.travel(@redundant_invitation_time) do
          @invite.cancel(@org_admin)
        end

        @invite.reload

        assert_equal :canceled, @invite.status
        assert_same_elements [@invite], BusinessOrganizationInvitation.redundant_invitations
      end

      test "does not include invitations canceled later than the cutoff time" do
        Timecop.travel(@non_redundant_invitation_time) do
          @invite.cancel(@org_admin)
        end

        assert_equal :canceled, @invite.status
        assert_empty BusinessOrganizationInvitation.redundant_invitations
      end

      test "includes invitations expired earlier than the cutoff time" do
        Timecop.travel(@redundant_invitation_time) do
          @invite.expire
        end

        @invite.reload

        assert_equal :expired, @invite.status
        assert_same_elements [@invite], BusinessOrganizationInvitation.redundant_invitations
      end

      test "does not include invitations expired later than the cutoff time" do
        Timecop.travel(@non_redundant_invitation_time) do
          @invite.expire
        end

        assert_equal :expired, @invite.status
        assert_empty BusinessOrganizationInvitation.redundant_invitations
      end
    end

    context "#accept" do
      test "fails if expired" do
        @invite.expire
        assert_raises BusinessOrganizationInvitation::ExpiredError do
          @invite.accept(@org_admin)
        end
      end

      test "fails if already accepted" do
        @invite.accept(@org_admin)
        assert_raises BusinessOrganizationInvitation::AlreadyAcceptedError do
          @invite.accept(@org_admin)
        end
      end

      test "fails if canceled" do
        @invite.cancel(@admin)
        assert_raises BusinessOrganizationInvitation::CanceledError do
          @invite.accept(@org_admin)
        end
      end

      test "fails if confirmed" do
        @invite.accept(@org_admin)
        @invite.confirm(@admin)
        assert_raises BusinessOrganizationInvitation::AlreadyConfirmedError do
          @invite.accept(@org_admin)
        end
      end

      test "fails if organization has been made part of a business already" do
        @business.add_organization(@org)
        assert_raises BusinessOrganizationInvitation::AlreadyBusinessMemberError do
          @invite.reload.accept(@org_admin)
        end
      end

      test "fails if acceptor isn't admin of organization" do
        assert_raises BusinessOrganizationInvitation::InvalidActorError do
          @invite.accept(@admin)
        end
      end

      test "fails if organization has an upgrade to business in progress" do
        business = create :business
        @org.upgrade_to_enterprise_in_progress!(business)
        assert_raises BusinessOrganizationInvitation::OrganizationUpgradeToBusinessInProgressError do
          @invite.reload.accept(@org_admin)
        end
      end

      test "works if business is not self-serve" do
        @business.update(can_self_serve: false)
        @invite.accept(@org_admin)
        assert_predicate @invite, :accepted?
      end

      test "works if organization has since become invoiced" do
        @org.update(billing_type: :invoice)
        @invite.accept(@org_admin)
        assert_predicate @invite, :accepted?
      end

      test "fails if the business' available seats is now insufficient for the Organization's unique additional members" do
        @business.update(seats: 0)

        assert_raises BusinessOrganizationInvitation::InsufficientAvailableSeatsError do
          @invite.accept(@org_admin)
        end
      end

      test "works if the business is metered, even with no available seats" do
        @business.customer.metered_plan = true
        @business.update(seats: 0)
        @invite.accept(@org_admin)
        assert_predicate @invite, :accepted?
      end

      test "fails if organization has an outstanding balance" do
        @org.plan_subscription.update(balance_in_cents: 100)
        assert_raises BusinessOrganizationInvitation::OrganizationHasOutstandingBalanceError do
          @invite.reload.accept(@org_admin)
        end
      end

      test "fails if organization is in dunning" do
        @org.increment_billing_attempts
        assert_raises BusinessOrganizationInvitation::OrganizationIsInDunningError do
          @invite.reload.accept(@org_admin)
        end
      end

      test "clears last_reminded_at value" do
        @invite.set_last_reminded_at(2.days.ago)
        refute_nil @invite.last_reminded_at

        @invite.accept(@org_admin)
        assert_predicate @invite, :accepted?
        assert_nil @invite.last_reminded_at
      end

      test "creates an audit log entry" do
        events = subscribe("org.accept_business_invitation")
        @invite.accept(@org_admin)

        assert_predicate @invite, :accepted?
        assert_equal 1, events.size
        event = events.first
        assert_equal @org_admin.id, event.payload[:actor_id]
        assert_equal @org.id, event.payload[:org_id]
        assert_equal @business.id, event.payload[:business_id]
      end
    end

    context "#confirm" do
      test "fails if expired" do
        @invite.expire
        assert_raises BusinessOrganizationInvitation::ExpiredError do
          @invite.confirm(@admin)
        end
      end

      if GitHub.spamminess_check_enabled?
        test "fails if Business is spammy" do
          @business.mark_as_spammy
          assert_predicate @business, :spammy?

          assert_raises BusinessOrganizationInvitation::BusinessIsSpammyError do
            @invite.confirm(@admin)
          end
        end
      end

      test "fails if not accepted" do
        assert_raises BusinessOrganizationInvitation::NotYetAcceptedError do
          @invite.confirm(@admin)
        end
      end

      test "fails if already confirmed" do
        @invite.accept(@org_admin)
        @invite.confirm(@admin)
        assert_raises BusinessOrganizationInvitation::AlreadyConfirmedError do
          @invite.confirm(@admin)
        end
      end

      test "fails if canceled" do
        @invite.cancel(@org_admin)
        assert_raises BusinessOrganizationInvitation::CanceledError do
          @invite.confirm(@admin)
        end
      end

      test "fails if organization has been made part of a business already" do
        @invite.accept(@org_admin)
        @business.add_organization(@org)
        assert_raises BusinessOrganizationInvitation::AlreadyBusinessMemberError do
          @invite.reload.confirm(@admin)
        end
      end

      test "fails if acceptor isn't admin of business" do
        @invite.accept(@org_admin)
        assert_raises BusinessOrganizationInvitation::InvalidActorError do
          @invite.confirm(@org_admin)
        end
      end

      test "fails if organization has an upgrade to business in progress" do
        @invite.accept(@org_admin)
        business = create :business
        @org.upgrade_to_enterprise_in_progress!(business)
        assert_raises BusinessOrganizationInvitation::OrganizationUpgradeToBusinessInProgressError do
          @invite.reload.confirm(@admin)
        end
      end

      test "works if business is not self-serve" do
        @invite.accept(@org_admin)
        @business.update(can_self_serve: false)
        @invite.confirm(@admin)
        assert_predicate @invite, :confirmed?
      end

      test "works if organization is invoiced" do
        @invite.accept(@org_admin)
        @org.update(billing_type: :invoice)
        @invite.reload.confirm(@admin)
        assert_predicate @invite, :confirmed?
      end

      test "fails if the business now has insufficient seats for the Organization's additional members" do
        @invite.accept(@org_admin)
        @business.update(seats: 0)
        @invite = BusinessOrganizationInvitation.find(@invite.id) # clear memoization, etc.

        assert_raises BusinessOrganizationInvitation::InsufficientAvailableSeatsError do
          @invite.confirm(@admin)
        end
      end

      test "works if the business is metered, regardless of seats field " do
        @invite.accept(@org_admin)

        @business.customer.metered_plan = true
        @business.update(seats: 0)
        @invite = BusinessOrganizationInvitation.find(@invite.id) # clear memoization, etc.
        @invite.confirm(@admin)
        assert_predicate @invite, :confirmed?
      end

      test "fails if organization has an outstanding balance" do
        @invite.accept(@org_admin)
        @org.plan_subscription.update(balance_in_cents: 100)
        assert_raises BusinessOrganizationInvitation::OrganizationHasOutstandingBalanceError do
          @invite.reload.confirm(@admin)
        end
      end

      test "fails if organization is in dunning" do
        @invite.accept(@org_admin)
        @org.increment_billing_attempts
        assert @org.dunning?
        assert_raises BusinessOrganizationInvitation::OrganizationIsInDunningError do
          @invite.reload.confirm(@admin)
        end
      end

      test "sets invitee billing type to card for self-serve paying organization" do
        assert_equal User::BillingDependency::CARD_BILLING_TYPE, @org.billing_type
        @invite.accept(@org_admin)
        @invite.confirm(@admin)
        assert_equal User::BillingDependency::CARD_BILLING_TYPE, @invite.reload.invitee_billing_type
      end

      test "sets invitee billing type to invoice for invoiced organization" do
        @org.switch_billing_type_to_invoice(@admin)
        assert_equal User::BillingDependency::INVOICE_BILLING_TYPE, @org.reload.billing_type
        @invite.accept(@org_admin)
        @invite.confirm(@admin)
        assert_equal User::BillingDependency::INVOICE_BILLING_TYPE, @invite.reload.invitee_billing_type
      end

      test "sets organization's plan to business plus if business not on trial" do
        @invite.accept(@org_admin)
        @invite.confirm(@admin)
        refute_predicate @business, :trial?
        assert_equal @org.reload.plan.name.to_sym, :business_plus
      end

      test "does not set organization's plan to business plus if business on trial" do
        @business.update_attribute(:trial_expires_at, 2.weeks.from_now)
        org = create :business_organization, admins: [@org_admin]
        invite = create :business_organization_invitation,
          business: @business, inviter: @admin, invitee: org
        invite.accept(@org_admin)
        invite.confirm(@admin)
        assert_predicate @business.reload, :trial?
        assert_equal org.reload.read_attribute_before_type_cast(:plan).to_sym, :business
      end

      test "suspends organization billing if business on trial" do
        @business.update_attribute(:trial_expires_at, 2.weeks.from_now)
        org = create(:credit_card_org, admin: @org_admin)
        plan_subscription = create(:billing_plan_subscription, user: org)
        invite = create :business_organization_invitation,
          business: @business, inviter: @admin, invitee: org
        invite.accept(@org_admin)
        assert_enqueued_jobs 1, only: SuspendPlanSubscriptionJob do
          invite.confirm(@admin)
        end
      end

      test "makes organization a part of business" do
        @invite.accept(@org_admin)
        @invite.confirm(@admin)
        assert_equal @org.reload.business, @business
      end

      test "revokes organization's active coupon" do
        coupon = create(:coupon, discount: "$5")
        @org.redeem_coupon(coupon)

        @invite.accept(@org_admin)
        @invite.confirm(@admin)
        assert_empty @org.reload.coupon_redemptions
      end

      test "sends an email when the organization's coupon is removed" do
        coupon = create(:coupon, discount: "$5")
        @org.redeem_coupon(coupon)
        @invite.accept(@org_admin)

        assert_difference "ActionMailer::Base.deliveries.count", 1 do
          assert_performed_email(mailer: "BillingNotificationsMailer", action: "coupon_removed_from_enterprise_owned_organization", args: [@org, @business]) do
            @invite.confirm(@admin)
          end
        end

        assert_empty @org.reload.coupon_redemptions
      end

      test "does not send an email if there was no coupon attached to the organization" do
        assert_empty @org.reload.coupon_redemptions
        @invite.accept(@org_admin)

        BillingNotificationsMailer.expects(:coupon_removed_from_enterprise_owned_organization).never
        assert_difference "ActionMailer::Base.deliveries.count", 0 do
          @invite.confirm(@admin)
        end

        assert_empty @org.reload.coupon_redemptions
      end

      test "instruments org.confirm_business_invitation event" do
        @invite.accept(@org_admin)
        events = subscribe "org.confirm_business_invitation"

        @invite.confirm(@admin)

        expected_payload = {
          org: @org.login,
          org_id: @org.id,
          actor: @admin.login,
          actor_id: @admin.id,
          business: @business.slug,
          business_id: @business.id,
          invitation_id: @invite.id,
        }
        assert event = events.pop, "org.confirm_business_invitation event was expected"
        assert events.empty?
        assert_equal expected_payload, event.payload
      end

      test "enqueues the enterprise cloud trial check job to display the trial banner" do
        @invite.accept(@org_admin)

        assert_enqueued_with(job: Billing::EnterpriseCloudTrialCheckJob, args: [@org.id], queue: "billing") do
          @invite.confirm(@admin)
        end
      end

      context "orgs with marketplace apps invited to self-serve enterprise" do
        test "creates new identical subscription items for org against enterprise account" do
          ano_listing_plan = create :marketplace_listing_plan, :verified_listing
          @business.enable_self_serve_payments
          qty = 99
          org_subscription_item = create :billing_subscription_item, plan_subscription: @org_plan_subscription,
            subscribable: @listing_plan, quantity: qty

          cancelled_org_subscription_item = create :billing_subscription_item, plan_subscription: @org_plan_subscription,
            subscribable: ano_listing_plan, quantity: 0

          assert_equal 0, @business.subscription_items.count

          @invite.accept(@org_admin)
          @invite.confirm(@admin)

          assert_predicate @invite, :confirmed?
          assert_equal 2, @business.subscription_items.count

          business_subscription_item = @business.subscription_items.find { |si| si.quantity == qty }
          cancelled_business_subscription_item = @business.subscription_items.find { |si| si.quantity == 0 }

          assert_equal org_subscription_item.subscribable, business_subscription_item.subscribable
          assert_equal qty, business_subscription_item.quantity

          assert_equal cancelled_org_subscription_item.subscribable, cancelled_business_subscription_item.subscribable

          org_subscription_item.reload
          assert_predicate org_subscription_item.quantity, :zero?
          assert_equal @org.id, business_subscription_item.organization_id
          assert_equal @org.id, cancelled_business_subscription_item.organization_id
        end

        test "sets trial end date to original trial date if app still in trial at time of transfer" do
          @business.enable_self_serve_payments

          org_pending_plan_change = create(:billing_pending_plan_change,
            plan: nil,
            plan_duration: nil,
            seats: nil,
            user: @org,
            active_on: 1.week.from_now
          )
          org_subscription_item = create(:billing_subscription_item,
            plan_subscription: @org_plan_subscription,
            subscribable: @listing_plan,
            free_trial_ends_on: 1.week.from_now
          )
          pending_subscription_item_change = create(:billing_pending_subscription_item_change,
            free_trial: true,
            subscribable: @listing_plan,
            pending_plan_change: org_pending_plan_change,
          )

          assert_equal 0, @business.subscription_items.count

          @invite.accept(@org_admin)
          @invite.confirm(@admin)

          assert_predicate @invite, :confirmed?
          assert_equal 1, @business.subscription_items.count
          assert_equal 0, @org.active_marketplace_listing_subscription_items.count

          business_subscription_item = @business.subscription_items.last
          assert_equal org_subscription_item.free_trial_ends_on, business_subscription_item.free_trial_ends_on
          assert business_subscription_item.has_pending_cycle_change?
          refute org_subscription_item.has_pending_cycle_change?
          assert_nil business_subscription_item.pending_subscription_item_change.user
          assert_equal @business.customer, business_subscription_item.pending_subscription_item_change.customer
          assert_equal @org, business_subscription_item.pending_subscription_item_change.organization
        end

        test "transfers pending cancellation and ensure doesn't apply to other orgs with same plan" do
          @business.enable_self_serve_payments

          existing_ea_org = create :organization, business: @business, admin: @business.owners.first
          existing_ea_org_subscription_item = create(:billing_subscription_item,
            quantity: 2,
            plan_subscription: @business_plan_subscription,
            subscribable: @listing_plan,
            organization: existing_ea_org
          )

          org_pending_cancellation = create(:billing_pending_plan_change,
            plan: nil,
            plan_duration: nil,
            seats: 0,
            user: @org,
            active_on: 1.week.from_now
          )
          org_subscription_item = create(:billing_subscription_item,
            quantity: 99,
            plan_subscription: @org_plan_subscription,
            subscribable: @listing_plan,
          )
          pending_subscription_item_change = create(:billing_pending_subscription_item_change,
            quantity: 0,
            subscribable: @listing_plan,
            pending_plan_change: org_pending_cancellation,
          )

          assert_equal 1, @business.subscription_items.count

          @invite.accept(@org_admin)
          @invite.confirm(@admin)

          assert_predicate @invite, :confirmed?
          assert_equal 2, @business.subscription_items.count
          assert_equal 0, @org.active_marketplace_listing_subscription_items.count
          refute org_subscription_item.has_pending_cycle_change?

          assert transferred = @business.subscription_items.for_organization(@org).first
          assert existing = @business.subscription_items.for_organization(existing_ea_org).first

          assert transferred.pending_subscription_item_change.present?
          assert transferred.pending_cancellation?
          assert_nil transferred.pending_subscription_item_change.user
          assert_equal @business.customer, transferred.pending_subscription_item_change.customer
          assert_equal @org, transferred.pending_subscription_item_change.organization

          refute existing.pending_subscription_item_change.present?
          refute existing.pending_cancellation?
        end

        test "does not create new subscription item if business is not self-serve" do
          org_subscription_item = create :billing_subscription_item, plan_subscription: @org_plan_subscription, subscribable: @listing_plan

          assert_equal 0, @business.subscription_items.count

          @invite.accept(@org_admin)
          @invite.confirm(@admin)

          assert_predicate @invite, :confirmed?
          assert_equal 0, @business.subscription_items.count
        end
      end
    end

    context "#cancel" do
      test "fails if expired" do
        @invite.expire
        assert_raises BusinessOrganizationInvitation::ExpiredError do
          @invite.cancel(@admin)
        end
      end

      test "fails if not business owner or org admin" do
        rando = create :user
        assert_raises BusinessOrganizationInvitation::InvalidActorError do
          @invite.cancel(rando)
        end
      end

      test "fails if confirmed" do
        @invite.accept(@org_admin)
        @invite.confirm(@admin)
        assert_raises BusinessOrganizationInvitation::AlreadyConfirmedError do
          @invite.cancel(@admin)
        end
      end

      test "fails if canceled" do
        @invite.cancel(@org_admin)
        assert_raises BusinessOrganizationInvitation::CanceledError do
          @invite.cancel(@admin)
        end
      end

      test "succeeds if business admin" do
        @invite.cancel(@admin)
        assert @invite.canceled?
      end

      test "succeeds if org admin" do
        @invite.cancel(@org_admin)
        assert @invite.canceled?
      end

      test "succeeds if accepted" do
        @invite.accept(@org_admin)
        @invite.cancel(@admin)
        assert @invite.canceled?
      end

      test "supports providing initiated_from as enterprise" do
        @invite.cancel(@admin, "enterprise")
        assert @invite.canceled?
      end

      test "supports providing initiated_from as organization" do
        @invite.cancel(@org_admin, "organization")
        assert @invite.canceled?
      end

      test "raises ArgumentError when initiated_from is non nil but not a valid value" do
        assert_raises ArgumentError do
          @invite.cancel(@admin, "whatever")
        end
      end

      test "creates an audit log entry" do
        events = subscribe("org.cancel_business_invitation")
        @invite.cancel(@org_admin)

        assert_equal 1, events.size
        event = events.first
        assert_equal @org_admin.id, event.payload[:actor_id]
        assert_equal @org.id, event.payload[:org_id]
        assert_equal @business.id, event.payload[:business_id]
      end

      test "creates an audit log entry that includes initiated_from when provided" do
        events = subscribe("org.cancel_business_invitation")
        @invite.cancel(@org_admin, "enterprise")

        assert_equal 1, events.size
        event = events.first
        assert_equal @org_admin.id, event.payload[:actor_id]
        assert_equal @org.id, event.payload[:org_id]
        assert_equal @business.id, event.payload[:business_id]
        assert_equal "enterprise", event.payload[:initiated_from]
      end
    end

    context "#expire" do
      test "sets expired_at" do
        assert_nil @invite.expired_at
        refute_predicate @invite, :expired?

        @invite.expire

        refute_nil @invite.expired_at
        assert_predicate @invite, :expired?
      end
    end

    context "#send_invitation_email" do
      test "sends invitation email when created" do
        perform_enqueued_jobs(only: [ApplicationDeliveryJob]) do
          assert_difference "deliveries.size", 1 do
            BusinessOrganizationInvitation.create!(business: @business, inviter: @admin, invitee: @uninvited_org)
          end
        end
      end

      test "does not send invitation if inviter is spammy" do
        @admin.spammy = true

        assert_no_difference "deliveries.size" do
          BusinessOrganizationInvitation.create!(business: @business, inviter: @admin, invitee: @uninvited_org)
        end
      end
    end

    context "#needed_seat_count" do
      test "returns the number of seats needed by the invited organization" do
        @business.update(seats: 2)

        email = "invited@example.com"

        existing_org = create(:organization, business: @business)
        existing_org.invite(email: email, inviter: existing_org.admins.first)
        @business.reload # make it aware of new organization

        @org.invite(email: email, inviter: @org_admin)

        # We just require a new seat for @org_admin since the invited email is already associated with @business
        assert_equal 1, @invite.needed_seat_count
      end
    end

    context "#needs_reminder?" do
      test "returns false for invitations created less than 3 days ago without a reminder sent yet" do
        invitation = create :business_organization_invitation, business: @business
        refute_predicate invitation, :needs_reminder?
      end

      test "returns true for invitations created more than 3 days ago without a reminder sent yet" do
        invitation = Timecop.travel((BusinessOrganizationInvitation::INVITATION_REMINDER_PERIOD + 1).days.ago) do
          create :business_organization_invitation, business: @business
        end
        assert_predicate invitation, :needs_reminder?
      end

      test "returns false for invitations created more than 3 days ago with a reminder sent less than 3 days ago" do
        invitation = Timecop.travel((BusinessOrganizationInvitation::INVITATION_REMINDER_PERIOD * 2).days.ago) do
          create :business_organization_invitation, business: @business
        end

        Timecop.travel((BusinessOrganizationInvitation::INVITATION_REMINDER_PERIOD - 1).days.ago) do
          invitation.set_last_reminded_at(DateTime.now)
        end

        refute_predicate invitation, :needs_reminder?
      end

      test "returns true for invitations created more than 3 days ago with a reminder sent more than 3 days ago" do
        invitation = Timecop.travel((BusinessOrganizationInvitation::INVITATION_REMINDER_PERIOD * 2).days.ago) do
          create :business_organization_invitation, business: @business
        end

        Timecop.travel((BusinessOrganizationInvitation::INVITATION_REMINDER_PERIOD + 1).days.ago) do
          invitation.set_last_reminded_at(DateTime.now)
        end

        assert_predicate invitation, :needs_reminder?
      end

      test "returns false for invitations accepted less than 3 days ago without a reminder sent yet" do
        invitation = create :business_organization_invitation, business: @business
        invitation.accept(invitation.invitee.admins.first)
        refute_predicate invitation, :needs_reminder?
      end

      test "returns true for invitations accepted more than 3 days ago without a reminder sent yet" do
        invitation = Timecop.travel((BusinessOrganizationInvitation::INVITATION_REMINDER_PERIOD + 1).days.ago) do
          i = create :business_organization_invitation, business: @business
          i.accept(i.invitee.admins.first)
          i
        end
        assert_predicate invitation, :needs_reminder?
      end

      test "returns false for invitations accepted more than 3 days ago with a reminder sent less than 3 days ago" do
        invitation = Timecop.travel((BusinessOrganizationInvitation::INVITATION_REMINDER_PERIOD * 2).days.ago) do
          i = create :business_organization_invitation, business: @business
          i.accept(i.invitee.admins.first)
          i
        end

        Timecop.travel((BusinessOrganizationInvitation::INVITATION_REMINDER_PERIOD - 1).days.ago) do
          invitation.set_last_reminded_at(DateTime.now)
        end

        refute_predicate invitation, :needs_reminder?
      end

      test "returns true for invitations accepted more than 3 days ago with a reminder sent more than 3 days ago" do
        invitation = Timecop.travel((BusinessOrganizationInvitation::INVITATION_REMINDER_PERIOD * 2).days.ago) do
          i = create :business_organization_invitation, business: @business
          i.accept(i.invitee.admins.first)
          i
        end

        Timecop.travel((BusinessOrganizationInvitation::INVITATION_REMINDER_PERIOD + 1).days.ago) do
          invitation.set_last_reminded_at(DateTime.now)
        end

        assert_predicate invitation, :needs_reminder?
      end
    end

    context "#send_expiration_reminder" do
      test "does nothing for confirmed invitations" do
        invitation = create :business_organization_invitation, business: @business
        invitation.accept(invitation.invitee.admins.first)
        invitation.confirm(@business.owners.first)

        BusinessMailer.expects(:organization_invitation_pending_acceptance_reminder).never

        invitation.send_expiration_reminder
      end

      test "does nothing for cancelled invitations" do
        invitation = create :business_organization_invitation, business: @business
        invitation.cancel(invitation.invitee.admins.first)

        BusinessMailer.expects(:organization_invitation_pending_acceptance_reminder).never

        invitation.send_expiration_reminder
      end

      test "does nothing for expired invitations" do
        invitation = create :business_organization_invitation, business: @business
        invitation.expire

        BusinessMailer.expects(:organization_invitation_pending_acceptance_reminder).never

        invitation.send_expiration_reminder
      end

      test "queues email delivery to org for invitation that has not been accepted" do
        invitation = create :business_organization_invitation, business: @business

        BusinessMailer.expects(:organization_invitation_pending_acceptance_reminder).once.with(
          invitation
        ).returns(stub(deliver_later: nil))

        invitation.send_expiration_reminder
        refute_nil invitation.last_reminded_at
      end

      test "queues email delivery to enterprise for invitation that has not been confirmed" do
        invitation = create :business_organization_invitation, business: @business
        invitation.accept(invitation.invitee.admins.first)

        BusinessMailer.expects(:organization_invitation_pending_confirmation_reminder).once.with(
          invitation
        ).returns(stub(deliver_later: nil))

        invitation.send_expiration_reminder
        refute_nil invitation.last_reminded_at
      end

      test "does nothing if business has been soft-deleted" do
        invitation = create :business_organization_invitation, business: @business
        invitation.accept(invitation.invitee.admins.first)
        @business.soft_delete!

        BusinessMailer.expects(:organization_invitation_pending_confirmation_reminder).never

        invitation.reload.send_expiration_reminder
      end

      test "does nothing if business is flagged spammy" do
        invitation = create :business_organization_invitation, business: @business
        invitation.accept(invitation.invitee.admins.first)
        @business.mark_as_spammy
        assert_predicate @business, :spammy?

        BusinessMailer.expects(:organization_invitation_pending_confirmation_reminder).never

        invitation.reload.send_expiration_reminder
      end

      test "does nothing if business is suspended" do
        invitation = create :business_organization_invitation, business: @business
        invitation.accept(invitation.invitee.admins.first)
        @business.suspend("Reasons")
        assert_predicate @business, :suspended?

        BusinessMailer.expects(:organization_invitation_pending_confirmation_reminder).never

        invitation.reload.send_expiration_reminder
      end
    end

    context "#until_expiry_in_words" do
      test "returns nil for confirmed invitations" do
        invitation = create :business_organization_invitation, business: @business
        invitation.accept(invitation.invitee.admins.first)
        invitation.confirm(@business.owners.first)

        assert_nil invitation.until_expiry_in_words
      end

      test "returns nil for cancelled invitations" do
        invitation = create :business_organization_invitation, business: @business
        invitation.cancel(invitation.invitee.admins.first)

        assert_nil invitation.until_expiry_in_words
      end

      test "returns nil for expired invitations" do
        invitation = create :business_organization_invitation, business: @business
        invitation.expire

        assert_nil invitation.until_expiry_in_words
      end

      test "returns correctly for created invitations" do
        invitation = Timecop.travel((BusinessOrganizationInvitation::INVITATION_EXPIRY_PERIOD - 10).days.ago) do
          create :business_organization_invitation, business: @business
        end

        assert_equal "10 days", invitation.until_expiry_in_words
      end

      test "returns correctly for accepted invitations" do
        invitation = Timecop.travel((BusinessOrganizationInvitation::INVITATION_EXPIRY_PERIOD - 10).days.ago) do
          i = create :business_organization_invitation, business: @business
          i.accept(i.invitee.admins.first)
          i
        end

        assert_equal "10 days", invitation.until_expiry_in_words
      end
    end

    context "#last_reminded_at" do
      test "returns nil when reminder has not been sent" do
        invitation = create :business_organization_invitation, business: @business
        assert_nil invitation.last_reminded_at
      end

      test "returns DateTime when reminder has been sent" do
        invitation = create :business_organization_invitation, business: @business
        invitation.send_expiration_reminder

        last_reminded_at = invitation.last_reminded_at
        refute_nil last_reminded_at
        assert last_reminded_at.is_a?(DateTime)
      end
    end

    context "#set_last_reminded_at" do
      test "when last_reminded_at is nil does not fail when attempting to delete value in GitHub::KV" do
        invitation = create :business_organization_invitation, business: @business

        invitation.set_last_reminded_at(nil)

        assert_nil invitation.last_reminded_at
      end

      test "when last_reminded_at is nil deletes the value in GitHub::KV" do
        invitation = create :business_organization_invitation, business: @business
        now = DateTime.current
        invitation.set_last_reminded_at(now)
        refute_nil invitation.last_reminded_at

        invitation.set_last_reminded_at(nil)

        assert_nil invitation.last_reminded_at
      end

      test "when last_reminded_at is a DateTime, converts it to String and stores value in GitHub::KV" do
        invitation = create :business_organization_invitation, business: @business
        now = DateTime.current

        invitation.set_last_reminded_at(now)

        assert_equal \
          now.to_s,
          EnterpriseAccounts::KV.store.get("business_organization_invitations/last_reminded/#{invitation.id}").value { nil }
        last_reminded_at = invitation.last_reminded_at
        refute_nil last_reminded_at
        assert last_reminded_at.is_a?(DateTime)
      end
    end
  end
end
