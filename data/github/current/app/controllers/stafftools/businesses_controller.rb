# typed: true
# frozen_string_literal: true

module Stafftools
  class BusinessesController < Stafftools::Businesses::BusinessBaseController
    include BusinessesHelper
    include SharedBusinessActions
    include Stafftools::BillingHelper

    # Allow a limited subset of necessary actions in GHES
    skip_before_action :dotcom_required, only: %w(index show)

    skip_before_action :business_required, only: %w(
      index new create destroy check_slug
    )
    before_action :check_for_owners, only: %w(show)

    depends_on_clusters ApplicationRecord::Mysql1,
      ApplicationRecord::IamAbilities,
      ApplicationRecord::Ballast,
      ApplicationRecord::Configurations,
      ApplicationRecord::Billing,
      ApplicationRecord::Collab,
      ApplicationRecord::Mysql2,
      ApplicationRecord::NotificationsEntries,
      ApplicationRecord::Mysql5,
      ApplicationRecord::Repositories,
      ApplicationRecord::Copilot,
      only: [:show]

    depends_on_clusters ApplicationRecord::Mysql1,
      ApplicationRecord::IamAbilities,
      ApplicationRecord::Collab,
      ApplicationRecord::Mysql2,
      ApplicationRecord::NotificationsEntries,
      ApplicationRecord::Mysql5,
      ApplicationRecord::Ballast,
      ApplicationRecord::Configurations,
      ApplicationRecord::Repositories,
      ApplicationRecord::Billing,
      only: [:index]

    depends_on_clusters ApplicationRecord::Mysql1,
      ApplicationRecord::IamAbilities,
      ApplicationRecord::Ballast,
      ApplicationRecord::Configurations,
      ApplicationRecord::Collab,
      ApplicationRecord::Mysql2,
      ApplicationRecord::NotificationsEntries,
      ApplicationRecord::Mysql5,
      ApplicationRecord::Repositories,
      ApplicationRecord::Billing,
      only: [:edit]

    depends_on_clusters ApplicationRecord::Mysql1,
      ApplicationRecord::IamAbilities,
      ApplicationRecord::Ballast,
      ApplicationRecord::Configurations,
      ApplicationRecord::Collab,
      ApplicationRecord::Mysql2,
      ApplicationRecord::NotificationsEntries,
      ApplicationRecord::Mysql5,
      ApplicationRecord::Repositories,
      ApplicationRecord::Billing,
      only: [:new]

    depends_on_clusters ApplicationRecord::Copilot,
      only: [:index, :edit, :new],
      optional: true

    BUSINESSES_PAGE_SIZE = 50

    def index
      tab = params[:tab] || "active"
      businesses = if tab == "deleted"
        ::Business.deleted.for_query(params[:query]).order("deleted_at DESC")
      else
        if params[:query].present?
          query = ::Search::Queries::EnterpriseQuery.new query: params[:query]
          results = query.execute
          if results.error?
            flash[:error] = "Enterprise search is currently unavailable, please try again later."
            Business.none
          elsif results.empty?
            Business.none
          else
            Business.where(id: results.map { |hit| hit["_id"] })
          end
        else
          ::Business.by_slug
        end
      end
      businesses = businesses.paginate(page: current_page, per_page: BUSINESSES_PAGE_SIZE)

      render "stafftools/businesses/index", layout: "stafftools", locals: { tab: tab, businesses: businesses }
    end

    def new
      render "stafftools/businesses/new", layout: "stafftools"
    end

    def create
      copilot_max_seats = business_params.dig(:copilot_max_seats).to_i
      startup_program_status = business_params.dig(:part_of_startup_program)

      business_creator = Business::Creator.new(
        business_params: filtered_business_params(business_params).merge(
          owners: owners_from_params,
          customer_attributes: business_params.fetch(:customer_attributes, {}).merge(
            billing_type: "invoice")),
        require_owners: false)

      if business_creator.valid?
        business_creator.save!
        business = business_creator.business
        business.copilot_max_seats = copilot_max_seats
        handle_startup_program(business, startup_program_status)

        begin
          handle_advanced_security_updates(business, business_params, new_record: true)
        rescue ArgumentError, TypeError, Configurable::AdvancedSecurityBillingConfig::Error => e
          Failbot.report(e, catalog_service: "github/advanced_security_billing")
          flash[:error] = "Failed to updated Advanced Security setting for enterprise. #{e.message}."
        end

        if GitHub.multi_tenant_enterprise?
          business.update!(plan_duration: "month")
          business.customer.set_metered_plan_and_onboard_to_all_billing_platform_products
        else
          business.customer.onboard_to_all_billing_platform_products
        end
        flash[:notice] = "Created #{business.name}."
        redirect_to stafftools_enterprise_complete_path(business)
      else
        flash[:error] = "Failed to save enterprise account. #{business_creator.error_message}."
        render "stafftools/businesses/new", layout: "stafftools", locals: { business_params: business_params }
      end
    end

    def show
      render "stafftools/businesses/show"
    end

    def edit
      render "stafftools/businesses/edit", locals: { business: this_business }
    end

    def update
      business_params = business_params_with_billing_email(include_slug: false)
      old_seats = this_business.seats
      original_url = params[:original_zuora_account_url]
      submitted_url = params[:zuora_account_url]

      if original_url.present? && submitted_url.blank? && this_business.customer&.zuora_account_id.present?
        this_business.errors.add(
          :zuora_account_url,
          "If you are trying to unlink a Zuora account by clearing the Zuora account URL, please use 'Unlink Zuora Account' on the billing overview page."
        )
        flash.now[:error] = this_business.errors[:zuora_account_url].first
        return render "stafftools/businesses/edit", locals: {
          business: this_business, business_params: business_params
        }
      end

      begin
        handle_advanced_security_updates(this_business, business_params, new_record: false)
      rescue ArgumentError, TypeError, Configurable::AdvancedSecurityBillingConfig::Error => e
        Failbot.report(e, catalog_service: "github/advanced_security_billing")
        flash[:error] = "Failed to updated Advanced Security setting for enterprise. #{e.message}."
      end

      if billing_email_valid?
        begin
          # Explicitly set the timezone to Pacific to ensure that the invoice term end date is set correctly.
          Time.use_zone(GitHub::Billing.timezone) do
            request_startup_status = business_params.dig(:part_of_startup_program)
            this_business.update(filtered_business_params(business_params))
            handle_startup_program(this_business, request_startup_status)
            update_zuora_account
          end
        rescue Business::NoOrganizationOwnerError => error
          flash[:error] = "Failed to update enterprise account. #{error.message}"
          return redirect_to stafftools_enterprise_path(this_business)
        end
      end

      if this_business.errors.blank?
        this_business.track_seat_upgrade_change(
          current_user,
          old_seats: old_seats,
          seats: this_business.seats
        )
        flash[:notice] = "Updated #{this_business.name}."
        redirect_to stafftools_enterprise_path(this_business)
      else
        flash[:error] = "Failed to update enterprise account. #{this_business.errors.full_messages.to_sentence}."
        render "stafftools/businesses/edit", locals: {
          business: this_business, business_params: business_params
        }
      end
    end

    def destroy
      # The reason that this action skips business_required is that it depends on
      # this_business, which deliberately does not find soft-deleted Businesses.
      business = Business.including_deleted.find_by(slug: params[:slug])
      return render_404 unless business

      DestroyBusinessJob.perform_later(T.must(business.id), actor: current_user)
      flash[:notice] = "#{business.name} enqueued for permanent deletion. NOTE: This may take a long time to complete."
      redirect_to stafftools_enterprises_path
    end

    private

    def business_params
      params.require(:business).permit(
        :owners,
        :billing_email,
        :name,
        :copilot_max_seats,
        :slug,
        :shortcode,
        :can_self_serve,
        :staff_owned,
        :terms_of_service_type,
        :terms_of_service_notes,
        :terms_of_service_company_name,
        :part_of_startup_program,
        :seats,
        :seats_plan_type,
        :support_plan,
        :microsoft_support_plan,
        :business_type,
        :enterprise_web_business_id,
        :advanced_security_enabled_type_for_entity,
        :advanced_security_seats_for_entity,
        :trial_expires_at,
        :custom_seat_limit_for_upgrades,
        :sales_managed_trial,
        customer_attributes: [
          :billing_end_date,
          :metered_ghe
        ],
        unbundled_all: [
          :secret_protection_licenses,
          :code_security_licenses,
        ],
        secret_protection_only: [
          :secret_protection_licenses,
        ],
        code_security_only: [
          :code_security_licenses,
        ],
      )
    end

    # filtered_business_params needs to remove a few form params in order
    # to be suitable for Business updates like in `Business::Creator.new`
    def filtered_business_params(params)
      params
        .except(:advanced_security_enabled_type_for_entity,
          :advanced_security_seats_for_entity,
          :secret_protection_licenses,
          :code_security_licenses,
          :unbundled_all,
          :secret_protection_only,
          :code_security_only,
          :copilot_max_seats,
          :part_of_startup_program,
        )
    end

    def owners_from_params
      return [] if params[:business][:owners].blank?
      ::User.where login: params[:business][:owners].strip.split
    end

    memoize def billing_email_from_params
      UserEmail.find_by(email: business_params.dig(:customer_attributes, :billing_email))
    end

    def billing_email_valid?
      billing_email = business_params.dig(:customer_attributes, :billing_email)
      return true unless billing_email.present?
      return true if billing_email_from_params.present?
      this_business.errors.add(:base, :invalid_billing_email, message: "Billing email must be associated with a user")
      false
    end

    def business_params_with_billing_email(include_slug: true)
      params = if business_params.dig(:customer_attributes, :billing_email).present?
        business_params.tap { |params| params[:customer_attributes][:billing_email] = billing_email_from_params }
      elsif business_params.dig(:customer_attributes, :billing_email) == ""
        business_params.tap { |params| params[:customer_attributes][:billing_email] = nil }
      else
        business_params
      end

      copilot_business = ::Copilot::Business.new(this_business)
      if copilot_business.copilot_standalone?
        params[:copilot_max_seats] = params[:copilot_max_seats]&.to_i || copilot_business.copilot_max_seats
      else
        params.delete(:copilot_max_seats)
      end

      params = params.except(:slug) unless include_slug

      params
    end

    def update_zuora_account
      zuora_account_url = params[:zuora_account_url]
      customer = this_business.customer

      if !zuora_account_url.nil? && zuora_account_url != ""
        uri = URI(zuora_account_url)
        params = URI.decode_www_form(uri.query || "").to_h

        zuora_account_id = params["id"]
        if zuora_account_id.nil?
          this_business.errors.add(:base, :invalid_zuora_account_id, message: "Zuora account URL must include account ID")
          return
        end

        zuora_account = GitHub.zuorest_client.get_account(zuora_account_id)
        if zuora_account.nil? || zuora_account["AccountNumber"].nil?
          this_business.errors.add(:base, :invalid_zuora_account_number, message: "Unable to find associated Zuora account number")
          return
        end

        zuora_account_number = zuora_account["AccountNumber"]

        Customer.transaction do
          begin
            customer.update(zuora_account_id: zuora_account_id)
            customer.update(zuora_account_number: zuora_account_number)
          rescue ActiveRecord::RecordNotUnique
            this_business.errors.add(:base, :duplicate_zuora_account_number, message: "Zuora account number already associated with another customer")
            raise ActiveRecord::Rollback
          rescue ActiveRecord::ValueTooLong
            this_business.errors.add(:base, :zuora_account_value_too_long, message: "Please check your input for the Zuora account URL")
            raise ActiveRecord::Rollback
          end
        end
      end
    end

    def handle_startup_program(business, status)
      return unless status

      startups_program = BusinessStartupsProgram.create_or_update!(business, status)
      startups_program.send_welcome_email if startups_program
    end

    def handle_advanced_security_updates(business, params, new_record:)
      ghas_option = params.delete(:advanced_security_enabled_type_for_entity)
      return unless ghas_option.present?

      trial_skus_before_update = ghas_trial_skus(business)
      converted = false

      metered_ghas_by_param = {
        ghas_off: Configurable::AdvancedSecurityBillingConfig::ADVANCED_SECURITY_OFF,
        ghas_bundled_metered: Configurable::AdvancedSecurityBillingConfig::GHAS_METERED,
        split_metered: Configurable::AdvancedSecurityBillingConfig::SPLIT_METERED,

        # ghas_unbundled_all: Configurable::AdvancedSecurityBillingConfig::SPLIT_VOLUME,
        # secret_protection_only: Configurable::AdvancedSecurityBillingConfig::SECRET_PROTECTION_VOLUME,
        # code_security_only: Configurable::AdvancedSecurityBillingConfig::CODE_SECURITY_VOLUME,
        # ghas_bundled_volume: Configurable::AdvancedSecurityBillingConfig::GHAS_VOLUME,
      }
      current_ghas_offering = business.advanced_security_enabled_type_for_entity
      # Short-circuit if we're not changing anything
      # `Business#set_advanced_security_enabled_type_for_entity` does this same check, but given the amount of
      # _other_ work happening in this method, we'll duplicate that short-circuiting.
      # Note: This no-op only applies to metered plans. With volume offerings, we may be changing other attributes
      # like the license count.
      return if metered_ghas_by_param[ghas_option.to_sym] == current_ghas_offering

      case ghas_option.to_sym
      when :ghas_off
        # We are not gonna manage bundle state. It's being turned off.
        if business.feature_flag_enabled?(:secret_scanning_suppress_end_of_trial_events_for_metered_customers, default: false)
          if current_ghas_offering == Configurable::AdvancedSecurityBillingConfig::ADVANCED_SECURITY_OFF && business.advanced_security_seats_for_entity == 0
            return # No need to emit events if the state is already off
          end
        end
        business.set_advanced_security_enabled_type_for_entity(option: Configurable::AdvancedSecurityBillingConfig::ADVANCED_SECURITY_OFF, actor: current_user)
        business.set_advanced_security_seats_for_entity(seats: 0, actor: current_user, is_stafftools_action: true)

        unless new_record
          this_business&.advanced_security_subscription_item&.cancel_and_refund!
        end
      when :ghas_bundled_metered
        if business.feature_flag_enabled?(:secret_scanning_suppress_end_of_trial_events_for_metered_customers, default: false)
          if current_ghas_offering == Configurable::AdvancedSecurityBillingConfig::GHAS_METERED && business.advanced_security_seats_for_entity == 0
            return # No need to emit events if the state is not changing
          end
        end
        business.set_advanced_security_enabled_type_for_entity(option: Configurable::AdvancedSecurityBillingConfig::GHAS_METERED, actor: current_user)
        business.set_advanced_security_seats_for_entity(seats: 0, actor: current_user, is_stafftools_action: true)
        ::Licensing::TransitionRebundleGhasForBusinessJob.perform_now(business, actor: T.must(current_user), transition_id: nil, skip_billing_config_changes: true, skip_bundle_check: true)
        converted = true
      when :ghas_bundled_volume
        seats = params.delete(:advanced_security_seats_for_entity).to_i
        if business.feature_flag_enabled?(:secret_scanning_suppress_end_of_trial_events_for_metered_customers, default: false)
          if current_ghas_offering == Configurable::AdvancedSecurityBillingConfig::GHAS_VOLUME && business.advanced_security_seats_for_entity == seats
            return # No need to emit events if the state is not changing
          end
        end

        converted = seats > 0
        emit_any_advanced_security_trial_started_events(seats, business, :ADVANCED_SECURITY)

        business.set_advanced_security_enabled_type_for_entity(option: Configurable::AdvancedSecurityBillingConfig::GHAS_VOLUME, actor: current_user)
        business.set_advanced_security_seats_for_entity(seats: seats, actor: current_user, is_stafftools_action: true)

        ::Licensing::TransitionRebundleGhasForBusinessJob.perform_now(business, actor: T.must(current_user), transition_id: nil, skip_billing_config_changes: true, skip_bundle_check: true)
      when :ghas_unbundled_all
        secret_protection_license_count = params.dig(:unbundled_all, :secret_protection_licenses).to_i
        code_security_license_count = params.dig(:unbundled_all, :code_security_licenses).to_i
        if business.feature_flag_enabled?(:secret_scanning_suppress_end_of_trial_events_for_metered_customers, default: false)
          if (current_ghas_offering == Configurable::AdvancedSecurityBillingConfig::SPLIT_VOLUME &&
            business.secret_scanning_license_count == secret_protection_license_count &&
            business.code_security_license_count == code_security_license_count)
            return # No need to emit events if the state is not changing
          end
        end

        converted = code_security_license_count > 0 || secret_protection_license_count > 0
        emit_any_advanced_security_trial_started_events(secret_protection_license_count, business, :SECRET_PROTECTION)
        emit_any_advanced_security_trial_started_events(code_security_license_count, business, :CODE_SECURITY)

        business.set_advanced_security_enabled_type_for_entity(option: Configurable::AdvancedSecurityBillingConfig::SPLIT_VOLUME, actor: current_user)
        business.set_secret_scanning_license_count(count: secret_protection_license_count, actor: current_user)
        business.set_code_security_license_count(count: code_security_license_count, actor: current_user)
        ::Licensing::TransitionUnbundleGhasForBusinessJob.perform_later(business, actor: T.must(current_user), transition_id: nil, skip_billing_config_changes: true, skip_unbundle_check: true)
      when :secret_protection_only
        secret_protection_license_count = params.dig(:secret_protection_only, :secret_protection_licenses).to_i
        if business.feature_flag_enabled?(:secret_scanning_suppress_end_of_trial_events_for_metered_customers, default: false)
          if current_ghas_offering == Configurable::AdvancedSecurityBillingConfig::SECRET_PROTECTION_VOLUME && business.secret_scanning_license_count == secret_protection_license_count
            return # No need to emit events if the state is not changing
          end
        end

        converted = secret_protection_license_count > 0
        emit_any_advanced_security_trial_started_events(secret_protection_license_count, business, :SECRET_PROTECTION)

        business.set_advanced_security_enabled_type_for_entity(option: Configurable::AdvancedSecurityBillingConfig::SECRET_PROTECTION_VOLUME, actor: current_user)
        business.set_secret_scanning_license_count(count: secret_protection_license_count, actor: current_user)
        ::Licensing::TransitionUnbundleGhasForBusinessJob.perform_later(business, actor: T.must(current_user), transition_id: nil, skip_billing_config_changes: true, skip_unbundle_check: true)
      when :code_security_only
        code_security_license_count = params.dig(:code_security_only, :code_security_licenses).to_i
        if business.feature_flag_enabled?(:secret_scanning_suppress_end_of_trial_events_for_metered_customers, default: false)
          if current_ghas_offering == Configurable::AdvancedSecurityBillingConfig::CODE_SECURITY_VOLUME && business.code_security_license_count == code_security_license_count
            return # No need to emit events if the state is not changing
          end
        end

        converted = code_security_license_count > 0
        emit_any_advanced_security_trial_started_events(code_security_license_count, business, :CODE_SECURITY)

        business.set_advanced_security_enabled_type_for_entity(option: Configurable::AdvancedSecurityBillingConfig::CODE_SECURITY_VOLUME, actor: current_user)
        business.set_code_security_license_count(count: code_security_license_count, actor: current_user)
        ::Licensing::TransitionUnbundleGhasForBusinessJob.perform_later(business, actor: T.must(current_user), transition_id: nil, skip_billing_config_changes: true, skip_unbundle_check: true)
      when :split_metered
        if business.feature_flag_enabled?(:secret_scanning_suppress_end_of_trial_events_for_metered_customers, default: false)
          if current_ghas_offering == Configurable::AdvancedSecurityBillingConfig::CODE_SECURITY_VOLUME && business.code_security_license_count == code_security_license_count
            return # No need to emit events if the state is not changing
          end
        end

        # I am not setting converted to true here because this potentially represents someone ending their contract.
        # Do we need to turn off everything here?

        business.set_customer_to_split_metered_offering(actor: current_user)
        ::Licensing::TransitionUnbundleGhasForBusinessJob.perform_later(business, actor: T.must(current_user), transition_id: nil, skip_billing_config_changes: true, skip_unbundle_check: true)
      end

      emit_any_advanced_security_trial_ended_events(trial_skus_before_update, business, converted)
    end

    sig { params(business: Business).returns(T::Array[Symbol]) }
    def ghas_trial_skus(business)
      return [] unless business.advanced_security_purchased_for_entity?
      trial_types = []

      if business.feature_flag_enabled?(:secret_scanning_suppress_end_of_trial_events_for_metered_customers, default: false)
        trial_types << :ADVANCED_SECURITY if business.advanced_security_purchased_for_entity? && business.advanced_security_products_bundled? && business.advanced_security_seats_for_entity == 0 && !business.advanced_security_metered_for_entity?
        trial_types << :CODE_SECURITY if business.code_security_purchased_for_entity? && business.code_security_license_count == 0 && !business.advanced_security_metered_for_entity?
        trial_types << :SECRET_PROTECTION if business.secret_protection_purchased_for_entity? && business.secret_scanning_license_count == 0 && !business.advanced_security_metered_for_entity?
      else
        trial_types << :ADVANCED_SECURITY if business.advanced_security_purchased_for_entity? && business.advanced_security_seats_for_entity == 0
        trial_types << :CODE_SECURITY if business.code_security_purchased_for_entity? && business.code_security_license_count == 0
        trial_types << :SECRET_PROTECTION if business.secret_protection_purchased_for_entity? && business.secret_scanning_license_count == 0
      end

      trial_types
    end

    sig { params(trial_skus_before_update: T::Array[Symbol], business: Business, converted: T::Boolean).void }
    def emit_any_advanced_security_trial_ended_events(trial_skus_before_update, business, converted)
      trial_skus_before_update.each do |trial_sku|
        trial_ended_message = {
          enterprise_id: business.id,
          action: :ENDED,
          trial_sku: trial_sku,
          converted_to_paid: converted,
          **business.advanced_security_usage_stats
        }
        GlobalInstrumenter.instrument("advanced_security_trial.toggled", trial_ended_message)
      end
    end

    sig { params(seats: Integer, business: Business, sku: Symbol).void }
    def emit_any_advanced_security_trial_started_events(seats, business, sku)
      return unless seats == 0
      return if sku == :ADVANCED_SECURITY && business.advanced_security_purchased_for_entity? && business.advanced_security_seats_for_entity == 0
      return if sku == :CODE_SECURITY && business.code_security_purchased_for_entity? && business.code_security_license_count == 0
      return if sku == :SECRET_PROTECTION && business.secret_protection_purchased_for_entity? && business.secret_scanning_license_count == 0

      message = {
        enterprise_id: business.id,
        action: :STARTED,
        trial_sku: sku,
        start_method: :STAFFTOOLS
      }
      GlobalInstrumenter.instrument("advanced_security_trial.toggled", message)
    end
  end
end
