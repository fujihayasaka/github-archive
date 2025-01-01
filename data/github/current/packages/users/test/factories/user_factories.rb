# typed: true
# frozen_string_literal: true

GOOD_USER_PASSWORD = "ThisIsASecurePassword"
COMPROMISED_USER_PASSWORD = "password12"
COMPROMISED_USER_PASSWORD_K_ANON = "password839976"
DICTIONARY_USER_PASSWORD = "Apples123"

FactoryBot.define do
  T.bind(self, T.untyped)

  # trait to setup EMU user, with a business if not passed in.  This trait is reused for an EMU and user when CI is
  # executed with TEST_WITH_ALL_EMUS flag set
  trait :enterprise_managed_user do
    USER_ATTRIBUTES_TO_UPDATE = %i[email login spammy]

    transient do
      provider_type { :saml }
      skip_identity { false }
      already_provisioned_not_mt_user { persisted? && business_id == 0 }
      roles { Platform::Provisioning::RoleReconciler::USER_ROLE[0] }
    end

    initialize_with do
      if skip_enterprise_managed_user || is_staff
        new(attributes)
      else
        # factory was called from emu factory business was either passed in or it needs to be created
        enterprise = if create_enterprise_managed_user
          raise "EMU users cannot be created in the GHES environment" if GitHub.enterprise?

          business || create(:business, :enterprise_managed)

        # In the cases below the user is created from a user factory only
        # Get business when running in multi-tenant mode.
        elsif GitHub.multi_tenant_enterprise?
          # get the current tenant, query or create a new business
          business || GitHub::CurrentTenant.get || Business.enterprise_managed.first || create(:business, :enterprise_managed)

        # executed in test with all emus mode
        # the check for test with all emus is not necessary but it is here just as a precaution
        elsif TestEnv.test_with_all_emus?
          # query or create a new business
          business || Business.enterprise_managed.first || create(:business, :enterprise_managed)
        end

        # since business was specified the factory was executed in EMU mode
        # which includes the multi-tenant and executing tests with all emus
        if enterprise
          # Business must be enterprise managed, if it is not raise an error
          raise "EMU users must be created with a valid EMU business with shortcode.  Use :enterprise_managed trait to create a business for user login #{attributes[:login]}" unless enterprise.shortcode

          # in multi-tenant mode set the current tenant to the business
          # so the user can be created correctly
          GitHub::CurrentTenant.set(enterprise) if GitHub.multi_tenant_enterprise?

          # Fixes login too long issues when running in Proxima mode
          login = attributes[:login].to_s # just in case this is a symbol
          if "#{login}_#{enterprise.shortcode}".length > 39
            len = 37 - enterprise.shortcode.length
            login = login[0..len]
          end

          update_attributes = attributes.reject { |k, _v| USER_ATTRIBUTES_TO_UPDATE.include?(k) }

          # override the attributes to ensure correct login and email values
          # when creating ane EMU user
          update_attributes[:login] = User.standardize_login(login, suffix: enterprise.shortcode)
          update_attributes[:email] = User::EnterpriseManagedDependency.add_shortcode(attributes[:email], enterprise)
          update_attributes[:business_id] = enterprise.id if GitHub.multi_tenant_enterprise?
          # not allowing spammy users in EMU mode
          update_attributes[:spammy] = false

          new(update_attributes)
        else
          new(attributes)
        end
      end
    end

    after(:build) do |user, evaluator|
      next if evaluator.already_provisioned_not_mt_user
      next if evaluator.skip_enterprise_managed_user
      next if evaluator.is_staff

      # we are creating an EMU so we need to force the user to be enterprise managed
      user.force_enterprise_managed = true if user.is_enterprise_managed? && !user.persisted?
    end

    after(:create) do |user, evaluator|
      extend GitHub::UserTestHelpers
      next if evaluator.already_provisioned_not_mt_user
      if evaluator.skip_enterprise_managed_user || evaluator.is_staff
        if GitHub.multi_tenant_enterprise?
          GitHub::CurrentTenant.restore_tenant do
            # Reset login without a shortcode
            user.login = user.display_login
            user.save
          end
        end

        next
      end

      business = create_external_identity_for_emu(
        user,
        evaluator.business,
        provider_type: evaluator.provider_type,
        skip_identity: evaluator.skip_identity,
        profile_name: evaluator.profile_name,
        roles: evaluator.roles,
      )

      next unless business

      # During all features CI runs the idp_cap_web_configurable_allowed flag is enabled.
      # If a business has IdP CAP enabled with the ff on, and if the web configurable is not also enabled
      # a bunch of the tests start failing when checking if the external conditional access policy is applicable,
      # it will start always returning false.
      # By turning this on the applicable check will return true, which is the same state that is run during
      # the default CI run.
      #
      # Rather than disabling the flag in all the IdP CAP tests, we can just enable it here and it will only
      # affect OIDC businsses and it only applies when IdP CAP is also enabled.
      #
      # This way, the default CI run will test businesses that are "new" to IdP CAP (i.e. the ff is off)
      # and the all features runs will test businesses that have already enabled IdP CAP (i.e. the ff is on)
      # and are now turning the configurable on for web.
      if business.feature_enabled?(:idp_cap_web_configurable_allowed) && business.oidc_enabled?
        business.config.enable(Configurable::IdpIpAllowlistForWeb::KEY, business.find_first_emu_owner)
      end

      # Ensure EMU is a member of an org in the business in all EMUs mode so that
      # user will have access to all internal repos across all the orgs in the
      # business
      if TestEnv.test_with_all_emus? && !evaluator.create_enterprise_managed_user && !evaluator.skip_organization_add
        org = business.organizations.first || create(:organization, business: business, admin: user)
        # if there are no admins, we're attempting to create this user as part of creating the org
        org.add_member(user) if org.admins.any?
      end

      if GitHub.multi_tenant_enterprise? && !TestEnv.test_with_all_emus? && evaluator.remove_tenant_context
        GitHub::CurrentTenant.remove
      end
    end
  end

  # Adding enterprise_managed_user trait to be called when the TEST_WITH_ALL_EMUS flag is set
  factory :user, traits: TestEnv.test_with_all_emus? ? [:enterprise_managed_user] : [] do
    suppress_instrumentation

    login { name || "user-#{SecureRandom.hex(12)}" }
    password { GitHub.default_password }
    email { Sham.email }
    require_email_verification { false }
    billing_attempts { 0 }

    transient do
      create_enterprise_managed_user { false }
      skip_identity { false }
      skip_enterprise_managed_user { false }
      name { nil } # FIXME update all callers to use `login:` instead of `name:`
      is_staff { false }
      business { nil }
      # When running tests in MT mode (TestEnv.test_with_all_emus? will be set to true) we do not
      # want to remove the tenant if one was laredy set.  We also do not want to get a default business
      # but either get it from evaluator.business or from a GitHub::CurrentTenant.get
      remove_tenant_context { TestEnv.test_with_all_emus? && GitHub::CurrentTenant.get ? false : true }
      skip_organization_add { false }
    end

    trait :staff do
      transient do
        is_staff { true }
      end

      after(:create) do |user, _|
        become_github_staff(user)
      end
    end

    trait :employee do
      transient do
        is_staff { true }
      end

      after(:create) do |user, _|
        add_as_employee(user)
      end
    end

    trait :contractor do
      after(:create) do |user, _|
        EnterpriseAttestation.set(user.id, contractor: true)
      end
    end

    factory :employee, traits: [:employee]

    factory :old_user do
      created_at { 10.days.ago }
    end

    factory :staff_admin_user do
      transient do
        stafftools_roles { nil }
        skip_metadata_creation { false }
        is_staff { true }
      end

      after(:create) do |user, evaluator|
        become_github_staff(user)

        if evaluator.stafftools_roles
          evaluator.stafftools_roles.each do |role|
            # find_or_initialize_by is not allowed :\
            found_role = StafftoolsRole.find_by(name: role)
            found_role ||= StafftoolsRole.new(name: role)

            user.stafftools_roles << found_role
          end
        end

        unless evaluator.skip_metadata_creation
          if metadata = user.user_metadata
            metadata.update(is_staff: true)
          else
            create(:user_metadata, user: user, is_staff: true)
          end
        end
      end
    end

    factory :user_with_compromised_password do
      after(:create) do |user|
        user.update!(password: COMPROMISED_USER_PASSWORD)
      end

      factory :blocked_weak_password_user do
        after(:create) do |user|
          check_result = build(:password_check_metadata_with_blocking_timestamp)
          user.update_attribute(:weak_password_check_result, check_result.to_binary_s)
        end
      end
    end

    factory :paid_user, traits: [:paid_plan] do
      # Set a future billed on date by default to prevent beneficiary? from returning true
      billed_on { GitHub::Billing.today + 30.days }
    end

    factory :dev_user do
      transient do
        is_staff { true }
      end

      gh_role { "dev" }
    end

    factory :spammy_user do
      spammy { true }
    end

    factory :hammy_user do
      spammy_reason { "Not spammy" }
    end

    factory :suspended_user do
      suspended_at { Time.now }
    end

    factory :suspended_sponsorable do
      suspended_at { Time.now }

      after(:create) do |user|
        create(:sponsors_listing, sponsorable: user)
      end
    end

    factory :hubber_user, traits: [:paid_plan] do
      transient do
        is_staff { true }
      end

      gh_role { "developer" }
    end

    factory :biztools_user do
      transient do
        is_staff { true }
      end

      gh_role { "biz" }
    end

    trait :paid_plan do
      plan { GitHub::Plan.pro }
    end

    trait :with_lfs_data_packs do
      transient do
        data_packs_count { 1 }
      end

      after(:create) do |user, evaluator|
        quantity = evaluator.data_packs_count
        Asset::Status.create(owner: user, asset_packs: quantity, data_packs: quantity)
      end
    end

    trait :fully_trade_restricted do
      after(:build) { |u| u.build_trade_controls_restriction(type: :full) }
      after(:create) { |u| u.create_trade_controls_restriction(type: :full) }
    end

    trait :partially_trade_restricted do
      after(:build) { |u| u.build_trade_controls_restriction(type: :partial) }
      after(:create) { |u| u.create_trade_controls_restriction(type: :partial) }
    end

    trait :trade_unrestricted do
      after(:build) { |u| u.build_trade_controls_restriction }
      after(:create) { |u| u.create_trade_controls_restriction }
    end

    trait :sanctioned_email_address do
      email { "test@test.sy" }
    end

    trait :in_dunning do
      billing_attempts { 1 }
    end

    trait :verified do
      after(:create) do |user|
        user.emails.first.verify!
      end
    end

    trait :with_profile do
      transient do
        profile_name { "Mona #{SecureRandom.hex(8)}" }
      end
      after(:create) do |user, evaluator|
        create(:profile, user: user, name: evaluator.profile_name, email: user.email)
      end
    end

    factory :verified_user, traits: [:verified]

    trait :show_private_contributions do
      after(:create) do |user|
        user.profile_settings.show_private_contribution_count = true
      end
    end

    factory :external_auth_user do
      email { nil }
    end

    factory :two_factor_credential_user, traits: [:two_factor_enabled]

    trait :two_factor_enabled do
      two_factor_credential
      after(:create) do |user|
        create(:totp_app_registration, user: user, encrypted_otp_secret: TwoFactorCredential.generate_secret)
      end
    end

    factory :two_factor_credential_and_verified_user, traits: [:two_factor_enabled, :verified]

    trait :with_signed_marketplace_agreement do
      after :create do |user, _evaluator|
        agreement = Marketplace::Agreement.first || create(:marketplace_agreement)
        create(:marketplace_agreement_signature, signatory: user, agreement: agreement)
      end
    end

    # Stuff for handling how the customer account gets attached
    transient do
      customer_account_factory { nil }
    end

    after(:create) do |user, evaluator|
      if evaluator.customer_account_factory
        attributes = { user: user }
        if user.customer
          attributes.merge(bill_cycle: user.customer.bill_cycle_day)
          user.customer.destroy
          user.reload
        end
        user.customer_account = create(evaluator.customer_account_factory, attributes)
        user.save
        user.reload
      end

      if user.customer
        bcd = user.customer.bill_cycle_day
        if (bcd.nil? || bcd.zero?) && user.billed_on
          user.customer.update!(bill_cycle_day: user.billed_on.day)
        end
      end

      user.reload
    end

    factory :credit_card_user do
      billing_type { "card" }
      customer_account_factory { :credit_card_customer_account }
    end

    factory :no_credit_card_user do
      billing_type { "card" }
      customer_account_factory { :no_credit_card_customer_account }
    end

    factory :paypal_user do
      billing_type { "card" }
      customer_account_factory { :paypal_customer_account }
    end

    factory :india_based_credit_card_user do
      billing_type { "card" }
      customer_account_factory { :india_based_credit_card_customer_account }
    end

    trait :manual_dunning do
      plan_subscription { create :billing_plan_subscription, :zuora, balance_in_cents: 7_00 }
      manual_dunning_period
    end

    trait :disabled_by_india_rbi do
      customer_account_factory { :disabled_by_india_rbi_customer_account }
    end

    trait :established_sign_in_history do
      after(:create) do |user, _evaluator|
        Timecop.travel(1.month.ago) do
          create(:authentication_record, user: user)
        end
      end
    end

    trait :zuora do
      customer_account { create :customer_account, :zuora }
    end

    trait :zuora_paypal do
      customer_account { create :customer_account, :zuora_paypal }
    end

    trait :invoiced do
      billing_type { "invoice" }
    end

    factory :user_with_payment_identifier do
      transient do
        unique_number { nil }
        paypal_email { nil }
      end

      after(:create) do |user, evaluator|
        customer = create(:customer_account, user: user).customer
        customer.payment_method.update unique_number_identifier: evaluator.unique_number, paypal_email: evaluator.paypal_email
        user.reload
      end
    end

    trait :without_analytics_tracking_id do
      before(:create) do |user|
        user.stubs(:set_analytics_tracking_id)
      end
    end

    trait :with_marketplace_order_previews do
      transient do
        previews_count { 1 }
      end

      after(:create) do |user, evaluator|
        create_list(:marketplace_order_preview, evaluator.previews_count, user: user)
      end
    end

    trait :sponsorable do
      transient do
        country_of_residence { "US" }
        sponsors_tier_count { 1 }
      end

      login { "sponsorable-#{SecureRandom.hex(9)}" }

      after(:create) do |user, evaluator|
        user.primary_user_email.verify!
        create(:sponsors_listing, :approved, sponsorable: user,
          country_of_residence: evaluator.country_of_residence,
          tier_count: evaluator.sponsors_tier_count)
      end
    end

    trait :sponsors_old_enough_to_not_get_auto_banned do
      created_at { (SponsorsListing::ACCOUNT_AGE_CUTOFF_FOR_AUTO_BAN + 1.day).ago }
    end

    trait :sponsors_auto_approvable do
      time_zone_name { "Pacific Time (US & Canada)" }
      created_at { 1.year.ago }

      after(:create) do |user, _evaluator|
        user.update!(profile_bio: "We the best code")
        create(:sponsors_listing, :pending_approval, full_description: "hewwo", sponsorable: user)
        create(:sponsors_tier, :published, sponsors_listing: user.sponsors_listing)
        create(:stripe_connect_account, :w8_or_w9_verified, sponsors_listing: user.sponsors_listing)

        if !user.has_saved_trade_screening_record?
          create(:account_screening_profile, msft_trade_screening_status: :no_hit, owner: user)
        end
      end
    end

    trait :sponsors_publishable do
      time_zone_name { "Pacific Time (US & Canada)" }
      created_at { 1.year.ago }

      after(:create) do |user, _evaluator|
        user.update!(profile_bio: "Ready to be sponsored!")
        create(:sponsors_listing, :draft, full_description: "$$$", sponsorable: user)
        create(:stripe_connect_account, :w8_or_w9_verified, sponsors_listing: user.sponsors_listing)

        if !user.has_saved_trade_screening_record?
          create(:account_screening_profile, msft_trade_screening_status: :no_hit, owner: user)
        end

        if !user.two_factor_authentication_enabled?
          user.update!(two_factor_credential: create(:two_factor_credential))
        end
      end
    end

    trait :sponsors_program_member do
      transient do
        country_of_residence { "US" }
      end

      after(:create) do |user, evaluator|
        user.primary_user_email.verify!
        create(:sponsors_listing, :draft, sponsorable: user,
          country_of_residence: evaluator.country_of_residence)
      end
    end

    trait :with_sponsors_patreon_user do
      after(:create) do |user|
        create(:sponsors_patreon_user, user: user)
      end
    end

    trait :with_prerelease_agreement do
      after(:create) do |user|
        create(:prerelease_program_member, member: user)
      end
    end

    trait :with_valid_contact_for_billing do
      after(:create) do |user|
        create(:account_screening_profile, :no_hit, owner: user)
        user.reload
      end
    end

    trait :with_trade_screening_record do
      after(:create) do |user|
        create(:account_screening_profile, owner: user)
      end
    end

    trait :with_validated_address_trade_screening_record do
      after(:create) do |user|
        create(:account_screening_profile, owner: user, billing_address_validated_at: Time.now.utc)
      end
    end

    trait :with_no_hit_sdn_screening do
      after(:create) do |user|
        create(:account_screening_profile, :no_hit, owner: user)
      end
    end

    trait :with_sdn_screening_restriction do
      after(:create) do |user|
        create(:account_screening_profile, owner: user, msft_trade_screening_status: :lic_r)
      end
    end

    # Removing enterprise_managed_user trait to be called when the TEST_WITH_ALL_EMUS flag is set, since
    # it is already attached to a user and emu inherits from a user
    factory :emu, traits: TestEnv.test_with_all_emus? ? [] : [:enterprise_managed_user] do
      transient do
        create_enterprise_managed_user { true }
        roles { Platform::Provisioning::RoleReconciler::USER_ROLE[0] }
      end

      trait :okta do
        after(:create) do |user, evaluator|
          if evaluator.provider_type == :saml
            # since this runs after the above "after(:create)", the user will already have a business_user_account
            business = evaluator.business || user.business_user_accounts.first.business
            business.saml_provider.issuer = "http://www.okta.com/hyk4alt44ls5GoKdV3d8"
          end
        end
      end

      trait :guest_collaborator do
        after(:create) do |user|
          user.external_identities.first.update!(guest_collaborator: true)
        end
      end

      trait :owner do
        transient do
          roles { Platform::Provisioning::RoleReconciler::ENTERPRISE_OWNER_ROLE[0] }
        end

        after(:create) do |user, evaluator|
          # since this runs after the above "after(:create)", the user will already have a business_user_account
          business = evaluator.business || user.business_user_accounts.first.business
          business.add_owner(user, actor: nil)
        end
      end

      trait :scim_provisioning_enabled do
        after(:create) do |user, evaluator|
          if evaluator.provider_type == :saml
            # since this runs after the above "after(:create)", the user will already have a business_user_account
            business = evaluator.business || user.business_user_accounts.first.business
            business.saml_provider.update(scim_provisioning_state: "scim_provisioning_state_enabled")
          end
        end
      end
    end

    factory :ghes_scim_user do
      transient do
        organization { nil }
        roles { Platform::Provisioning::RoleReconciler::USER_ROLE[0] }
      end

      after(:create) do |user, evaluator|
        business = evaluator.business || create(:global_business)

        if business.saml_provider.nil?
          provider = create :business_saml_provider, :azuread_issuer, business: business
          # When used in GHES mode set the SCIM state to "enabled"
          provider.update(scim_provisioning_state: "scim_provisioning_state_enabled") if GitHub.single_business_environment?
        end

        email = user.emails.first
        create(:external_identity, :scim, user: user, provider: business.saml_provider, email: email.email, roles: evaluator.roles, org: nil)

        profile = user.create_profile
        profile.email = email.email
        profile.name = user.external_identities.first&.display_name || "Mona #{SecureRandom.hex(8)}"
        profile.save!

        if evaluator.organization.present?
          org = evaluator.organization
          business.add_organization org
          org.reload # need to ensure the org is flagged as enterprise managed
          org.add_member(user)
          org.reload
        end
      end

      trait :okta do
        after(:create) do |user, evaluator|
          # since this runs after the above "after(:create)", the user will already have a business_user_account
          business = evaluator.business || user.business_user_accounts.first.business
          business.saml_provider.issuer = "http://www.okta.com/hyk4alt44ls5GoKdV3d8"
        end
      end

      trait :admin do
        transient do
          roles { Platform::Provisioning::RoleReconciler::ENTERPRISE_OWNER_ROLE[0] }
        end

        after(:create) do |user, evaluator|
          user.grant_site_admin_access("saml/scim single sign-on administrator promotion")

          business = evaluator.business || create(:global_business)
          business.add_owner(user, actor: nil, send_email_notification: false)
        end
      end

      trait :scim do
        after(:create) do |user, _evaluator|
          provider = user.external_identities.first.provider
          provider.provisioning_enabled = true
          provider.scim_provisioning_state = "scim_provisioning_state_enabled"
          provider.save!
        end
      end
    end

    factory :sponsorable_user do
      transient do
        listing_traits { [:approved] }
        country_of_residence { "US" }
        billing_country { "US" }
        sponsors_tier_count { 1 }
      end
      after(:create) do |user, evaluator|
        user.primary_user_email.verify!
        create(:sponsors_listing, *evaluator.listing_traits, sponsorable: user,
          country_of_residence: evaluator.country_of_residence,
          billing_country: evaluator.billing_country,
          tier_count: evaluator.sponsors_tier_count)
      end

      trait :trusted do
        created_at { (Sponsors::TrustLevel::NEUTRAL_ACCOUNT_AGE_THRESHOLD + 1.day).ago }
      end

      trait :neutral_trust do
        created_at { (Sponsors::TrustLevel::UNTRUSTED_ACCOUNT_AGE_THRESHOLD + 1.day).ago }
      end

      trait :untrusted do
        created_at { (Sponsors::TrustLevel::UNTRUSTED_ACCOUNT_AGE_THRESHOLD - 1.day).ago }
      end
    end

    trait :with_codespaces_basic_tier_access do
      after(:create) do |user, _|
        organization = create(:organization, :with_codespaces_basic_tier_access)
        organization.add_member(user)
      end
    end

    trait :private_profile do
      private_profile { true }
    end
  end

  factory :collaborator, class: "User" do
    transient do
      repository { create(:repository) }
      action { :write }
      add_user_to_repo { false }
      remove_tenant_context { TestEnv.test_with_all_emus? && GitHub::CurrentTenant.get ? false : true }
    end

    login { "user-#{SecureRandom.hex(12)}" }
    collaborator { nil }

    initialize_with do
      if attributes[:collaborator]
        attributes[:collaborator]
      else
        user = build(:user, login: attributes[:login])
        new(user.attributes.merge({ email: user.emails.first.email, password: GitHub.default_password }))
      end
    end

    before(:create) do |user, _evaluator|
      user.force_enterprise_managed = true if user.is_enterprise_managed? && !user.persisted?
    end

    # some of the code had to be copied over here since the user factory is called with build none of the creates
    # are executed there
    after(:create) do |user, evaluator|
      extend GitHub::UserTestHelpers
      business = create_external_identity_for_emu(user, evaluator.repository.enterprise_managed_business, profile_name: evaluator.profile_name)

      evaluator.repository.add_member(user, action: evaluator.action)
      evaluator.repository.add_member_without_validation_or_notifications(user, action: evaluator.action) unless evaluator.repository.member?(user)

      next unless business

      # Ensure EMU is a member of an org in the business in all EMUs mode so that
      # user will have access to all internal repos across all the orgs in the
      # business
      if TestEnv.test_with_all_emus? && user.is_enterprise_managed?
        org = business.organizations.first || create(:organization, business: business, admin: user)
        # if there are no admins, we're attempting to create this user as part of creating the org
        org.add_member(user) if org.admins.any?
      end

      if GitHub.multi_tenant_enterprise? && !TestEnv.test_with_all_emus? && evaluator.remove_tenant_context
        GitHub::CurrentTenant.remove
      end
    end

    trait :with_profile do
      transient do
        profile_name { "Mona #{SecureRandom.hex(8)}" }
      end
      after(:create) do |user, evaluator|
        create(:profile, user: user, name: evaluator.profile_name, email: user.email)
      end
    end
  end
end
