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
      filtered_business_params = business_params

      advanced_security_enabled_type_for_entity = filtered_business_params.delete(:advanced_security_enabled_type_for_entity)
      advanced_security_seats = filtered_business_params.delete(:advanced_security_seats_for_entity).to_i
      copilot_max_seats = filtered_business_params.delete(:copilot_max_seats).to_i
      startup_program_status = filtered_business_params.delete(:part_of_startup_program)

      business_creator = Business::Creator.new(
        business_params: filtered_business_params.merge(
          any_length_shortcode_feature_flag_enabled: GitHub.flipper[:any_length_shortcode].enabled?(current_user),
          owners: owners_from_params,
          customer_attributes: filtered_business_params.fetch(:customer_attributes, {}).merge(
            billing_type: "invoice")),
        require_owners: false)

      if business_creator.valid?
        business_creator.save!
        business = business_creator.business
        business.copilot_max_seats = copilot_max_seats
        handle_startup_program(business, startup_program_status)

        if advanced_security_enabled_type_for_entity != Configurable::AdvancedSecurityBillingConfig::ADVANCED_SECURITY_OFF && advanced_security_enabled_type_for_entity.present?
          begin
            business.set_advanced_security_enabled_type_for_entity(option: advanced_security_enabled_type_for_entity, actor: current_user)
            business.set_advanced_security_seats_for_entity(seats: advanced_security_seats, actor: current_user)
          rescue ArgumentError, TypeError, Configurable::AdvancedSecurityBillingConfig::DunningError => e
            Failbot.report(e, catalog_service: "github/advanced_security_billing")
            flash[:error] = "Failed to enable Advanced Security for newly created enterprise. #{e.message}."
          end
        end

        if GitHub.multi_tenant_enterprise?
          business.update!(plan_duration: "month")
          business.customer.onboard_to_all_billing_platform_products
        else
          business.customer.onboard_to_billing_platform(
            products: [
              ::Billing::OnboardCustomerToProductInBillingPlatformJob::ProductEnum::Actions.serialize,
              ::Billing::OnboardCustomerToProductInBillingPlatformJob::ProductEnum::Codespaces.serialize,
              ::Billing::OnboardCustomerToProductInBillingPlatformJob::ProductEnum::Copilot.serialize,
              ::Billing::OnboardCustomerToProductInBillingPlatformJob::ProductEnum::Git_Lfs.serialize,
              ::Billing::OnboardCustomerToProductInBillingPlatformJob::ProductEnum::Packages.serialize
            ]
          )
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
      filtered_business_params = business_params_with_billing_email(include_slug: false)
      old_seats = this_business.seats

      advanced_security_enabled_type_for_entity = filtered_business_params.delete(:advanced_security_enabled_type_for_entity)
      advanced_security_seats = filtered_business_params.delete(:advanced_security_seats_for_entity).to_i

      begin
        if advanced_security_enabled_type_for_entity.present?
          this_business.set_advanced_security_enabled_type_for_entity(option: advanced_security_enabled_type_for_entity, actor: current_user, is_stafftools_action: true)

          if advanced_security_enabled_type_for_entity == Configurable::AdvancedSecurityBillingConfig::ADVANCED_SECURITY_OFF

            # Skip the GHAS seats validation because cancelling and refunding the subscription
            # happens in a background job, asynchronously. The validation for the GHAS seats ensuring
            # that the seat count is 0 when GHAS is marked as not purchased therefore fails because the
            # subscription cancellation, which sets the seat count to 0, hasn't happened yet
            this_business.skip_ghas_seats_validation = true
            this_business&.advanced_security_subscription_item&.cancel_and_refund!
          end
        end

        if advanced_security_seats
          this_business.set_advanced_security_seats_for_entity(seats: advanced_security_seats, actor: current_user, is_stafftools_action: true)
        end

      rescue ArgumentError, TypeError, Configurable::AdvancedSecurityBillingConfig::DunningError => e
        Failbot.report(e, catalog_service: "github/advanced_security_billing")
        flash[:error] = "Failed to updated Advanced Security setting for enterprise. #{e.message}."
      end

      if billing_email_valid?
        begin
          # Explicitly set the timezone to Pacific to ensure that the invoice term end date is set correctly.
          Time.use_zone(GitHub::Billing.timezone) do
            request_startup_status = filtered_business_params.delete(:part_of_startup_program)
            this_business.update(filtered_business_params)
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
        customer_attributes: [
          :billing_end_date,
          :metered_ghe
        ],
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
      else
        customer.update(zuora_account_id: nil)
        customer.update(zuora_account_number: nil)
      end
    end

    def handle_startup_program(business, status)
      return unless status

      startups_program = BusinessStartupsProgram.create_or_update!(business, status)
      startups_program.send_welcome_email if startups_program
    end
  end
end
