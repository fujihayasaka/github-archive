# typed: true
# frozen_string_literal: true

require "test_helper"

class BusinessManagedUserDependencyTest < GitHub::TestCase
  fixtures do
    @business = create(:business)
    @emu_business = create(:business, :enterprise_managed)
    @emu_business_without_owner = create(:business, :enterprise_managed, :without_enterprise_managed_user_owner)
    @user = create(:user)

    @invalid_emails = ["john",
      "john@",
      "john@()",
      "john@   ",
      "@foo.com",
      "test@test.c@m",
      "user with spaces@foo.com",
      "two@gmail@outlook.com"
    ]
    GitHub.flipper[:disable_external_group_team_reconcile_job].disable
  end

  context "Business#enterprise_managed_user_enabled?" do
    test "returns false when the enterprise is a default business type" do
      refute_predicate @business, :enterprise_managed_user_enabled?
    end

    test "returns true when the enterprise is configured for enterprised managed" do
      assert_predicate @emu_business, :enterprise_managed_user_enabled?
    end
  end

  context "Business#enterprise_managed_user_and_saml_sso_enabled?" do
    test "returns true when the enterprise saml sso is configured and enterprise managed" do
      provider = create(:business_saml_provider, business: @emu_business)
      assert_predicate @emu_business, :enterprise_managed_user_and_saml_sso_enabled?
    end

    test "returns false when the enterprise saml sso is not configured and enterprise managed" do
      refute_predicate @emu_business, :enterprise_managed_user_and_saml_sso_enabled?
    end

    test "returns false when the enterprise saml sso is configured and default business type" do
      refute_predicate @business, :enterprise_managed_user_and_saml_sso_enabled?
    end
  end

  context "Business#create_and_add_first_emu_owner" do
    test "return ArgumentError if email is invalid" do
      assert_raises ArgumentError do
        @emu_business_without_owner.create_and_add_first_emu_owner(email: nil, actor: @user)
      end

      assert_raises ArgumentError do
        @emu_business_without_owner.create_and_add_first_emu_owner(actor: @user)
      end

      @invalid_emails.each do |invalid_email|
        assert_raises ArgumentError do
          email = @emu_business_without_owner.create_and_add_first_emu_owner(invalid_email, actor: @user)
        end
      end
    end

    test "return UnableToCreateAdminUserError if business is default business type" do
      assert_raises Business::UnableToCreateAdminUserError do
        @business.create_and_add_first_emu_owner(email: "inpreman@github.com", actor: @user)
      end
    end

    test "return UnableToCreateAdminUserError if SAML is enabled for enterprise managed" do
      create(:business_saml_provider, business: @emu_business_without_owner)
      assert_raises Business::UnableToCreateAdminUserError do
        @emu_business_without_owner.create_and_add_first_emu_owner(email: "inpreman@github.com", actor: @user)
      end
    end

    test "returns Business::UnableToCreateAdminUserError if admin user creation fails" do
      User.any_instance.stubs(:valid?).returns(false)
      assert_raises Business::UnableToCreateAdminUserError do
        @emu_business_without_owner.create_and_add_first_emu_owner(email: "inpreman@github.com", actor: @user)
      end
    end

    test "should rollback user creation if add owner fails" do
      Business.any_instance.stubs(:add_owner).raises(RuntimeError)
      assert_raises(RuntimeError) do
        @emu_business_without_owner.create_and_add_first_emu_owner(email: "inpreman@github.com", actor: @user)
      end

      assert_nil User.find_by_login(@emu_business_without_owner.shortcode + "_admin"), "expected admin_user to be nil"
    end

    test "returns UnableToCreateAdminUserError if a user already with same login exists for EMU enabled enterprise" do
      default_opts = { "email" => "monalisa@github.com", "force_enterprise_managed" => true, "login_suffix" => "admin" }
      User.create_with_random_password(@emu_business_without_owner.shortcode, false, default_opts)

      assert_raises Business::UnableToCreateAdminUserError do
        @emu_business_without_owner.create_and_add_first_emu_owner(email: "inpreman@github.com", actor: @user)
      end
    end

    test "returns AdminAlreadyExistsError if an admin user already exists for EMU enabled enterprise" do
      @emu_business_without_owner.create_and_add_first_emu_owner(email: "monalisa@github.com", actor: @user)

      assert_raises Business::AdminAlreadyExistsError do
        @emu_business_without_owner.create_and_add_first_emu_owner(email: "inpreman@github.com", actor: @user)
      end
    end

    test "does not create the admin user if there is another admin" do
      default_opts = { "email" => "monalisa@microsoft.com", "force_enterprise_managed" => true, "login_suffix" => "admin" }
      existing_admin_user = User.create_with_random_password("monalisa@microsoft.com", false, default_opts)
      @emu_business_without_owner.add_owner(existing_admin_user, actor: @user, send_email_notification: false)

      assert_raises Permissions::Participant::PermissionGrantError do
        @emu_business_without_owner.create_and_add_first_emu_owner(email: "inpreman@microsoft.com", actor: @user)
      end
      refute User.find_by_login(@emu_business_without_owner.shortcode + "_admin")
    end

    test "creates the admin user and adds the owner as enterprise owner" do
      @emu_business_without_owner.create_and_add_first_emu_owner(email: "inpreman@microsoft.com", actor: @user)

      admin_user = User.find_by_login(@emu_business_without_owner.shortcode + "_admin")
      refute_nil admin_user, "expected admin_user to be not nil"
      assert_equal admin_user.email, "inpreman+#{@emu_business_without_owner.shortcode}-admin@microsoft.com"
      assert_equal "inpreman@microsoft.com", admin_user.profile_email
      assert @emu_business_without_owner.owner?(admin_user), "expected admin_user to be emu_business_without_owner owner"
    end

    test "creates the admin user and adds the owner as enterprise owner for email with plus sign" do
      @emu_business_without_owner.create_and_add_first_emu_owner(email: "inpreman+#{@emu_business_without_owner.shortcode}-admin@microsoft.com", actor: @user)

      admin_user = User.find_by_login(@emu_business_without_owner.shortcode + "_admin")
      refute_nil admin_user, "expected admin_user to be not nil"
      assert_equal admin_user.email, "inpreman+#{@emu_business_without_owner.shortcode}-admin@microsoft.com"
      assert_equal "inpreman+#{@emu_business_without_owner.shortcode}-admin@microsoft.com", admin_user.profile_email
      assert @emu_business_without_owner.owner?(admin_user), "expected admin_user to be emu_business_without_owner owner"
    end

    test "creates the admin user and adds the owner as enterprise owner for email with multiple sub-addressing sign" do
      @emu_business_without_owner.create_and_add_first_emu_owner(email: "inpreman+admin@microsoft.com", actor: @user)

      admin_user = User.find_by_login(@emu_business_without_owner.shortcode + "_admin")
      refute_nil admin_user, "expected admin_user to be not nil"
      assert_equal admin_user.email, "inpreman+admin+#{@emu_business_without_owner.shortcode}-admin@microsoft.com"
      assert_equal "inpreman+admin@microsoft.com", admin_user.profile_email
      assert @emu_business_without_owner.owner?(admin_user), "expected admin_user to be emu_business_without_owner owner"
    end

    test "creates the admin user and adds the owner as enterprise owner for multi tenant" do
      on_multi_tenant_enterprise do
        GitHub::CurrentTenant.set(@emu_business_without_owner)

        # Unscope for creation of first admin user.
        # Creation of the first admin is performed outside the context of a tenant
        # so we shouldn't scope to the tenant during this call.
        GitHub::CurrentTenant.unscope do
          @emu_business_without_owner.create_and_add_first_emu_owner(email: "inpreman@microsoft.com", actor: @user)
        end

        admin_user = User.find_by_login(@emu_business_without_owner.shortcode + "_admin")
        refute_nil admin_user, "expected admin_user to be not nil"
        assert_equal admin_user.email, "inpreman+#{@emu_business_without_owner.shortcode}-admin@microsoft.com"
        assert_equal "inpreman@microsoft.com", admin_user.profile_email
        assert @emu_business_without_owner.owner?(admin_user), "expected admin_user to be emu_business_without_owner owner"
        assert_equal @emu_business_without_owner.id, admin_user.business_id
        assert_predicate admin_user, :is_enterprise_managed?

        GitHub::CurrentTenant.remove
      end
    end
  end

  context "Business#reset_first_emu_owner" do
    test "raises UnableToFindExistingAdminUserError if an admin user does not already exist for EMU enabled enterprise" do
      assert_raises Business::UnableToFindExistingAdminUserError do
        @emu_business_without_owner.reset_first_emu_owner(email: "monalisa@github.com")
      end
    end

    test "resets the password for the enterprise owner" do
      admin_user = User.find_by_login(@emu_business.shortcode + "_admin")
      profile_email = admin_user.profile_email
      email = admin_user.email

      assert_difference "ActionMailer::Base.deliveries.size", +1 do
        perform_enqueued_jobs(only: [ApplicationDeliveryJob]) do
          @emu_business.reset_first_emu_owner
        end
      end

      assert_equal admin_user.email, email
      assert_equal profile_email, admin_user.profile_email
    end
  end

  context "Business#find_first_emu_owner" do
    test "return nil if business is not enterprise managed" do
      assert_nil @business.find_first_emu_owner
    end

    test "return nil if emu admin user account does not exist" do
      assert_nil @emu_business_without_owner.find_first_emu_owner
    end

    test "return nil if the first admin user is not an owner" do
      default_opts = { "email" => "monalisa@github.com", "force_enterprise_managed" => true, "login_suffix" => "admin" }
      User.create_with_random_password(@emu_business_without_owner.shortcode, false, default_opts)

      admin_user = @emu_business_without_owner.find_first_emu_owner
      assert_nil admin_user
    end
    test "return emu owner if emu admin user account exists" do
      default_opts = { "email" => "monalisa@github.com", "force_enterprise_managed" => true, "login_suffix" => "admin" }
      existing_admin_user = User.create_with_random_password(@emu_business_without_owner.shortcode, false, default_opts)
      @emu_business_without_owner.add_owner(existing_admin_user, actor: @user, send_email_notification: false)

      admin_user = @emu_business_without_owner.find_first_emu_owner
      refute_nil admin_user
      assert_equal existing_admin_user.login, admin_user.login
    end
  end

  context "Business#find_emu_owners_except_first" do
    test "returns empty array if business is not enterprise managed" do
      assert_empty @business.find_emu_owners_except_first
    end

    test "returns emu owners excluding the first admin account" do
      second_admin = create(:emu, business: @emu_business)
      @emu_business.add_owner(second_admin, actor: @user, send_email_notification: false)

      found_owners = @emu_business.find_emu_owners_except_first

      assert_equal 1, found_owners.count
      refute_includes found_owners, @emu_business.find_first_emu_owner
      assert_includes found_owners, second_admin
    end
  end

  context "Business#is_first_emu_owner" do
    test "returns false if business is not enterprise managed" do
      refute @business.is_first_emu_owner?(user: @user)
    end

    test "returns false if user is nil" do
      refute @emu_business_without_owner.is_first_emu_owner?(user: nil)
    end

    test "returns false if user is org" do
      org = create(:organization)
      refute @emu_business_without_owner.is_first_emu_owner?(user: org)
    end

    test "returns false if user is bot" do
      integration = create(:integration, name: "simple-ci", default_permissions: { "metadata" => :read })
      refute @emu_business_without_owner.is_first_emu_owner?(user: integration.bot)
    end

    test "returns false if the user is not an owner" do
      refute @emu_business_without_owner.is_first_emu_owner?(user: @user)
    end

    test "returns false if the user doesn't have a business user account" do
      default_opts = { "email" => "monalisa@microsoft.com", "force_enterprise_managed" => true, "login_suffix" => @emu_business_without_owner.shortcode }
      existing_admin_user = User.create_with_random_password("monalisa@microsoft.com", false, default_opts)
      @emu_business_without_owner.add_owner(existing_admin_user, actor: @user, send_email_notification: false)
      @emu_business_without_owner.user_accounts.remove_members([existing_admin_user.id])

      refute @emu_business_without_owner.is_first_emu_owner?(user: existing_admin_user)
    end

    test "returns false if the user is an admin user but not first admin user owner" do
      default_opts = { "email" => "monalisa@microsoft.com", "force_enterprise_managed" => true, "login_suffix" => @emu_business_without_owner.shortcode }
      existing_admin_user = User.create_with_random_password("monalisa@microsoft.com", false, default_opts)
      @emu_business_without_owner.add_owner(existing_admin_user, actor: @user, send_email_notification: false)

      refute @emu_business_without_owner.is_first_emu_owner?(user: existing_admin_user)
    end

    test "returns false if the user has a linked external identity" do
      emu_biz = create(:business, :enterprise_managed, :without_enterprise_managed_user_owner)
      emu_biz.create_and_add_first_emu_owner(email: "inpreman@microsoft.com", actor: create(:staff_admin_user))
      admin_user = @emu_business_without_owner.find_first_emu_owner

      provider = create :business_saml_provider, business: @business
      create(:external_identity, user: admin_user, provider: provider)

      refute @emu_business_without_owner.is_first_emu_owner?(user: admin_user)
    end

    test "returns true if the user is first admin user" do
      @emu_business_without_owner.create_and_add_first_emu_owner(email: "inpreman@microsoft.com", actor: @user)
      admin_user = @emu_business_without_owner.find_first_emu_owner

      assert @emu_business_without_owner.is_first_emu_owner?(user: admin_user)
    end
  end

  context "#add_emu_shortcode_to_emails" do
    test "returns email unchanged for normal business" do
      assert_equal "normal.user@conto.com", @business.add_emu_shortcode_to_emails("normal.user@conto.com")
    end

    test "returns email with shortcode for emu business" do
      assert_equal "emu.user+#{@emu_business.shortcode}@conto.com", @emu_business.add_emu_shortcode_to_emails("emu.user@conto.com")
    end

    test "returns email unchanged for normal business when flag is passed" do
      assert_equal "normal.user@conto.com", @business.add_emu_shortcode_to_emails("normal.user@conto.com", first_enterprise_owner: true)
    end

    test "returns email with shortcode and admin for emu business when flag is passed" do
      assert_equal "owner.user+#{@emu_business.shortcode}-admin@conto.com", @emu_business.add_emu_shortcode_to_emails("owner.user@conto.com", first_enterprise_owner: true)
    end
  end

  context "#remove_shortcode" do
    test "returns email unchanged for normal business" do
      assert_equal "normal.user+short@conto.com", @business.remove_shortcode("normal.user+short@conto.com")
    end

    test "returns email without shortcode for emu business" do
      assert_equal "emu.user@conto.com", @emu_business.remove_shortcode("emu.user+#{@emu_business.shortcode}@conto.com")
    end

    test "returns email unchanged for normal business when flag is passed" do
      assert_equal "normal.user+short@conto.com", @business.remove_shortcode("normal.user+short@conto.com", first_enterprise_owner: true)
    end

    test "returns email without shortcode and admin for emu business when flag is passed" do
      assert_equal "owner.user@conto.com", @emu_business.remove_shortcode("owner.user+#{@emu_business.shortcode}-admin@conto.com", first_enterprise_owner: true)
    end
  end

  context "#enterprise_managed_business_for" do
    test "returns nil if resource is nil" do
      assert_nil Business.enterprise_managed_business_for(resource: nil)
    end

    test "returns nil if resource is empty" do
      assert_nil Business.enterprise_managed_business_for(resource: "")
    end

    test "returns nil if not a supported type" do
      org_invite = create :organization_invitation
      assert_nil Business.enterprise_managed_business_for(resource: org_invite)
    end

    test "returns nil if user is not an EMU" do
      user = create :user, skip_enterprise_managed_user: true
      refute user.is_enterprise_managed?
      assert_nil Business.enterprise_managed_business_for(resource: user)
    end

    test "returns nil if org is not part of EMU business" do
      business = create :business, skip_enterprise_managed_business: true
      org = create :organization, business: business
      refute org.enterprise_managed_user_enabled?
      assert_nil Business.enterprise_managed_business_for(resource: org)
    end

    test "returns nil if repo is not owned by EMU" do
      user = create :user, skip_enterprise_managed_user: true
      repo = create :repository, owner: user, force_user_owned: true
      refute repo.enterprise_managed_user_enabled?
      assert_nil Business.enterprise_managed_business_for(resource: repo)
    end

    test "returns nil if repo is not owned by EMU org" do
      business = create :business, skip_enterprise_managed_business: true
      org = create :organization, business: business
      repo = create :repository, owner: org
      refute repo.enterprise_managed_user_enabled?
      assert_nil Business.enterprise_managed_business_for(resource: repo)
    end

    test "returns business for EMU" do
      business = create :business, :enterprise_managed
      emu = create :emu, business: business
      assert emu.is_enterprise_managed?
      assert_equal business, Business.enterprise_managed_business_for(resource: emu)
    end

    test "returns business for EMU org" do
      business = create :business, :enterprise_managed
      emu = create :emu, business: business
      emu_org = create :organization, business: business, admin: emu
      assert emu_org.enterprise_managed_user_enabled?
      assert_equal business, Business.enterprise_managed_business_for(resource: emu_org)
    end

    test "returns business for repo owned by EMU" do
      business = create :business, :enterprise_managed
      emu = create :emu, business: business
      repo = create :repository, owner: emu, force_user_owned: true
      assert repo.enterprise_managed_user_enabled?
      assert_equal business, Business.enterprise_managed_business_for(resource: repo)
    end

    test "returns business for repo owned by EMU org" do
      business = create :business, :enterprise_managed
      emu = create :emu, business: business
      emu_org = create :organization, business: business, admin: emu
      repo = create :repository, owner: emu_org
      assert repo.enterprise_managed_user_enabled?
      assert_equal business, Business.enterprise_managed_business_for(resource: repo)
    end
  end

  context "#scim_provider_type" do
    test "returns nil when user_agent is nil" do
      assert_nil Business.scim_provider_type(user_agent: nil)
      assert_nil Business.scim_provider_type
    end

    test "returns :azure_ad for AAD user agent" do
      assert_equal :azure_ad, Business.scim_provider_type(user_agent: "Microsoft Azure AD SCIM provisioning 1.0.0")

      GitHub.stubs(:context).returns({ user_agent:  "Microsoft Azure AD SCIM provisioning 1.2.3" })
      assert_equal :azure_ad, Business.scim_provider_type
    end

    test "returns :okta for Okta user agent" do
      assert_equal :okta, Business.scim_provider_type(user_agent: "Okta SCIM client 1.0.0")

      GitHub.stubs(:context).returns({ user_agent: "Okta SCIM client 1.2.3" })
      assert_equal :okta, Business.scim_provider_type
    end

    test "returns :ping_federate for Ping user agent" do
      assert_equal :ping_federate, Business.scim_provider_type(user_agent: "Apache-HttpClient 1.0.0")

      GitHub.stubs(:context).returns({ user_agent: "Apache-HttpClient 1.2.3" })
      assert_equal :ping_federate, Business.scim_provider_type
    end

    test "returns :open_scim when unknown user agent" do
      assert_equal :open_scim, Business.scim_provider_type(user_agent: "random")

      GitHub.stubs(:context).returns({ user_agent: "random" })
      assert_equal :open_scim, Business.scim_provider_type
    end
  end

  context "#guest_collaborator_ids" do
    test "return guest_collaborator_ids under emu business" do
      org = create :organization, business: @emu_business, admin: @first_admin
      guest_collaborator = create(:emu, :guest_collaborator, business: @emu_business)

      refute_includes @emu_business.guest_collaborator_ids, guest_collaborator.id

      org.add_member(guest_collaborator)

      assert_same_elements @emu_business.reload.guest_collaborator_ids, [guest_collaborator.id]
    end
  end
end unless GitHub.single_business_environment?
