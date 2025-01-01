# typed: true
# frozen_string_literal: true

require "test_helper"

class EnterpriseManagedDependencyTest < GitHub::TestCase
  fixtures do
    @normal_user = create(:user)
    @emu = create(:emu)
    @default_business = create(:business)
    @emu_business = @emu.enterprise_managed_business
    @guest_emu = create(:emu, :guest_collaborator, business: @emu_business)
    @org_admin = create :emu, business: @emu_business

    @first_admin = @emu_business.find_first_emu_owner
    business_user_account = create(:business_user_account, user: @normal_user, business: @default_business)

    @appended_shortcode = "+#{@emu_business.shortcode}@"

    @org_direct = create :enterprise_linked_organization, business: @emu_business, admin: @org_admin
    @org_derived = create :enterprise_linked_organization, business: @emu_business, admin: @org_admin

    @external_group = create :external_group, :with_members, business: @emu_business, number_of_members: 2

    @external_team = create :team, organization: @org_derived
    @internal_team = create(:team, organization: @org_derived)
    ExternalGroupTeam.create(external_group: @external_group, team: @external_team.reload)

    ExternalIdentityGroupMembership.create(external_group: @external_group, external_identity: @emu.external_identities.first)
    ExternalIdentityGroupMembership.create(external_group: @external_group, external_identity: @guest_emu.external_identities.first)

    @external_group.external_group_teams.pluck(:team_id).each do |team_id|
      ExternalGroupTeamReconcileJob.perform_now(external_group_id: @external_group.id, team_id: team_id, caller: self.class.name)
    end

    @external_group.reload

    @normal_team = create(:team, organization: @org_direct)
  end

  context "#deprovisioned?" do
    test "returns false for non EMU user" do
      user = create(:user)
      refute_predicate user, :deprovisioned?
    end

    test "relies on disabled external identity" do
      emu = create :emu, business: @emu_business
      refute emu.external_identities.first.disabled_at?
      refute_predicate emu, :deprovisioned?

      emu.external_identities.first.update(disabled_at: Time.now)
      assert_predicate emu, :deprovisioned?
    end

    test "assumes emu is deprovisioned when no external identity record" do
      emu = create :emu, business: @emu_business
      refute_predicate emu, :deprovisioned?

      emu.external_identities.first.destroy
      assert_predicate emu, :deprovisioned?
    end

    test "creating an emu without an email fails" do
      default_opts = { "email" => nil, "force_enterprise_managed" => true, "login_suffix" => @emu_business.shortcode }
      default_opts["business_id"] = @emu_business.id if TestEnv.test_in_multitenancy_mode?

      emu = User.create_with_random_password("invalid", false, default_opts)
      refute_predicate emu, :valid?
      refute_predicate emu, :deprovisioned?
    end
  end

  context "#is_emu_org_owner" do
    test "returns false when user is not an EMU" do
      refute @normal_user.is_emu_org_owner?
    end

    test "returns false when user is EMU and businesses are nil" do
      emu = create :emu

      refute emu.is_emu_org_owner?
    end

    test "returns false when user is EMU and businesses are not nil and orgs are nil" do

      refute @emu.is_emu_org_owner?
    end

    test "returns true when user is EMU and businesses are not nil and orgs are not nil and user is org admin" do
      emu = create :emu, business: @emu_business
      org = create :enterprise_linked_organization, business: @emu_business, admin: emu

      assert emu.is_emu_org_owner?
    end
  end

  context "add emu shortcode" do
    test "add business short code to an email" do
      email = "swanson@parks.org"
      emu_email = User::EnterpriseManagedDependency.add_shortcode(email, @emu_business)

      refute_nil emu_email
      assert_includes emu_email, @appended_shortcode
    end

    test "add business short code to an email with -admin" do
      email = "swanson@parks.org"
      emu_email = User::EnterpriseManagedDependency.add_shortcode(email, @emu_business, first_enterprise_owner: true)

      refute_nil emu_email
      assert_includes emu_email, "+#{@emu_business.shortcode}-admin@"
    end

    test "does not add business short code to an email with shortcode-admin" do
      email = "swanson+#{@emu_business.shortcode}-admin@parks.org"
      emu_email = User::EnterpriseManagedDependency.add_shortcode(email, @emu_business, first_enterprise_owner: true)

      refute_nil emu_email
      assert_includes emu_email, "+#{@emu_business.shortcode}-admin@"
      assert_equal email, emu_email
    end

    test "add business short code to an email array" do
      emails = ["swanson@parks.org", "park.recs@parks.org"]
      emu_emails = User::EnterpriseManagedDependency.add_shortcode(emails, @emu_business)

      refute_nil emu_emails
      assert_equal 2, emu_emails.count
      assert_includes emu_emails[0], @appended_shortcode
      assert_includes emu_emails[1], @appended_shortcode
    end

    test "works when the email array is empty" do
      emails = []
      emu_emails = User::EnterpriseManagedDependency.add_shortcode(emails, @emu_business)

      refute_nil emu_emails
      assert_equal 0, emu_emails.count
    end

    test "works when the email array contains nil" do
      emails = [nil]
      emu_emails = User::EnterpriseManagedDependency.add_shortcode(emails, @emu_business)

      refute_nil emu_emails
      assert_equal 1, emu_emails.count
    end

    test "works when the email is a string" do
      emu_email = User::EnterpriseManagedDependency.add_shortcode("swansonparks.org", @emu_business)

      refute_nil emu_email
      assert_equal "swansonparks.org", emu_email
    end

    test "works when the email does not have a user name" do
      emu_email = User::EnterpriseManagedDependency.add_shortcode("@parks.org", @emu_business)

      refute_nil emu_email
      assert_equal "+#{@emu_business.shortcode}@parks.org", emu_email
    end

    test "works when the email does not have a domain" do
      emu_email = User::EnterpriseManagedDependency.add_shortcode("swanson@", @emu_business)

      refute_nil emu_email
      assert_equal "swanson@", emu_email
    end

    test "returns nil email when nil is passed in" do
      emu_email = User::EnterpriseManagedDependency.add_shortcode(nil, @emu_business)

      assert_nil emu_email
    end

    test "returns email when nil is passed in for business" do
      email = "swanson@parks.org"
      emu_email = User::EnterpriseManagedDependency.add_shortcode(email, nil)

      refute_nil emu_email
      assert_equal email, emu_email
    end

    test "returns email when business is not an emu" do
      email = "swanson@parks.org"
      emu_email = User::EnterpriseManagedDependency.add_shortcode(email, @default_business)

      refute_nil emu_email
      assert_equal email, emu_email
    end

    test "works when array contains nil and other values" do
      emails = [nil, 1, "abc", "swanson@parks.org"]
      emu_emails = User::EnterpriseManagedDependency.add_shortcode(emails, @emu_business)

      refute_nil emu_emails
      assert_equal 4, emu_emails.count
      assert_nil emu_emails[0]
      assert_equal emails[1], emu_emails[1]
      assert_equal emails[2], emu_emails[2]
      assert_includes emu_emails[3], @appended_shortcode
    end

    test "shortcode is not added when it already contains same shortcode" do
      email = "swanson+#{@emu_business.shortcode}@parks.org"
      emu_email = User::EnterpriseManagedDependency.add_shortcode(email, @emu_business)

      refute_nil emu_email
      assert_includes emu_email, @appended_shortcode
      assert_equal email, emu_email
    end

    test "shortcode is not added for a web committer email" do
      emu_email = User::EnterpriseManagedDependency.add_shortcode(GitHub.web_committer_email, @emu_business)

      assert_equal GitHub.web_committer_email, emu_email
    end
  end

  context "remove emu shortcode" do
    test "shortcode is removed from an emu email" do
      emu_email = "swanson+#{@emu_business.shortcode}@parks.org"

      email = User::EnterpriseManagedDependency.remove_shortcode(emu_email, @emu_business)

      assert_equal "swanson@parks.org", email
    end

    test "shortcode is removed from a first admin email" do
      emu_email = "swanson+#{@emu_business.shortcode}-admin@parks.org"

      email = User::EnterpriseManagedDependency.remove_shortcode(emu_email, @emu_business, first_enterprise_owner: true)

      assert_equal "swanson@parks.org", email
    end

    test "returns nil email when nil is passed in" do
      email = User::EnterpriseManagedDependency.remove_shortcode(nil, @emu_business)

      assert_nil email
    end

    test "returns email when nil is passed in for business" do
      emu_email = "swanson+#{@emu_business.shortcode}@parks.org"
      email = User::EnterpriseManagedDependency.add_shortcode(emu_email, nil)

      refute_nil email
      assert_equal email, emu_email
    end

    test "returns a web committer email" do
      email = User::EnterpriseManagedDependency.remove_shortcode(GitHub.web_committer_email, @emu_business)

      assert_equal GitHub.web_committer_email, email
    end

    test "shortcode is removed from an emu users email" do
      emu_email = @emu.primary_user_email.email
      email = @emu.remove_shortcode(emu_email)

      refute_equal emu_email, email
      assert_equal @emu.profile_email, email
    end

    test "shortcode is removed from an emu first admin users email" do
      emu_email = @first_admin.primary_user_email.email
      email = @first_admin.remove_shortcode(emu_email)

      refute_equal emu_email, email
      assert_equal @first_admin.profile_email, email
    end

    test "same email is returned for a non emu user" do
      non_emu_email = @normal_user.primary_user_email.email
      email = @emu.remove_shortcode(non_emu_email)

      assert_equal non_emu_email, email
    end
  end

  context "enterprise managed user" do
    test "enterprise_managed? when business type is default" do
      refute @normal_user.send(:is_enterprise_managed_user?)
      refute @normal_user.is_enterprise_managed?
    end

    test "enterprise_managed? when business type is enterprise_managed" do
      assert @emu.send(:is_enterprise_managed_user?)
      assert @emu.is_enterprise_managed?
    end

    test "enterprise_managed? when more than one business_user_accounts" do
      business2 = create(:business)
      business_user_account2 = create(:business_user_account, business: business2, user: @normal_user)
      Business.any_instance.expects(:enterprise_managed_user_enabled?).never
      refute @normal_user.send(:is_enterprise_managed_user?)
      refute @normal_user.is_enterprise_managed?
    end

    test "enterprise_managed? true for tenant-owned user in multi tenant enterprise mode" do
      on_multi_tenant_enterprise do
        emu = create :emu

        refute_equal User::EnterpriseManagedDependency::NON_ENTERPRISE_MANAGED_BUSINESS_ID, emu.business_id
        assert_predicate emu, :is_enterprise_managed_user?
        assert_predicate emu, :is_enterprise_managed?
      end
    end

    test "enterprise_managed? false for tenant-owned bot in multi tenant enterprise mode" do
      on_multi_tenant_enterprise do
        emu = create :emu
        tenant = emu.enterprise_managed_business
        assert_equal tenant.id, emu.business_id
        integration = create(:integration, owner: emu, name: "simple-ci", default_permissions: { "metadata" => :read })
        bot = integration.bot
        assert_equal tenant.id, bot.business_id

        refute_equal User::EnterpriseManagedDependency::NON_ENTERPRISE_MANAGED_BUSINESS_ID, bot.business_id
        refute_predicate bot, :is_enterprise_managed_user?
        refute_predicate bot, :is_enterprise_managed?
      end
    end

    test "renaming_enabled? when user is not enterprise managed" do
      assert @normal_user.renaming_enabled?
    end

    test "change_profile_name_enabled? when user is not enterprise managed" do
      assert @normal_user.change_profile_name_enabled?
    end

    test "change_email_enabled? when user is not enterprise managed" do
      assert @normal_user.change_email_enabled?
    end

    test "change_company_enabled? when user is not enterprise managed" do
      assert @normal_user.change_company_enabled?
    end

    test "renaming_enabled? when user is enterprise managed" do
      refute @emu.renaming_enabled?
    end

    test "change_profile_name_enabled? when user is enterprise managed" do
      refute @emu.change_profile_name_enabled?
    end

    test "change_email_enabled? when user is enterprise managed" do
      refute @emu.change_email_enabled?
    end

    test "change_company_enabled? when user is enterprise managed" do
      refute @emu.change_company_enabled?
    end
  end

  context "#guest_collaborator?" do
    test "returns false when the user is not enterprise managed" do
      refute_predicate @normal_user, :guest_collaborator?
    end

    test "returns false when the user is enterprise managed but not a guest collaborator" do
      refute_predicate @emu, :guest_collaborator?
    end

    test "returns true when the user is enterprise managed and a guest collaborator" do
      assert_predicate @guest_emu, :guest_collaborator?
    end
  end

  context "#is_first_emu_owner?" do
    test "returns false if the user is not enterprise managed" do
      refute_predicate @normal_user, :is_first_emu_owner?
    end

    test "returns false if user is org" do
      org = create(:organization)
      refute_predicate org, :is_first_emu_owner?
    end

    test "returns false if user is bot" do
      integration = create(:integration, name: "simple-ci", default_permissions: { "metadata" => :read })
      refute_predicate integration.bot, :is_first_emu_owner?
    end

    test "returns false if user is not first enterprise owner" do
      refute_predicate @emu, :is_first_emu_owner?
    end

    test "returns false if user is first enterprise owner account but no longer an owner" do
      default_opts = { "email" => "monalisa@microsoft.com", "login_suffix" => @emu_business.shortcode }
      emu_admin_user = User.create_with_random_password("monalisa@microsoft.com", false, default_opts)
      emu_business_user_account = create(:business_user_account, user: emu_admin_user, business: @emu_business)

      refute_predicate emu_admin_user, :is_first_emu_owner?
    end

    test "returns true if user is first enterprise owner of the emu business" do
      emu_owner = @emu_business.find_first_emu_owner
      assert_predicate emu_owner, :is_first_emu_owner?
    end
  end

  context "#enterprise_managed_business" do
    test "returns nil if there is no business user account" do
      user = create :user
      assert_equal user.business_user_accounts.count, 0
      assert_nil user.enterprise_managed_business
    end

    test "returns nil if there is more than one business user account" do
      user = create :user
      business_1 = create(:business)
      business_2 = create(:business)
      business_user_account = create(:business_user_account, user: user, business: business_1)
      business_user_account = create(:business_user_account, user: user, business: business_2)

      assert_equal user.business_user_accounts.count, 2
      assert_nil user.enterprise_managed_business
    end

    test "returns nil if the business is not enterprise managed" do
      assert_equal @normal_user.business_user_accounts.count, 1
      assert_nil @normal_user.enterprise_managed_business
    end

    test "returns enterprise managed business when there is one business user account and the user is EMU" do
      assert_equal @emu.business_user_accounts.count, 1
      enterprise_managed_business = @emu.enterprise_managed_business
      refute_nil enterprise_managed_business
      assert_equal @emu_business, enterprise_managed_business
    end
  end

  context "#emu_creating_public_repo?" do
    test "returns false for regular users on a private repo" do
      refute @normal_user.emu_creating_public_repo?(:private)
    end

    test "returns false for regular users on a internal repo" do
      refute @normal_user.emu_creating_public_repo?(:internal)
    end

    test "returns false for regular users on a public repo" do
      refute @normal_user.emu_creating_public_repo?(:public)
    end

    test "returns false for bots" do
      refute create(:bot).emu_creating_public_repo?(:public)
    end

    test "returns false for EMUs on a private repo" do
      refute @emu.emu_creating_public_repo?(:private)
    end

    test "returns false for EMUs on an internal repo" do
      refute @emu.emu_creating_public_repo?(:internal)
    end

    test "returns true for EMUs on a public repo" do
      assert @emu.emu_creating_public_repo?(:public)
    end

    test "returns false for EMU orgs a private repo" do
      org = create(:enterprise_linked_organization, business: @emu_business)
      refute org.emu_creating_public_repo?(:private)
    end

    test "returns false for EMU orgs an internal repo" do
      org = create(:enterprise_linked_organization, business: @emu_business)
      refute org.emu_creating_public_repo?(:internal)
    end

    test "returns true for EMU orgs on a public repo" do
      org = create(:enterprise_linked_organization, business: @emu_business)
      assert org.emu_creating_public_repo?(:public)
    end
  end

  context "#update_first_emu_owner_email" do
    test "returns email unchanged for normal user" do
      primary_user_email = @normal_user.primary_user_email.email

      message = @normal_user.update_first_emu_owner_email("foobar@contoso.com")

      assert_equal message, "Email unchanged."
      assert_equal primary_user_email, @normal_user.reload.primary_user_email.email
      refute_equal "foobar@contoso.com", @normal_user.profile_email
    end

    test "returns email unchanged for emu user" do
      primary_user_email = @emu.primary_user_email.email

      message = @emu.update_first_emu_owner_email("foobar@contoso.com")

      assert_equal message, "Email unchanged."
      assert_equal primary_user_email, @emu.reload.primary_user_email.email
      refute_equal "foobar@contoso.com", @emu.profile_email
    end

    test "returns email unchanged for admin user when email is the same" do
      primary_user_email = @first_admin.primary_user_email.email

      message = @first_admin.update_first_emu_owner_email(@first_admin.profile_email)

      assert_equal message, "Email unchanged."
      assert_equal primary_user_email, @first_admin.reload.primary_user_email.email
    end

    test "works for admin user" do
      primary_user_email = @first_admin.primary_user_email.email

      message = @first_admin.update_first_emu_owner_email("foobar@contoso.com")

      new_primary_user_email = User::EnterpriseManagedDependency.add_shortcode("foobar@contoso.com", @emu_business, first_enterprise_owner: true)
      assert_equal message, "Email updated successfully.  Please note that the primary email address has been changed to '#{new_primary_user_email}'."

      refute_equal primary_user_email, @first_admin.reload.primary_user_email.email
      assert_equal new_primary_user_email, @first_admin.primary_user_email.email
      assert_equal "foobar@contoso.com", @first_admin.profile_email
    end

    test "changing case of email does not create out of sync profile email" do
      primary_user_email = @first_admin.primary_user_email.email

      email_address = "foobar@contoso.com"
      new_email_address = "fooBar@contoso.com"

      @first_admin.update_first_emu_owner_email(email_address)

      new_primary_user_email = User::EnterpriseManagedDependency.add_shortcode(email_address, @emu_business, first_enterprise_owner: true)

      # successfully updates email first time
      refute_equal primary_user_email, @first_admin.reload.primary_user_email.email
      assert_equal new_primary_user_email, @first_admin.primary_user_email.email
      assert_equal email_address, @first_admin.profile_email

      # unsuccessfully updates email using different casing
      assert_equal "Emails is invalid", @first_admin.update_first_emu_owner_email(new_email_address)

      # profile email did not update to new_email_address
      assert_equal email_address, @first_admin.reload.profile_email
    end

    test "rolls back transaction if profile email save fails" do
      Profile.any_instance.stubs(:save!).returns(false)

      original_primary_email = @first_admin.primary_user_email.email
      original_profile_email = @first_admin.profile_email

      new_email_address = "foobar@contoso.com"

      assert_equal "Error updating admin profile", @first_admin.update_first_emu_owner_email(new_email_address)
      assert_equal original_primary_email, @first_admin.reload.primary_user_email.email
      assert_equal original_profile_email, @first_admin.profile_email
    end

    test "leading / trailing whitespace is trimmed" do
      primary_user_email = @first_admin.primary_user_email.email

      new_email_address = "  foobar@contoso.com  "
      trimmed_new_email_address = "foobar@contoso.com"

      message = @first_admin.update_first_emu_owner_email(new_email_address)

      new_primary_user_email = User::EnterpriseManagedDependency.add_shortcode(trimmed_new_email_address, @emu_business, first_enterprise_owner: true)
      assert_equal message, "Email updated successfully.  Please note that the primary email address has been changed to '#{new_primary_user_email}'."

      refute_equal primary_user_email, @first_admin.reload.primary_user_email.email
      assert_equal new_primary_user_email, @first_admin.primary_user_email.email
      assert_equal trimmed_new_email_address, @first_admin.profile_email
    end
  end

  context "#add_emu_shortcode_to_emails" do
    test "returns email unchanged for normal user" do
      assert_equal "normal.user@conto.com", @normal_user.add_emu_shortcode_to_emails("normal.user@conto.com")
    end

    test "returns email with shortcode for emu user" do
      assert_equal "emu.user+#{@emu_business.shortcode}@conto.com", @emu.add_emu_shortcode_to_emails("emu.user@conto.com")
    end

    test "returns email with shortcode and admin for emu first owner" do
      assert_equal "owner.user+#{@emu_business.shortcode}-admin@conto.com", @first_admin.add_emu_shortcode_to_emails("owner.user@conto.com")
    end
  end

  context "#known_email?" do
    test "returns false when email is nil" do
      refute @first_admin.known_email?(nil)
    end

    test "returns false when normal user" do
      refute @normal_user.known_email?(@normal_user.primary_user_email.email)
    end

    test "returns false when emu user" do
      refute @emu.known_email?(@emu.primary_user_email.email)
    end

    test "returns false when organization" do
      org = create(:enterprise_linked_organization, business: @emu_business)
      refute org.known_email?(org.outbound_email)
    end

    test "returns true when first emu owner" do
      assert @first_admin.known_email?(@first_admin.primary_user_email.email)
      assert @first_admin.known_email?(@first_admin.profile_email)
    end
  end
