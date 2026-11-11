# typed: strict
# frozen_string_literal: true

module Billing
  class CreateCustomer
    sig { returns(::Billing::Types::Account) }
    attr_accessor :target

    sig { returns(Customer) }
    attr_accessor :customer

    sig { returns(PaymentMethod) }
    attr_accessor :payment_method

    sig { returns(T::Hash[Symbol, T.untyped]) }
    attr_accessor :details

    sig { returns(T.nilable(::User)) }
    attr_accessor :actor

    sig { returns(Symbol) }
    attr_accessor :purpose

    class BraintreeCreationError < StandardError; end

    # Public: The batch for self-serve customers used to segment billing/payment runs
    SELF_SERVE_BATCH = "Batch10"

    # Public: Business segments used for reporting
    SELF_SERVE_BUSINESS_SEGMENT = "Self-Serve"
    CORPORATE_SPONSORS_BUSINESS_SEGMENT = "Corporate-Sponsors"

    # Public: Generate the Network for a paying Account. This will
    # associate the User, PaymentMethod, Customer and CustomerAccount.
    # Existing Customer objects and PaymentMethods, even orphaned ones, will
    # be re-used.
    #
    # target  - A User, Organization, or Business to generate a paying account
    # actor   - the authenticated User taking this action
    # details - A Hash of payment details:
    #   :omit_billing_info - optional Boolean to indicate we should create a Zuora account without any billing info
    #   :zuora_payment_method_id - The payment method ID returned by Zuora's Hosted Payment Page
    #   :billing_extra    - String extra billing information.
    #   :vat_code         - String VAT identification number
    #   :paypal_nonce     - String nonce representing a paypal account (optional).
    #   :billing_address  - The billing address as a Hash of optionally encrypted CC info
    #     * :country_code_alpha3 - Country as a 3-letter abbreviation String
    #     * :region              - Region as a String
    #     * :postal_code         - Postal code as a String
    #   :zuora_account_id - optional ID of an existing Zuora account to look up and associate with the given `target`
    # purpose - Symbol indicating the purpose of the customer and customer account to create, :general or :sponsors
    sig do
      params(
        target: ::Billing::Types::Account,
        actor: T.nilable(User),
        details: T::Hash[Symbol, T.untyped],
        purpose: T.any(Symbol, String),
        skip_sync: T::Boolean,
        vat_code: T.nilable(String),
      ).returns(::Billing::CreateCustomer)
    end
    def self.perform(target, actor: nil, details: {}, purpose: Customer::DEFAULT_PURPOSE, skip_sync: false, vat_code: nil)
      new(target, actor: actor, details: details, purpose: purpose, skip_sync: skip_sync, vat_code: vat_code).perform
    end

    sig do
      params(
        target: ::Billing::Types::Account,
        actor: T.nilable(User),
        details: T::Hash[Symbol, T.untyped],
        purpose: T.any(Symbol, String),
        skip_sync: T::Boolean,
        vat_code: T.nilable(String),
      ).void
    end
    def initialize(target, actor: nil, details: {}, purpose: Customer::DEFAULT_PURPOSE, skip_sync: false, vat_code: nil)
      @target  = target
      @actor   = actor
      @details = details
      @purpose = T.let(purpose.to_sym, Symbol)
      @zuora_account_id = T.let(details[:zuora_account_id], T.nilable(String))
      @zuora_response = T.let(nil, T.nilable(T::Hash[Symbol, T.untyped]))
      @customer_creation_already_in_progress = T.let(false, T::Boolean)
      @restraint = T.let(GitHub::Restraint.new, GitHub::Restraint)

      vat_code_to_use = details[:vat_code].presence || vat_code
      if target.is_a?(Business)
        @customer = T.let(target.customer || Customer.new(name: target.slug, vat_code: vat_code_to_use, purpose: purpose), Customer)
      else
        existing_customer = target.customer_for(purpose, delegate_to_business: true)
        @customer = T.let(existing_customer || Customer.new(name: target.login, vat_code: vat_code_to_use, purpose: purpose), Customer)
      end

      # Keep a copy of the customer record prior to any changes for logging purposes
      @old_customer = T.let(@customer.persisted? ? @customer.dup : nil, T.nilable(Customer))

      # Set the vat_code if it was explicitly passed in to the creator
      @customer.vat_code = vat_code_to_use if @customer.persisted? && vat_code_to_use.present?

      # Ensure the locked_at field is populated for new customers
      @customer.locked_at = GitHub::Billing.now if !@customer.persisted? && @target.should_disable?

      @payment_method = T.let(orphaned_payment_method || PaymentMethod.build_from_payment_details(details), PaymentMethod)
      @skip_sync = skip_sync
    end

    sig { returns(T.self_type) }
    def perform
      if @details.blank?
        Customer.transaction do
          @customer.save!
          attach_customer_to_billable_entity
        end
        # Deferred lodge-cluster write; see `persist_business_association`.
        persist_business_association
        return self
      end

      target.check_for_spam
      return self if target.spammy?

      lock_customer_creation do
        if details[:omit_billing_info]
          create_remote_customer_without_billing
        else
          create_remote_customer
        end
      end
      self
    end

    sig { returns(GitHub::Billing::Result) }
    def response
      if target.spammy?
        GitHub::Billing::Result.failure("This account has been flagged. #{GitHub.support_link_text} for further information.")
      else
        result =
          if @zuora_response
            result = GitHub::Billing::Result.from_zuora(@zuora_response)
          elsif @customer_creation_already_in_progress
            GitHub::Billing::Result.failure("Customer creation is already in progress")
          else
            GitHub::Billing::Result.failure("No response from Zuora")
          end
        result.record = @customer if result.success?
        result
      end
    end

    sig { returns(T.nilable(String)) }
    def error_message
      response.error_message
    end

    sig { returns(T::Boolean) }
    def success?
      return @customer.persisted? unless @details.present?
      return false unless @zuora_response.present?
      !!@zuora_response[:success]
    end

    private

    sig { returns(T::Boolean) }
    attr_reader :skip_sync

    sig { returns(T::Boolean) }
    def should_omit_billing_info?
      !!(details[:apple_iap_subscription] || details[:omit_billing_info])
    end

    sig { returns(String) }
    def customer_creation_lock_key
      "creating_customer:#{@target.class.name}:#{target.id}"
    end

    sig { params(block: T.proc.returns(T.untyped)).void }
    def lock_customer_creation(&block)
      lock_concurrency = 1
      ttl = 1.minute
      begin
        @restraint.lock!(customer_creation_lock_key, lock_concurrency, ttl) do
          block.call
        end
      rescue GitHub::Restraint::UnableToLock => e
        @customer_creation_already_in_progress = true
        GitHub.dogstats.increment("billing.multiple_customer_creation_requests")
        GitHub.logger.error("Multiple customer creation requests",
          {
            "gh.code.namespace" => self.class,
            "gh.billing.billable_entity.id" => @target.id,
            "gh.billing.billable_entity.login" => @target.display_login,
            "gh.billing.billable_entity.type" => @target.class.name,
            "gh.billing.omit_billing_info" => should_omit_billing_info?,
          })
      end
    end

    sig { void }
    def create_remote_customer
      create_zuora_customer

      if success?
        if customer.persisted?
          # The customer already exists, so assigning the association
          # immediately persists the new payment method (and nullifies any
          # previously associated one) outside the wrapping transaction, so
          # this does not introduce a cross-cluster transaction.
          customer.payment_method = @payment_method
          Customer.transaction do
            customer.save!
            attach_customer_to_billable_entity
          end
          # Deferred lodge-cluster write; see `persist_business_association`.
          persist_business_association
        else
          # The customer is new; defer saving the payment method until after
          # the `Customer.transaction` commits to avoid a cross-cluster
          # transaction between `payment_methods` (mysql1) and tables in
          # other cluster groups (e.g. `businesses`) that may be touched
          # while attaching the customer to its billable entity.
          Customer.transaction do
            customer.save!
            attach_customer_to_billable_entity
          end
          persist_business_association
          @payment_method.customer = customer
          @payment_method.save!
          customer.reload_payment_method
        end

        payment_method.enforce_blocklisted_consequences!
        update_user_billing

        # This will create an external subscription if needed
        @target.recurring_charge
      end

      log_billing_creation("code.function": __method__.to_s)
    end

    sig { void }
    def create_remote_customer_without_billing
      # create a zuora account without any billing information
      @zuora_response = if @zuora_account_id.present?
        find_zuora_account
      else
        GitHub.zuorest_client.create_account(account_creation_params_for_zuora).with_indifferent_access
      end

      return unless @zuora_response[:success]

      # update customer information from Zuora
      @customer.zuora_account_id = @zuora_response[:accountId]
      @customer.zuora_account_number = @zuora_response[:accountNumber]

      # add an empty payment method
      @payment_method.payment_processor_type = PaymentMethod.zuora_processor_slug
      @payment_method.payment_processor_customer_id = @zuora_response[:accountId]
      @payment_method.payment_token = PaymentMethod::PAYMENT_TOKEN_CLEARED
      @payment_method.user = @target unless @target.is_a?(Business)

      # set billing type
      if sponsors_purpose?
        @customer.billing_type = Customer::BILLING_TYPE_INVOICE
        @customer.billing_end_date = (GitHub::Billing.now + 1.year).in_billing_timezone
        @payment_method.primary = false
      end

      if @customer.persisted?
        # The customer already exists, so assigning the association
        # immediately persists the new payment method (and nullifies any
        # previously associated one) outside the wrapping transaction, so
        # this does not introduce a cross-cluster transaction.
        @customer.payment_method = @payment_method
        Customer.transaction do
          @customer.save!
          attach_customer_to_billable_entity
        end
        # Deferred lodge-cluster write; see `persist_business_association`.
        persist_business_association
      else
        # The customer is new; defer saving the payment method until after
        # the `Customer.transaction` commits to avoid a cross-cluster
        # transaction between `payment_methods` (mysql1) and tables in
        # other cluster groups (e.g. `businesses`) that may be touched
        # while attaching the customer to its billable entity.
        Customer.transaction do
          @customer.save!
          attach_customer_to_billable_entity
        end
        persist_business_association
        @payment_method.customer = @customer
        @payment_method.save!
        @customer.reload_payment_method
      end

      log_billing_creation("code.function": __method__.to_s)
    end

    sig { params(log_args: T::Hash[String, T.untyped]).void }
    def log_billing_creation(log_args = {})
      log_args.merge!({
        "code.namespace" => "Billing::CreateCustomer",
        "gh.actor.id" => actor&.id,
        "gh.actor.login" => actor&.login,
        "gh.billing.create_customer.zuora_account_id" => @zuora_account_id,
        "gh.billing.create_customer.success" => success?,
        "gh.billing.create_customer.error" => error_message,
        "gh.billing.billable_entity.id" => target.id,
        "gh.billing.billable_entity.login" => target.display_login,
        "gh.billing.billable_entity.type" => target.class.name,
        "gh.billing.customer.id" => customer.id,
        "gh.billing.customer.old_zuora_account_id" => @old_customer&.zuora_account_id,
        "gh.billing.customer.new_zuora_account_id" => customer.zuora_account_id,
        "gh.billing.zuora.params" => account_creation_params_for_zuora,
        "gh.billing.zuora.response" => @zuora_response,
      })
      target = self.target
      if target.is_a?(Business)
        log_args["gh.business.slug"] = target.slug
      elsif business = target.business
        log_args["gh.user.login"] = target.login
        log_args["gh.business.name"] = business.name
      else
        log_args["gh.user.login"] = target.login
      end

      GitHub.logger.info(log_args)
    end

    sig { void }
    def create_zuora_customer
      @zuora_response = if @zuora_account_id
        find_zuora_account
      else
        create_zuora_account
      end

      attach_zuora_account_to_customer if @zuora_response[:success]
    end

    sig { returns(String) }
    def business_segment
      return CORPORATE_SPONSORS_BUSINESS_SEGMENT if sponsors_purpose?
      SELF_SERVE_BUSINESS_SEGMENT
    end

    sig { returns(String) }
    def external_name
      return @external_name if @external_name
      target = self.target
      name = if target.is_a?(Business)
        target.slug
      elsif target.business
        target.business.name
      else
        target.login
      end

      name_parts = [name]
      name_parts << "for sponsorships" if sponsors_purpose?
      @external_name = T.let(name_parts.join(" "), T.nilable(String))
      T.must(@external_name)
    end

    sig { returns(T.nilable(String)) }
    def external_email
      target = self.target
      if target.is_a?(Business)
        target.billing_email
      elsif target.business
        target.business.customer&.billing_email&.email
      else
        target.email
      end
    end

    sig { returns(T.nilable(String)) }
    def vat_code
      target_billing_information.vat_code
    end

    # If the target is business owned it will return the business's billing contact instead
    sig { returns(Billing::Contact) }
    def target_billing_information
      target = self.target
      if !target.is_a?(Business) && target.business
        target.business.customer&.billing_contact || Billing::Contact.new
      else
        target.customer&.billing_contact || Billing::Contact.new
      end
    end

    # If the target is business owned it will return the business's shipping contact instead
    sig { returns(T.nilable(Billing::Contact)) }
    def target_shipping_information
      target = self.target
      if !target.is_a?(Business) && target.business
        target.business.customer&.shipping_contact
      else
        target.customer&.shipping_contact
      end
    end

    # Creates a hash with first and last names for the Zuora bill to/sold to contact information
    #
    # Will return the external name (slug or login) by default
    # If the target is business owned it will use the business contact information as the target screening record
    # If the target contact has an entity name it will use that as the first name
    # If the target contact has first/last names it will use those
    sig { params(contact: Billing::Contact).returns({ firstName: String, lastName: String }) }
    def contact_names(contact)
      # Use the external name by default
      names = {
        firstName: external_name,
        lastName: external_name,
      }

      # Return the default unless the target (or target owning business) has a valid Billing::Contact
      return names unless contact.valid_for_trade_screening?

      entity_name = contact.entity_name
      if entity_name.present?
        split_names = entity_name.split(" ")

        if split_names.size == 1
          name = split_names.first
          names[:firstName] = name
          names[:lastName] = name
        else
          names[:firstName] = split_names.first
          names[:lastName] = split_names[1..-1].to_a.join(" ")
        end
      else
        names[:firstName] = contact.first_name
        names[:lastName] = contact.last_name
      end

      names
    end

    sig { returns(T::Hash[Symbol, Integer]) }
    def bt_fields
      target = self.target
      if target.is_a?(Business) || target.business
        {}
      else
        { user_id: target.id }
      end
    end

    sig { returns(Integer) }
    def billed_on
      target = self.target
      day = if !target.is_a?(Business) && target.business
        (target.business.billing_term_ends_on + 1.day).day
      else
        target.billed_on&.day
      end
      day || GitHub::Billing.today.day
    end

    sig { returns(T::Hash[Symbol, T.untyped]) }
    def create_zuora_account
      if details[:paypal_nonce].present?
        create_zuora_paypal_account
      else
        create_zuora_account_and_braintree_customer
      end
    end

    sig { returns(T::Hash[Symbol, T.untyped]) }
    def create_zuora_paypal_account
      billing_address = if target_billing_information.persisted?
        billing_address = {
          address1: target_billing_information.address1,
          address2: target_billing_information.address2,
          city: target_billing_information.city,
          postal_code: target_billing_information.postal_code,
          country_code: Customer.countries.key(target_billing_information.country_code),
          region: target_billing_information.region,
        }
      else
        details[:billing_address].slice(:address1, :address2, :city, :postal_code, :region).merge(
          country_code: details[:billing_address][:country_code_alpha3]
        )
      end

      Billing::ZuoraPaypal.create_account(
        target_details: {
          external_name: external_name,
          bt_fields: bt_fields,
          billed_on: billed_on,
        },
        paypal_nonce: details[:paypal_nonce],
        billing_address: billing_address,
        vat_code: details[:vat_code],
        tax_exemption_status: customer.tax_exemption_status,
      )
    end

    sig { returns(T::Hash[Symbol, T.untyped]) }
    def bill_to_contact
      address_info =
        if details[:omit_billing_info]
          billing_information = target_billing_information
          if billing_information.valid_for_trade_screening?
            {
              address1: billing_information.address1,
              address2: billing_information.address2,
              city: billing_information.city,
              zipCode: billing_information.postal_code,
              country: billing_information.country_code,
              state: billing_information.region,
            }
          else
            {
              # using GitHub HQ here to represent the billToContact address since zuora
              # requires billing info to create an account
              country: "USA",
              state: "CA",
            }
          end
        else
          {
            address1: details.dig(:billing_address, :address1),
            address2: details.dig(:billing_address, :address2),
            city: details.dig(:billing_address, :city),
            zipCode: details.dig(:billing_address, :postal_code),
            country: details.dig(:billing_address, :country_code_alpha3),
            state: details.dig(:billing_address, :region),
          }
        end

      contact_names(target_billing_information).merge(address_info)
    end

    sig { returns(T::Hash[Symbol, T.untyped]) }
    def sold_to_contact
      shipping_information = target_shipping_information
      return bill_to_contact unless shipping_information&.persisted?
      return bill_to_contact unless shipping_information.valid_for_trade_screening?

      address_info = {
        address1: shipping_information.address1,
        address2: shipping_information.address2,
        city: shipping_information.city,
        zipCode: shipping_information.postal_code,
        country: shipping_information.country_code,
        state: shipping_information.region,
      }
      contact_names(shipping_information).merge(address_info)
    end

    sig { returns(T::Hash[Symbol, T.untyped]) }
    def account_creation_params_for_zuora
      account_creation_base_params.merge(account_creation_payment_params)
    end

    sig { returns(T::Hash[Symbol, T.untyped]) }
    def account_creation_base_params
      tax_exemption_status = customer.tax_exemption_status

      base_params = {
        BusinessSegment__c: business_segment,
        batch: SELF_SERVE_BATCH,
        SynctoNetSuite__NS: "No",
        billCycleDay: 0,
        communicationProfileId: GitHub.zuora_self_serve_communication_profile_id,
        currency: "USD",
        name: external_name,
        billToContact: bill_to_contact,
        soldToContact: sold_to_contact,
        taxInfo: {
          exemptStatus: tax_exemption_status&.approved? ? "Yes" : "No",
          exemptCertificateId: tax_exemption_status&.id&.to_s || "N/A",
          VATId: vat_code,
        }
      }

      stamp = GitHub::Config::Proxima.current_stamp_or_dotcom
      if stamp != "dotcom"
        base_params.merge({ Stamp__c: stamp })
      else
        base_params
      end
    end

    sig { returns(T::Hash[Symbol, T.untyped]) }
    def account_creation_payment_params
      params = {
        paymentGateway: ::Billing::Zuora::PaymentGateway.for(@target, type: :credit_card),
        APM__c: "True" # See https://knowledgecenter.zuora.com/Zuora_Collect/Zuora_Collections/CA_Advanced_Payment_Manager
      }

      if details[:omit_billing_info]
        params[:autoPay] = false
      else
        # "If the autoPay field is set to true in the request, you must provide one of the paymentMethod, creditCard,
        # or hpmCreditCardPaymentMethodId field, but not multiple."
        # -- https://www.zuora.com/developer/api-reference/#operation/POST_Account
        params.merge!(
          autoPay: true,
          hpmCreditCardPaymentMethodId: details[:zuora_payment_method_id],
        )
      end

      params
    end

    sig { returns(T::Hash[Symbol, T.untyped]) }
    def find_zuora_account
      zuora_response = GitHub.zuorest_client.get_account(@zuora_account_id).symbolize_keys
      zuora_response[:success] = true
      zuora_response[:accountId] = zuora_response[:account_id] = zuora_response[:Id]
      zuora_response[:accountNumber] = zuora_response[:account_number] = zuora_response[:AccountNumber]
      zuora_response
    rescue Zuorest::HttpError => err
      Failbot.report!(err, app: "github-zuora")
      # Include error message and code in a format that GitHub::Billing::Result#zuora_error_message and
      # GitHub::Billing::Result#zuora_error_code expect:
      { :success => false, "reasons" => [{ "message" => err.message, "code" => err.status_code }] }
    end

    sig { returns(T::Hash[Symbol, T.untyped]) }
    def create_zuora_account_and_braintree_customer
      zuora_response = GitHub.zuorest_client.create_account(account_creation_params_for_zuora)
      return zuora_response.with_indifferent_access unless zuora_response["success"]

      zuora_response[:account_number] = zuora_response["accountNumber"]
      zuora_response[:account_id] = zuora_response["accountId"]
      zuora_response[:payment_method_id] = zuora_response["paymentMethodId"]
      zuora_response[:success] = zuora_response["success"]

      braintree_success = create_braintree_customer(zuora_response)
      return { success: false } unless braintree_success

      zuora_response
    end

    # Private: Create a Braintree customer so we can use it if we update
    # the payment method later on to use PayPal. We are using
    # Braintree's Paypal JS library so it's easier to keep track of the
    # customers by updating their payment methods instead of creating new ones.
    sig { params(zuora_response: T::Hash[Symbol, T.untyped]).returns(T::Boolean) }
    def create_braintree_customer(zuora_response)
      braintree_response = ::Braintree::Customer.create({
        id: zuora_response[:accountId],
        first_name: external_name,
        custom_fields: bt_fields,
      })
      return true if braintree_response.success?

      Failbot.report(
        BraintreeCreationError.new("Customer creation failed"),
        {
          "gh.target.id" => @target.id,
          "gh.billing.braintree.response.message" => braintree_response.message
        },
      )
      false
    end

    sig { void }
    def attach_zuora_account_to_customer
      zuora_response = T.must(@zuora_response)
      if paypal_account = zuora_response[:paypal_account]
        @payment_method.paypal_email = paypal_account.email
      else
        success = update_payment_method_from_zuora
        return unless success
      end
      @customer.zuora_account_id = zuora_response[:account_id]
      @customer.zuora_account_number = zuora_response[:account_number]
      @customer.bill_cycle_day = details[:paypal_nonce].present? ? billed_on : 0

      target = self.target
      unless target.is_a?(Business) || target.business
        @payment_method.user = target
      end

      @payment_method.payment_processor_type = PaymentMethod.zuora_processor_slug
      @payment_method.payment_processor_customer_id = zuora_response[:account_id]
      @payment_method.payment_token = zuora_response[:payment_method_id]
      @payment_method.cache_payment_method_change_actor(actor)
    end

    sig { returns(T::Boolean) }
    def update_payment_method_from_zuora
      zuora_response = T.must(@zuora_response)
      zuora_payment_method = ::Billing::Zuora::PaymentMethod.find(zuora_response[:payment_method_id])
      unless zuora_payment_method
        @zuora_response = { success: false, errors: [{ code: "INVALID_VALUE", message: "Payment method not found" }] }
        return false
      end

      @payment_method.assign_from_zuora_payment_method(zuora_payment_method)
      @payment_method.paypal_email = nil

      true
    end

    sig { returns(T.nilable(PaymentMethod)) }
    def orphaned_payment_method
      payment_methods_for_purpose = PaymentMethod.for_purpose(@purpose)

      target = self.target
      if target.is_a?(Business) || target.business
        payment_methods_for_purpose.find_by(customer_id: @customer.id)
      else
        payment_methods_for_purpose.find_by(user_id: @target.id)
      end
    end

    sig { returns(T::Boolean) }
    def sponsors_purpose?
      purpose == :sponsors
    end

    sig { void }
    def attach_customer_to_billable_entity
      target = self.target
      if target.is_a?(Business)
        # NB: `@customer.business = target` is deferred to
        # `persist_business_association` (called after the wrapping
        # `Customer.transaction` commits) to avoid a cross-cluster transaction
        # between `businesses` (lodge) and `customer_accounts` (mysql1). This
        # mirrors the existing deferral of `@payment_method.save!` in `create_remote_customer`.
        return if @customer.customer_accounts.exists?(billable_entity: target, purpose: purpose)
      else
        # We don't want to override the targets existing customer, or associate a
        # customer with a target that belongs to a business (since it will be set on the business)
        return if target_has_customer_for_specified_purpose?
      end

      create_verified_customer_account(target)

      # NB Need to refresh customer association so we have its context when we check for
      # valid payment.
      reload_customer_for_specified_purpose
    end

    sig { void }
    def persist_business_association
      target = self.target
      return unless target.is_a?(Business)
      # Lodge-cluster write (`UPDATE businesses SET customer_id = ?`). Must run
      # outside the wrapping `Customer.transaction` (mysql1) to avoid a
      # cross-cluster transaction with `customer_accounts` (mysql1) and
      # `businesses` (lodge). Pairs with the deferred assignment in
      # `attach_customer_to_billable_entity`.
      @customer.business = target
    end

    sig { params(target: ::Billing::Types::Account).returns(CustomerAccount) }
    def create_verified_customer_account(target)
      attrs = {
        billable_entity: target,
        purpose: purpose,
      }
      attrs[:user] = target if target.is_a?(User)

      customer_account = @customer.customer_accounts.create!(attrs)
      verify_actor = target.is_a?(Business) ? nil : target
      customer_account.verify!(verify_actor)
    end

    sig { returns(T.nilable(Customer)) }
    def reload_customer_for_specified_purpose
      if sponsors_purpose?
        T.cast(target, ::User).reload_sponsors_customer
      else
        target.reload_customer
      end
    end

    sig { returns(T::Boolean) }
    def target_has_customer_for_specified_purpose?
      return target.sponsors_customer.present? if sponsors_purpose?
      return true if target.customer
      return true if target.is_a?(User) && T.cast(target, ::User).business&.customer.present?
      false
    end

    sig { void }
    def update_user_billing
      target = self.target
      if details.has_key?(:billing_extra) && !target.is_a?(Business) && !target.business
        target.billing_extra = details[:billing_extra]
      end

      # Ideally, we should use `enable_or_disable!` here, but there is logic that exists
      #   that depends on the behavior of `unlock_billing`, which at the time of writing,
      #   resets the billing attempts to 0, sets the billed_on date to the future and enables
      #   the account if it's disabled. This breaks any logic that depends on the billing attempt
      #   count being reset or the billed_on date being moved.
      # Using the check `should_disable?` also can't be used on its own here. At the time of writing,
      #   `should_disable?` has some checks, one of which verifies whether the account has had a past
      #   successful payment. However, since this method is being called on customer creation,
      #   it's unlikely that the customer had a past successful payment. Therefore, checking whether
      #   or not any disabled reasons are present on the account will have to suffice for now.
      target.unlock_billing! if target.disabled? && target.disabled_reasons&.empty?

      # This is expected to save changes to various fields on the target that were made before
      # being passed in to the CreateCustomer class. Skip the save when no
      # attributes have changed to avoid an extra commit (and the associated
      # `after_commit` callbacks, such as search reindexing). This matters when
      # the caller has already persisted attribute changes before invoking
      # `CreateCustomer` (e.g. `GitHub::Billing.redeem_coupon_and_charge`,
      # which calls `redeem_coupon` outside the payment transaction to avoid
      # cross-cluster transactions).
      target.save! if target.changed?
    end
  end
end
