# typed: true
# frozen_string_literal: true

class Organization
  # Creates an Organization for the current user,
  # optionally setting up billing for paid Organization.
  #
  # See also OrganizationController#create
  class Creator
    include TradeControlsHelper

    class Error < StandardError; end

    # Result from the Organization creation
    class Result
      attr_accessor :error_message, :coupon
      attr_reader :organization
      def initialize(success, organization, error_message: nil)
        @success = success
        @organization = organization
        @error_message = error_message
      end

      def success?
        @success
      end
    end

    EMU_NO_SSO_SETUP_ERROR = "You must configure SAML/OIDC single sign-on for an enterprise managed through an IdP before you can create an organization"

    def self.perform(current_user, plan, org_hash, payment_details: {}, coupon_code: nil, business_owned: false, business: nil, terms_of_service: nil, trade_screening_info: nil)
      new(
        current_user,
        plan,
        org_hash,
        payment_details: payment_details,
        coupon_code: coupon_code,
        business_owned: business_owned,
        business: business,
        terms_of_service: terms_of_service,
        trade_screening_info: trade_screening_info
      ).perform
    end

    # Create the Creator
    #
    def initialize(current_user, plan, org_hash, payment_details: {}, coupon_code: nil, business_owned: false, business: nil, terms_of_service: nil, trade_screening_info: nil)
      @current_user = current_user
      @plan = plan
      @profile_name = org_hash[:profile_name]
      @org_hash = org_hash.except(:profile_name).merge(plan: plan)
      @payment_details = payment_details
      @coupon_code = coupon_code
      @business_owned = business_owned
      @business = GitHub.single_business_environment? ? GitHub.global_business : business
      @terms_of_service = terms_of_service&.capitalize
      @trade_screening_info = trade_screening_info

      if GitHub.organization_namespacing_enabled?
        @org_hash.merge!({
          "force_enterprise_managed" => true,
          "login_suffix" => @business.shortcode,
          "business_id" => @business.id
        }) if @business.present?
      end
    end

    attr_accessor :organization
    # The current User creating the Organization - must not be nil
    attr_reader :current_user
    # Plan object for this Organization - should not be nil
    attr_accessor :plan
    # Hash of attributes for the new Org
    attr_reader :org_hash
    # Optional String coupon code
    attr_reader :coupon_code
    # Optional Hash of parsed params for payment - see also BillingSettingsHelper
    attr_reader :payment_details
    # Optional Boolean business owned
    attr_reader :business_owned
    # Optional String representing the profile name
    attr_reader :profile_name
    # Optional Business to add this newly created Organization to
    attr_reader :business
    # Optional Terms of Service type to create the Organization under if business_owned
    attr_reader :terms_of_service
    # Optional Hash of trade screening information to be saved against the organization
    attr_reader :trade_screening_info

    # Do the actual Org creation
    #
    # Returns a Creator::Result object
    def perform
      # Push the current user as the actor early on in the creation process
      GitHub.context.push(actor: current_user)
      Audit.context.push(actor: current_user)

      self.organization = Organization.new(org_hash)

      unless current_user.present?
        return Result.new(false, organization, error_message: "Admin user could not be found")
      end

      has_sdn_restrictions = if [GitHub::Plan.free.name, GitHub::Plan::TEAM_FREE_PLAN_NAME].include?(plan.name)
        current_user.has_commercial_interaction_restriction?(feature_type: :free_org_creation)
      else
        current_user.has_commercial_interaction_restriction?
      end

      if has_sdn_restrictions
        message = trade_screening_restriction_notice(target: current_user)
        return Result.new(false, organization, error_message: message)
      end

      organization.creator = current_user
      organization.associated_business_on_creation = business

      if business && business.enterprise_managed_user_enabled? && !business.external_provider_enabled?
        return Result.new(false, organization, error_message: EMU_NO_SSO_SETUP_ERROR)
      end

      if business && business.spammy?
        return Result.new \
          false,
          organization,
          error_message: "This enterprise has been flagged and cannot create new organizations."
      end

      can_create_organization = business && current_user && Authz.domain.check_allowed(current_user, :create_enterprise_organizations, business)
      if business && !can_create_organization && !GitHub.org_creation_enabled?
        return Result.new(false, organization, error_message: "User does not have permission to create organizations in this enterprise")
      end

      if business && org_hash[:admin_logins] && org_hash[:admin_logins].any?
        two_factor_authentication_enabled =  business.two_factor_requirement_enabled?
        proposed_admins = org_hash[:admin_logins].map { |login| ::User.find_by(login: login) }.compact
        proposed_admins.each do |admin|
          if two_factor_authentication_enabled && !admin.two_factor_authentication_enabled?
            return Result.new \
              false,
              organization,
              error_message: "Not all provided administrators meet the two-factor authentication requirement."
          end

          if business.enterprise_managed? && business != admin.enterprise_managed_business
            return Result.new \
              false,
              organization,
              error_message: "Not all provided administrators are part of the externally managed enterprise."
          end

          unless business.meets_sso_requirements?(admin)
            return Result.new \
              false,
              organization,
              error_message: "#{admin.display_login} must satisfy the SSO requirements for this enterprise."
          end
        end
      end

      if business_owned && org_hash[:company_name].blank?
        return Result.new(false, organization, error_message: "#{terms_of_service} Terms of Service require a business name")
      end

      if business_owned && !Company.valid_name?(org_hash[:company_name])
        return Result.new(false, organization, error_message: "Company name is invalid")
      end

      if !current_user.bot? && current_user.should_verify_email?
        return Result.new(false, organization, error_message: "You must have a verified email address to create an organization")
      end

      if organization.admins.blank? && current_user.bot?
        return Result.new(false, organization, error_message: "Must provide at least one valid owner")
      end

      if organization.admins.blank?
        organization.admins = [current_user]
      end

      if coupon_code.present?
        if !organization.validate_coupon(coupon_code)
          # NB - this is stupid but needs to happen because of the Transaction
          # creation side effect in .redeem_coupon
          organization.coupon = coupon_code
          error_message = organization.errors.full_messages.first
          return Result.new(false, organization, error_message: error_message)
        else
          coupon = Coupon.find_by_code(coupon_code)
        end
      end

      organization.seats = \
        if plan.per_seat?
          organization.default_seats(new_plan: plan)
        else
          0
        end

      organization.show_onboarding_tasks = !business&.enterprise_managed_user_enabled?

      # Skip the automatic external subscription update - for synchronous payments,
      # the first synchronization must be run from CollectPaymentOnUpgradeJob.
      organization.skip_update_external_subscription = true

      # Store screening external_uuid for logging when organization creation is rolled back
      @screening_id = T.let(nil, T.nilable(String))

      saved_successfully = begin
        if business
          begin
            business.ensure_sufficient_licenses_for_organization!(organization)
          rescue Business::CannotAddOrganizationError => e
            handle_error(message: e.message)
          end
        end

        Organization.transaction do
          update_organization_login
          set_profile_name
          save_organization
          update_terms_of_service
          add_to_global_business
          @screening_id = handle_account_screening
          org_has_restrictions = handle_organization_restrictions
          redeem_coupon(coupon, org_has_restrictions)
          handle_billing(org_has_restrictions)
          handle_business
          set_default_configurations
          save_organization
          GitHub.dogstats.increment("organization", tags: ["action:create", "valid:true"])
          true
        end
      rescue Error
        GitHub.dogstats.increment("organization", tags: ["action:create", "valid:false"])
        false
      end

      if saved_successfully
        organization.reload

        organization.set_beta_features_for_plan
        organization.setup_security_products_on_creation(@current_user)
        synchronize_plan_subscription
        OrgCreationJob.perform_later(current_user.id, organization.id)
        Billing::EnterpriseCloudTrialCheckJob.perform_later(organization.id) if business

        if !GitHub.enterprise? && !business && plan.name == GitHub::Plan.business.name && @current_user.feature_enabled?(:onboard_new_team_plan_to_billing_platform)
          # Onboard new team plan customers to billing platform
          GitHub.dogstats.increment("billing_platform.onboard_new_team_organization.count")
          organization.customer.onboard_to_all_billing_platform_products
        end

        if !GitHub.enterprise? && !business && [GitHub::Plan.free.name, GitHub::Plan::TEAM_FREE_PLAN_NAME].include?(plan.name) && @current_user.feature_enabled?(:onboard_new_free_plan_to_billing_platform)
          customer = GitHub::Billing.create_customer(organization, {}, actor: @current_user)
          # Onboard new free plan customers to billing platform
          if organization.customer.present?
            GitHub.dogstats.increment("billing_platform.onboard_new_free_organization.count")
            organization.customer.onboard_to_all_billing_platform_products
          end
        end

        if trade_screening_info.present? && standard_terms_of_service?
          link_success = organization.link_billing_contact actor: current_user
          unless link_success
            GitHub.dogstats.increment("sdn.link_billing_info.failed", tags: ["flow:STOS_ORGANIZATION_SIGNUP"])
          end
        end
      else

        # Org creation failed. Still need to provide a valid Organization object to the caller
        self.organization = Organization.new(org_hash)
        organization.plan = plan.name
        organization.valid?

        error_context = {
          error: "Organization was rolled back for account screening profile with external ID: #{@screening_id}",
          metadata: nil,
        }

        GitHub.context.push(error_context)
        Audit.context.push(error_context)
        GitHub.logger.error("organization_creation.failed",
          "gh.organization_creation.external_uuid": @screening_id,
          "error.message": "Organization was rolled back: #{error_messages.join(", ")}",
        )
      end

      result = Result.new(
        saved_successfully,
        organization,
        error_message: error_messages.join(", ")
      )
      result.coupon = coupon
      result
    end

    private

    def save_organization
      unless organization.save
        handle_error(message: organization.errors.full_messages)
      end
    end

    def update_organization_login
      return if !GitHub.organization_namespacing_enabled? || organization.login.blank?

      suffix = org_hash["login_suffix"] if org_hash["force_enterprise_managed"]
      organization.login = User.standardize_login(organization.login, suffix: suffix)
    end

    def set_profile_name
      if profile_name.present? && profile_name != organization.login
        organization.build_profile(name: profile_name)
        unless organization.profile.valid?
          handle_error(message: organization.profile.errors.full_messages)
        end
      end
    end

    def update_terms_of_service
      return unless business_owned

      organization.terms_of_service.update(
        type: terms_of_service,
        actor: current_user,
        company_name: org_hash[:company_name],
      )
    end

    def add_to_global_business
      return unless GitHub.single_business_environment? && GitHub.global_business

      GitHub.global_business.add_organization(organization)
    end

    def handle_account_screening
      return if trade_screening_info.blank? || standard_terms_of_service?

      AccountScreeningProfile.new(trade_screening_info.merge(owner: organization)).tap do |asp|
        asp.assign_attributes(metadata: asp.metadata.merge({ screening_context: "new_org_creation" }))
        if asp.save
          organization.perform_live_sdn_screening
          asp.external_uuid
        else
          handle_account_screening_error(asp)
        end
      end
    end

    def handle_account_screening_error(asp)
      error_messages.push("We were unable to process your payment information. Please try again.")
      error_context = {
        error: "Unable to save account screening profile due to: #{asp.errors.full_messages.to_sentence}",
        metadata: nil,
      }

      GitHub.context.push(error_context)
      Audit.context.push(error_context)
      revert_account_screening_and_abilities

      raise Error
    end

    def handle_organization_restrictions
      return false unless organization.has_commercial_interaction_restriction?

      organization.seats = 0
      organization.plan = "free"
      true
    end

    def redeem_coupon(coupon, org_has_restrictions)
      return if !coupon || org_has_restrictions

      organization.redeem_coupon(coupon, instrument: false, actor: current_user)
    end

    def handle_billing(org_has_restrictions)
      return if !organization.payment_amount.positive? || org_has_restrictions

      billing_result = GitHub::Billing.signup(organization,
        plan.name,
        actor: current_user,
        payment_details: payment_details
      )

      context = {
        note: "Added #{organization.friendly_payment_method_name} during creation",
        org: organization,
      }

      GitHub.context.push(context)
      Audit.context.push(context)

      return if billing_result.success?

      handle_error(
        message: billing_result.error_message.to_s,
        metadata: billing_result.error_message.try(:metadata),
      )
    end

    def handle_business
      return unless business

      business.add_organization(organization, new_organization: true, actor: current_user, ensure_sufficient_licenses: false)
      return if business.trial?

      plan = GitHub.enterprise? ? :enterprise : :business_plus
      organization.update(plan: plan)
    end

    def set_default_configurations
      return if business_owned

      organization.set_fine_grained_personal_access_token_expiration_limit(
        actor: User.ghost,
        expiration: Configurable::PersonalAccessTokenExpirationLimit::DEFAULT_FINE_GRAINED_PAT_EXPIRATION_LIMIT
      )
    end

    def handle_error(message: nil, metadata: nil)
      error_messages.push(message)
      error_context = {
        error: message,
        metadata: metadata,
      }

      GitHub.context.push(error_context)
      Audit.context.push(error_context)
      revert_account_screening_and_abilities

      raise Error
    end

    def error_messages
      @error_messages ||= []
    end

    def revert_account_screening_and_abilities
      AccountScreeningProfile.find_by(external_uuid: @screening_id)&.destroy if @screening_id.present?
      Ability.clear(organization, async: true)
    end

    def standard_terms_of_service?
      terms_of_service&.downcase == "standard"
    end

    def synchronize_plan_subscription
      if organization.collect_payment_immediately_for_plan_or_seat_changes?
        CollectPaymentForUpgradeJob.perform_later(billable_entity: organization, actor: @current_user,
          old_plan_name: GitHub::Plan.free.name, old_seat_count: 0, notify_on_failure: true)
      else
        organization.plan_subscription&.synchronize_later
      end
    end
  end
end
