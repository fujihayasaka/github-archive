# typed: true
# frozen_string_literal: true

require "test_helper"

class OrganizationTradeScreeningDependencyTest < GitHub::TestCase

  fixtures do
    @admin = create(:user, :with_trade_screening_record)
    @organization = create(:organization, :trade_unrestricted, admin: @admin)
    @staffer = create :user, login: "staffer", site_admin: true

    create_list(:private_repository, 2, owner: @organization)
    create_list(:repository, 2, owner: @organization)
  end

  context "#sdn_suspend" do
    %w[old_method new_method].each do |method|
      test "an org can be suspended using the #{method}" do
        reason = "Organization was suspended by staff"

        is_new_method = method == "new_method"
        enable_feature_flag(:sdn_organization_suspension_v3, @organization) if is_new_method
        disable_feature_flag(:sdn_organization_suspension_v3, @organization) if !is_new_method
        @organization.sdn_suspend(staff_user: @staffer, reason: reason)

        # Assertions to check org suspension worked
        assert_equal @organization.spammy?, false
        @organization.repositories.each do |repository|
          if repository.private?
            assert_predicate repository, :locked_on_trade_restriction? if is_new_method
            refute_predicate repository, :locked? if !is_new_method
            assert repository.disabled?(viewer: @admin) if !is_new_method
          else
            assert_predicate repository, :archived?
          end
        end

        unless is_new_method
          restriction = @organization.trade_controls_restriction
          assert_predicate restriction, :persisted?
          assert_predicate restriction, :full?
        end

        assert_predicate @organization.trade_screening_record, :true_match?
        assert_predicate @organization, :suspended?
        assert_predicate @organization, :sdn_suspended?
        assert_predicate @organization, :legal_hold?
      end
    end

    test "unlinks linked screening record from org on SDN suspension" do
      reason = "Organization was suspended by staff"
      @admin.link_trade_screening_record_to_org(organization: @organization)

      @organization.sdn_suspend(staff_user: @staffer, reason: reason)
      refute_predicate @organization, :has_linked_trade_screening_record?
    end

    test "adds staff note to the org on SDN suspension" do
      reason = "Organization was suspended by staff"

      @organization.sdn_suspend(staff_user: @staffer, reason: reason)

      assert @organization.staff_notes.any?
      assert_equal "DO NOT MODIFY THIS ACCOUNT WITHOUT APPROVAL FROM TRADE SUPPORT/CELA. Organization was suspended by staff", @organization.staff_notes.last.body
    end

    test "it doesn't send a trade restriction enforcement email" do
      reason = "Organization was suspended by staff"

      Organization.any_instance.expects(:send_trade_controls_enforcement_email).never

      @organization.sdn_suspend(staff_user: @staffer, reason: reason)
    end

    test "an org with full trade restrictions can still be suspended" do
      org = create(:organization)
      repository = create(:repository, owner: org)
      org.trade_controls_restriction.full!

      reason = "Organization was suspended by staff"
      org.sdn_suspend(staff_user: @staffer, reason: reason)

      assert_equal org.spammy?, false
      org.repositories.each do |repository|
        refute_predicate repository, :locked?
        assert_predicate repository, :archived?
      end

      assert org.has_full_trade_restrictions?
      assert_predicate org.trade_screening_record, :true_match?
      assert_predicate org, :sdn_suspended?
      assert_predicate org, :legal_hold?
    end

    test "it raises error when no reason is provided" do
      exception = assert_raises TypeError  do
        @organization.sdn_suspend(staff_user: @staffer, reason: nil)
      end
      assert_includes exception.message, "Parameter 'reason': Expected type String, got type NilClass"
    end

    test "it raises error when reason is blank" do
      assert_raises_with_message Organization::OrganizationSuspensionError, "Reason is required!" do
        @organization.sdn_suspend(staff_user: @staffer, reason: "")
      end
    end
  end if GitHub.billing_enabled?

  context "#send_true_match_internal_notification" do
    test "sends true match email when the org has a true_match screening status" do
      # with the new experience, we no longer notify the Legal Support team
      skip if GitHub.flipper[:improved_controls_for_true_match].enabled?

      org = create(:account_screening_profile, :with_org, :no_hit).owner
      org.expects(:send_true_match_internal_notification).once

      org.trade_screening_record.true_match!
    end
  end if GitHub.billing_enabled?

  context "#sdn_unsuspend" do
    %w[old_method new_method].each do |method|
      test "org previously suspended using the old #{method} can be unsuspended by staff" do
        reason = "Testing unsuspension"
        is_new_method = method == "new_method"
        enable_feature_flag(:sdn_organization_suspension_v3, @organization) if is_new_method
        disable_feature_flag(:sdn_organization_suspension_v3, @organization) if !is_new_method
        @organization.sdn_suspend(staff_user: @staffer, reason: reason)

        @organization.reload
        @organization.repositories.each do |repository|
          if repository.private?
            assert_predicate repository, :locked_on_trade_restriction? if is_new_method
            refute_predicate repository, :locked? if !is_new_method
            assert repository.disabled?(viewer: @admin) if !is_new_method
          else
            assert_predicate repository, :archived?
          end
        end

        assert_predicate @organization.trade_screening_record, :true_match?
        assert_predicate @organization, :sdn_suspended?
        assert_predicate @organization, :legal_hold?
        refute_predicate @organization, :spammy?

        @organization.sdn_unsuspend(staff_user: @staffer, reason: reason)

        # Assertions to check org un-suspension worked
        @organization.reload
        @organization.repositories.each do |repository|
          if repository.private?
            refute_predicate repository, :locked_on_trade_restriction? if is_new_method
            refute_predicate repository, :locked? if !is_new_method
            refute repository.disabled?(viewer: @admin)
          else
            refute_predicate repository, :archived?
          end
        end

        unless is_new_method
          assert_predicate @organization.trade_controls_restriction, :unrestricted?
        end

        refute_predicate @organization, :spammy?
        assert_predicate @organization.trade_screening_record, :no_hit?
        refute_predicate @organization, :suspended?
        refute_predicate @organization, :sdn_suspended?
        refute_predicate @organization, :legal_hold?
        assert_predicate @organization.staff_notes, :any?
        assert_equal reason, @organization.staff_notes.last.body
      end
    end

    test "unlinks linked screening record from org on SDN unsuspension" do
      reason = "Organization was suspended by staff"

      @admin.link_trade_screening_record_to_org(organization: @organization)
      @organization.sdn_unsuspend(staff_user: @staffer, reason: reason)

      refute_predicate @organization, :has_linked_trade_screening_record?
    end

    test "it raises error when no reason is provided" do
      exception = assert_raises TypeError  do
        @organization.sdn_unsuspend(staff_user: @staffer, reason: nil)
      end
      assert_includes exception.message, "Parameter 'reason': Expected type String, got type NilClass"
    end

    test "it raises error when reason is blank" do
      assert_raises_with_message Organization::OrganizationSuspensionError, "Reason is required!" do
        @organization.sdn_unsuspend(staff_user: @staffer, reason: "")
      end
    end
  end if GitHub.billing_enabled?
end
