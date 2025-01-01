# typed: true
# frozen_string_literal: true

require "test_helper"

class ScreeningRecordLinkManagerTest < GitHub::TestCase
  include DogstatsTestHelpers
  include GitHub::LoggerHelper

  setup do
    @user = create(:credit_card_user)
    @profile = create(:account_screening_profile, skip_contact_creation: true, owner: @user)
    @org = create(:organization, admin: @user)

    @user_with_contact = create(:credit_card_user)
    @contact = create(:billing_contact, customer: @user_with_contact.customer)
    @profile_with_contact = create(:account_screening_profile, owner: @user_with_contact)
    @org_with_contact = create(:organization, admin: @user_with_contact)
  end

  def link_manager
    TradeControls::ScreeningRecordLinkManager
  end

  context "#stos_org_trade_screening_record_exists?" do
    test "returns true if a linked profile exists after linking the billing contact" do
      assert @org_with_contact.trade_screening_record_link.update(id: @profile_with_contact.id)

      ActiveRecord::Base.connected_to(role: :reading) do
        assert link_manager.stos_org_trade_screening_record_exists?(org: @org_with_contact)
      end

      assert_predicate @org_with_contact.trade_screening_record_link.link_id, :present?
      assert_equal @org_with_contact.trade_screening_record_link.link_id, @profile_with_contact.id
      assert_predicate @org_with_contact.billing_contact_link.link_id, :present?
      assert_equal @org_with_contact.billing_contact_link.link_id, @contact.id
    end

    test "returns false if no profile is linked" do
      ActiveRecord::Base.connected_to(role: :reading) do
        refute link_manager.stos_org_trade_screening_record_exists?(org: @org)
      end

      refute_predicate @org.trade_screening_record_link.link_id, :present?
      refute_predicate @org.billing_contact_link.link_id, :present?
    end

    test "returns false if a deleted profile is linked" do
      assert @org.trade_screening_record_link.update(id: @profile.id)
      @profile.delete

      ActiveRecord::Base.connected_to(role: :reading) do
        refute link_manager.stos_org_trade_screening_record_exists?(org: @org)
      end

      assert_predicate @org.trade_screening_record_link.link_id, :present?
      refute_predicate AccountScreeningProfile.find_by(id: @org.trade_screening_record_link.link_id), :present?
      refute_predicate @org.billing_contact_link.link_id, :present?
    end
  end

  context "#stos_org_trade_screening_record" do
    test "returns the linked profile after linking the billing contact" do
      assert @org_with_contact.trade_screening_record_link.update(id: @profile_with_contact.id)
      refute_predicate @org_with_contact.billing_contact_link.link_id, :present?

      ActiveRecord::Base.connected_to(role: :reading) do
        assert_equal @profile_with_contact, link_manager.stos_org_trade_screening_record(org: @org_with_contact)
      end

      assert_predicate @org_with_contact.billing_contact_link.link_id, :present?
      assert_equal @org_with_contact.billing_contact_link.link_id, @contact.id
    end

    test "returns the profile if the org has its own profile" do
      profile = build(:account_screening_profile, owner: @org)
      profile.save(validate: false)

      ActiveRecord::Base.connected_to(role: :reading) do
        assert_equal profile, link_manager.stos_org_trade_screening_record(org: @org)
      end

      refute_predicate @org.billing_contact_link.link_id, :present?
    end

    test "creates a new profile if the linked profile has been deleted and log the broken link ref" do
      stats = GitHub::MemoryDogstatsD.new
      GitHub.stubs(:dogstats).returns(stats)

      assert @org.trade_screening_record_link.update(id: @profile.id)

      # Delete the profile so as not to trigger callbacks
      #   and ensure the link still exists
      @profile.delete
      assert link_id = @org.trade_screening_record_link.link_id

      expected_log = {
        "Body" => "sdn.find_linked_record.failed",
        "gh.sdn_link_manager.org" => @org.display_login,
        "gh.sdn_link_manager.ref_id" => link_id,
      }

      assert_logged(**expected_log) do
        ActiveRecord::Base.connected_to(role: :reading) do
          @new_profile = link_manager.stos_org_trade_screening_record(org: @org)
        end
      end

      assert_dogstats_increment 1, "sdn.find_linked_record.failed"

      # Check that a new profile has been created
      refute_equal @profile, @new_profile
      refute @new_profile.persisted?
      refute_predicate @org.billing_contact_link.link_id, :present?
    end

    test "creates a new profile if the org does not have one" do
      ActiveRecord::Base.connected_to(role: :reading) do
        profile = link_manager.stos_org_trade_screening_record(org: @org)

        # New profiles will not yet be persisted
        refute profile.persisted?
      end

      refute_predicate @org.billing_contact_link.link_id, :present?
    end
  end

  context "#link_trade_screening_record_to_org" do
    test "returns true after linking the profile" do
      @user.customer&.billing_contact&.destroy!
      @user.reload
      assert link_manager.link_trade_screening_record_to_org(screening_record: @profile, org: @org)

      assert_predicate @org.trade_screening_record_link.link_id, :present?
      assert_equal @org.trade_screening_record_link.link_id, @profile.id
      refute_predicate @org.billing_contact_link.link_id, :present?
    end

    test "returns true after linking the profile and billing contact" do
      assert link_manager.link_trade_screening_record_to_org(screening_record: @profile_with_contact, org: @org_with_contact)

      assert_predicate @org_with_contact.trade_screening_record_link.link_id, :present?
      assert_equal @org_with_contact.trade_screening_record_link.link_id, @profile_with_contact.id
      assert_predicate @org_with_contact.billing_contact_link.link_id, :present?
      assert_equal @org_with_contact.billing_contact_link.link_id, @contact.id
    end

    test "returns true after linking the profile with missing billing contact" do
      @user_with_contact.customer&.billing_contact&.destroy!
      @user_with_contact.reload
      assert link_manager.link_trade_screening_record_to_org(screening_record: @profile_with_contact, org: @org_with_contact)

      assert_predicate @org_with_contact.trade_screening_record_link.link_id, :present?
      assert_equal @org_with_contact.trade_screening_record_link.link_id, @profile_with_contact.id
      refute_predicate @org_with_contact.billing_contact_link.link_id, :present?
    end

    test "returns false if there's already a profile linked" do
      @user.customer&.billing_contact&.destroy!
      @user.reload
      assert link_manager.link_trade_screening_record_to_org(screening_record: @profile, org: @org)

      refute link_manager.link_trade_screening_record_to_org(screening_record: @profile, org: @org)

      assert_predicate @org.trade_screening_record_link.link_id, :present?
      assert_equal @org.trade_screening_record_link.link_id, @profile.id
      refute_predicate @org.billing_contact_link.link_id, :present?
    end

    test "returns false if there's already a profile linked after linking the billing contact" do
      assert link_manager.link_trade_screening_record_to_org(screening_record: @profile_with_contact, org: @org_with_contact)

      refute link_manager.link_trade_screening_record_to_org(screening_record: @profile_with_contact, org: @org_with_contact)

      assert_predicate @org_with_contact.trade_screening_record_link.link_id, :present?
      assert_equal @org_with_contact.trade_screening_record_link.link_id, @profile_with_contact.id
      assert_predicate @org_with_contact.billing_contact_link.link_id, :present?
      assert_equal @org_with_contact.billing_contact_link.link_id, @contact.id
    end

    test "returns false if the profile belongs to an org" do
      org_profile = create(:account_screening_profile, :with_org)

      refute link_manager.link_trade_screening_record_to_org(screening_record: org_profile, org: @org)

      refute_predicate @org.trade_screening_record_link.link_id, :present?
      refute_predicate @org.billing_contact_link.link_id, :present?
    end
  end

  context "#unlink_trade_screening_record_from_org" do
    test "returns true after unlinking the profile" do
      assert @org.trade_screening_record_link.update(id: @profile.id)
      assert_predicate @org.trade_screening_record_link.link_id, :present?
      refute_predicate @org.billing_contact_link.link_id, :present?

      assert link_manager.unlink_trade_screening_record_from_org(actor: @user, org: @org)

      refute_predicate @org.trade_screening_record_link.link_id, :present?
      refute_predicate @org.billing_contact_link.link_id, :present?
    end

    test "returns true after unlinking the profile and billing contact" do
      assert link_manager.link_trade_screening_record_to_org(screening_record: @profile_with_contact, org: @org_with_contact)
      assert_predicate @org_with_contact.trade_screening_record_link.link_id, :present?
      assert_predicate @org_with_contact.billing_contact_link.link_id, :present?

      assert link_manager.unlink_trade_screening_record_from_org(actor: @user_with_contact, org: @org_with_contact)

      refute_predicate @org_with_contact.trade_screening_record_link.link_id, :present?
      refute_predicate @org_with_contact.billing_contact_link.link_id, :present?
    end

    test "returns false if there's no profile linked" do
      refute link_manager.unlink_trade_screening_record_from_org(actor: @user, org: @org)

      refute_predicate @org.trade_screening_record_link.link_id, :present?
      refute_predicate @org.billing_contact_link.link_id, :present?
    end
  end
end