end unless GitHub.single_business_environment?

class EnterpriseManagedDependencyGHESTest < GitHub::TestCase
  include AuthenticationHelpers
  include AuthenticationHelpers::SAML

  fixtures do
    setup_saml_auth_mode(with_scim: true)
    @enterprise = create(:global_business)
    @provider = @enterprise.external_provider
    @scim_user = create :ghes_scim_user
    @normal_user = create :user
    @saml_user = create(:user_saml_mapping).user
  end

  setup do
    setup_saml_auth_mode(with_scim: true)
  end

  context "#scim_managed_user?" do
    context "mixed mode SCIM and basic auth" do
      test "returns false when basic auth user" do
        GitHub.stubs(:builtin_auth_fallback).returns(true)
        refute @normal_user.scim_managed_user?
      end

      test "returns true when scim user" do
        GitHub.stubs(:builtin_auth_fallback).returns(true)
        assert @scim_user.scim_managed_user?
      end

      test "returns true when disabled scim user" do
        GitHub.stubs(:builtin_auth_fallback).returns(true)
        @scim_user.external_identities.first.disable
        assert @scim_user.scim_managed_user?
      end

      test "returns true when deleted scim user" do
        GitHub.stubs(:builtin_auth_fallback).returns(true)
        @scim_user.external_identities.first.update(deleted_at: Time.now)
        assert @scim_user.scim_managed_user?
      end
    end

    context "SCIM only" do
      test "returns false when basic auth user" do
        refute @normal_user.scim_managed_user?
      end

      test "returns true when scim user" do
        assert @scim_user.scim_managed_user?
      end

      test "returns true when disabled scim user" do
        @scim_user.external_identities.first.disable
        assert @scim_user.scim_managed_user?
      end

      test "returns true when deleted scim user" do
        @scim_user.external_identities.first.update(deleted_at: Time.now)
        assert @scim_user.scim_managed_user?
      end
    end

    context "basic auth mode" do
      test "returns false when basic auth user" do
        with_auth_mode(:default) do
          refute @normal_user.scim_managed_user?
        end
      end

      test "returns false when scim user" do
        with_auth_mode(:default) do
          refute @scim_user.scim_managed_user?
        end
      end

      test "returns false when saml user" do
        with_auth_mode(:default) do
          refute @saml_user.scim_managed_user?
        end
      end
    end
  end

  context "#managed_user_deletion_disabled?" do
    context "mixed mode SCIM and basic auth" do
      test "returns false when basic auth user" do
        GitHub.stubs(:builtin_auth_fallback).returns(true)
        refute @normal_user.managed_user_deletion_disabled?
      end

      test "returns true when scim user" do
        GitHub.stubs(:builtin_auth_fallback).returns(true)
        assert @scim_user.managed_user_deletion_disabled?
      end

      test "returns true when disabled scim user" do
        GitHub.stubs(:builtin_auth_fallback).returns(true)
        @scim_user.external_identities.first.disable
        assert @scim_user.managed_user_deletion_disabled?
      end

      test "returns true when deleted scim user" do
        GitHub.stubs(:builtin_auth_fallback).returns(true)
        @scim_user.external_identities.first.update(deleted_at: Time.now)
        assert @scim_user.managed_user_deletion_disabled?
      end
    end

    context "SCIM only" do
      test "returns false when basic auth user" do
        refute @normal_user.managed_user_deletion_disabled?
      end

      test "returns true when scim user" do
        assert @scim_user.managed_user_deletion_disabled?
      end

      test "returns true when disabled scim user" do
        @scim_user.external_identities.first.disable
        assert @scim_user.managed_user_deletion_disabled?
      end

      test "returns true when deleted scim user" do
        @scim_user.external_identities.first.update(deleted_at: Time.now)
        assert @scim_user.managed_user_deletion_disabled?
      end
    end

    context "mixed mode SAML and basic auth" do
      test "returns false when basic auth user" do
        GitHub.stubs(:builtin_auth_fallback).returns(true)
        GitHub.global_business.saml_provider.destroy
        refute @normal_user.managed_user_deletion_disabled?
      end

      test "returns false when SAML user" do
        GitHub.stubs(:builtin_auth_fallback).returns(true)
        GitHub.global_business.saml_provider.destroy
        refute @saml_user.managed_user_deletion_disabled?
      end

      test "returns false when SCIM user" do
        GitHub.stubs(:builtin_auth_fallback).returns(true)
        @provider.destroy
        refute @scim_user.managed_user_deletion_disabled?
      end
    end

    context "SAML only" do
      test "returns false when basic auth user" do
        GitHub.global_business.saml_provider.destroy
        refute @normal_user.managed_user_deletion_disabled?
      end

      test "returns false when SAML user" do
        GitHub.global_business.saml_provider.destroy
        refute @saml_user.managed_user_deletion_disabled?
      end

      test "returns false when SCIM user" do
        @provider.destroy
        refute @scim_user.managed_user_deletion_disabled?
      end
    end

    context "basic auth mode" do
      test "returns false when basic auth user" do
        with_auth_mode(:default) do
          refute @normal_user.managed_user_deletion_disabled?
        end
      end

      test "returns false when scim user" do
        with_auth_mode(:default) do
          refute @scim_user.managed_user_deletion_disabled?
        end
      end

      test "returns false when saml user" do
        with_auth_mode(:default) do
          refute @saml_user.managed_user_deletion_disabled?
        end
      end
    end
  end
end if GitHub.single_business_environment?
