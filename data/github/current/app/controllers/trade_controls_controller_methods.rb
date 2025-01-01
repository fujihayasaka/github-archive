# typed: strict
# frozen_string_literal: true

module TradeControlsControllerMethods
  include GitHub::Memoizer
  include BusinessesHelper
  include OrganizationsHelper

  extend ActiveSupport::Concern
  extend T::Sig
  extend T::Helpers

  requires_ancestor { ApplicationController }

  abstract!

  # Public: Creates or updates the trade screening record of a specified target plus some extra actions.
  #
  # The extra actions are triggered by the presence of the following parameters:
  #
  # - org_record_is_individual_owned: if present, the trade screening record will be created/updated for the current user
  # after which it will be linked to the target organization on Standard Terms of Service.
  #
  # - tos_org_linkage_only: if present only a link will be created between the target organization on Standard Terms
  # of Service and the trade screening record of the current user.
  #
  # - is_business: if present, the ToS type of the target organization will be updated to Corporate.
  # - organization[billing_email]: if present, the billing email of the target organization will be updated to the params value.
  sig { params(skip_redirect: T::Boolean).returns(T.any(T::Boolean, String)) }
  def update_trade_screening_record(skip_redirect: false)
    errors = []
    target = T.must_because(self.target) { "this action can only occur on a valid target" }
    tos_org = target.org_is_on_standard_tos?
    org_record_is_individual_owned = params.dig("account_screening_profile", "org_record_is_individual_owned").present?
    only_link_org_to_record_owned_by_user = tos_org && params["tos_org_linkage_only"].present?
    flash_notice = "Successfully updated billing information."
    set_corporate_tos = params["is_business"] == "true"
    # Move this out to the llama controller
    set_llama2_access_request = params["llama2_access_request"] == "true"

    if only_link_org_to_record_owned_by_user && !set_corporate_tos
      if link_record_to_org
        flash_notice = TradeControls::Notices.record_linking_success
      else
        errors << TradeControls::Notices.record_linking_error
      end
    else
      errors = update_record_with_extras(
        link_record: org_record_is_individual_owned,
        billing_email: params.dig(:organization, :billing_email),
        set_corporate_tos:  set_corporate_tos,
        set_llama2_access_request: set_llama2_access_request
      )
    end

    if errors.empty?
      flash[:notice] = flash_notice unless set_llama2_access_request
      if params[:return_to].to_s.include?("copilot")
        # we need to instrument this as the address being saved for the CFI flow
        utm_query_params = params.to_unsafe_h.slice(*::Copilot::SignupController::UTM_PARAMS).symbolize_keys
        current_copilot_user = self.current_copilot_user
        if current_copilot_user
          Copilot::Instrumenter.instrument_signup_saved_address(current_copilot_user,
            utm_query_params: utm_query_params)
        end
      end
    else
      # Remove address validation errors from global errors for flash display
      flash[:error] = errors.excluding(flash[:address_validation_error]).join("\n")
    end

    if skip_redirect
      # if we are skipping redirect, we want to know if the update was successful or not
      errors.empty?
    else
      return safe_redirect_to params[:return_to] if params[:return_to].present? && errors.empty?

      redirect_back(fallback_location: billing_path)
    end
  end

  sig { void }
  def link_trade_screening_record_to_org
    target = T.must_because(self.target) { "this action can only occur on a valid target" }
    return render_404 unless current_user.has_saved_trade_screening_record?
    return render_404 unless target.org_is_on_standard_tos?

    screening_record = current_user.trade_screening_record
    payment_flow = params.dig(:form_loaded_from)
    if payment_flow.present?
      screening_record.update(metadata: screening_record.metadata.merge({ screening_context: payment_flow }))
    end

    trade_screening_record_linked_to_org = current_user.link_trade_screening_record_to_org(organization: target)
    unless screening_record.validated_for_sales_tax?
      response = screening_record.validate_billing_information_for_tax
      screening_record.save if response.valid
    end
    set_flash_message(trade_screening_record_linked_to_org)

    instrument_billing_form_submitted

    if params[:return_to].present?
      safe_redirect_to params[:return_to].chomp("?link_other=true")
    elsif request.referrer&.include?("link_other")
      redirect_to request.referrer.chomp("?link_other=true")
    else
      redirect_back(fallback_location: billing_path)
    end
  end

  # Public: Removes an account billing information without destroying the trade screening record.
  sig { void }
  def remove_billing_information
    target = T.must_because(self.target) { "this action can only occur on a valid target" }
    is_allowed = target.is_allowed_to_remove_billing_information?
    if is_allowed && target.trade_screening_record.remove_billing_information(actor: current_user)
      flash[:notice] = "Successfully removed billing information."
    else
      flash[:error] = "Unable to remove billing information."
    end

    if params[:return_to].present?
      safe_redirect_to params[:return_to]
    else
      redirect_back(fallback_location: billing_path)
    end
  end

  # Public: Removes the reference between the target organization on Standard Terms of Service and the
  # trade screening record of the current user only if the reference exists.
  sig { void }
  def unlink_trade_screening_record_from_org
    target = T.must_because(self.target) { "this action can only occur on a valid target" }
    return render_404 unless target.organization?

    current_user.unlink_trade_screening_record_from_org(organization: target)
    flash[:notice] = "Successfully removed billing information."

    if params[:return_to].present?
      safe_redirect_to params[:return_to]
    else
      redirect_back(fallback_location: billing_path)
    end
  end

  sig { void }
  def user_profile_view
    return render_404 if !request.xhr?
    target = T.must_because(self.target) { "this action can only occur on a valid target" }
    return render_404 unless target.user?

    instrument_billing_form_loaded

    render json: {}
  end

  private

  # Private: Creates a link between the target organization and the trade screening record of the current user.
  sig { returns(T::Boolean) }
  def link_record_to_org
    payment_flow = params.dig(:form_loaded_from)
    screening_record_linked = current_user.link_trade_screening_record_to_org(organization: target, screening_flow: payment_flow)
    if screening_record_linked && payment_flow.present?
      screening_record = current_user.trade_screening_record
      screening_record.update(metadata: screening_record.metadata.merge({ screening_context: payment_flow }))
    end

    screening_record_linked
  rescue ActiveRecord::ActiveRecordError
    false
  end

  # Private: Validates if the billing information parameters valid for a screening profile
  sig { params(owner_type: Symbol).returns(T::Boolean) }
  def valid_billing_information_params_for(owner_type)
    AccountScreeningProfile.new(billing_info_params).valid?(owner_type)
  end

  # Private: Creates or updates the trade screening record of a specified target plus some extra actions.
  #
  # returns an Array of errors if any.
  sig do
    params(
      link_record: T::Boolean,
      billing_email: T.nilable(String),
      set_corporate_tos: T::Boolean,
      set_llama2_access_request: T::Boolean
    ).returns(T::Array[String])
  end
  def update_record_with_extras(link_record: false, billing_email: nil, set_corporate_tos: false, set_llama2_access_request: false)
    errors = []
    form_type = if set_llama2_access_request
      "account details"
    else
      "payment information"
    end
    update_error = "An error occurred while saving #{form_type}."
    target = T.must_because(self.target) { "this action can only occur on a valid target" }
    target_to_use = if link_record
      # Orgs on Standard Terms of Service (SToS) have a different data collection process. They can't own
      # their own trade screening billing info, so we need to save the billing info to the current user.
      current_user
    else
      target # The selected account defined in the including controller class
    end

    unless current_user.trade_screening_record.allowed_to_update? && target_to_use.trade_screening_record.allowed_to_update?
      return [update_error]
    end

    terms_updated = false
    existing_terms = nil
    existing_company = nil
    if set_corporate_tos
      existing_terms = target_to_use.terms_of_service.name
      existing_company = target_to_use.company_name
      unless valid_billing_information_params_for(:entity) && target_to_use.terms_of_service.update(
        type: Organization::TermsOfService::CORPORATE,
        actor: current_user,
        company_name: billing_info_params[:entity_name],
      )
        errors << "An error occurred while saving business information."
      end

      terms_updated = true
    end

    current_screening_record = target_to_use.trade_screening_record
    current_screening_record.assign_attributes(billing_info_params)
    valid_screening_record = current_screening_record.valid?

    payment_flow = params.dig(:form_loaded_from)
    if payment_flow.present?
      current_screening_record.assign_attributes(metadata: current_screening_record.metadata.merge({ screening_context: payment_flow }))
    end

    if valid_screening_record
      address_validity_response = current_screening_record.validate_billing_information_for_tax
      unless address_validity_response.valid
        address_validation_error = address_validity_response.error
        flash[:address_validation_error] = address_validation_error
        Billing::Settings::AccountScreeningProfileUpdateStash.stash_update_for(
          target, billing_info_params
        )
        return [address_validation_error]
      end
    end

    if valid_screening_record && current_screening_record.save
      instrument_billing_form_submitted

      if link_record
        # Having saved the billing info to the current user, we now need to create a link
        # between the saved billing info and the target org. This will allow the org to use the user's billing info as its own.
        unless link_record_to_org
          errors << TradeControls::Notices.record_linking_error
        end
      end

      if billing_email.present?
        target_to_use.billing_email = billing_email
        unless target_to_use.save
          errors << "An error occurred while saving billing email."
        end
      end

      Billing::Settings::AccountScreeningProfileUpdateStash.delete_stashed_update_for(target_to_use)
    else
      # rollback terms of service update
      if terms_updated
        target_to_use.terms_of_service.update(
          type: existing_terms,
          actor: current_user,
          company_name: existing_company,
        )
      end

      # The billing info form builders always use target.trade_screening_record to build the form,
      # however when the admin of an org tries to create their billing info to link to an org and
      # there are errors, the errors are stored in the admin billing info record, the link is not created
      # and target.trade_screening_record is empty. Updating the stash with the admin billing info errors
      # causes the form to retain the submitted values and errors scoped to the original target.
      Billing::Settings::AccountScreeningProfileUpdateStash.stash_update_for(
        target, billing_info_params, link_record ? current_screening_record.errors : nil
      )

      updates_restricted = current_screening_record.errors[:updates_restricted]
      restricted_msg = updates_restricted.to_sentence if updates_restricted.present?
      errors << "#{update_error} #{restricted_msg}"
    end

    errors
  end

  sig { returns(ActionController::Parameters) }
  def account_screening_profile_params
    params.require(:account_screening_profile).permit(
      :first_name,
      :last_name,
      :middle_name,
      :region,
      :city,
      :country_code,
      :postal_code,
      :address1,
      :address2,
      :org_record_is_individual_owned,
      :entity_name,
      :vat_code,
    )
  end

  sig { returns(ActionController::Parameters) }
  def billing_info_params
    account_screening_profile_params.except(:org_record_is_individual_owned)
  end

  sig { params(flow: T.nilable(String)).void }
  def instrument_billing_form_submitted(flow: nil)
    target = T.must_because(self.target) { "this action can only occur on a valid target" }
    page_params = params.dig(:form_loaded_from)

    GlobalInstrumenter.instrument("account_screening_profile.form_submitted", {
      actor: current_user,
      action: :SUBMITTED,
      payment_flow_page: flow || page_params || "payment flow param missing",
      target_type: target.instrumentation_object_type,
      target_id: target.id,
      target_name: target.display_login
    })
  end

  sig { params(flow: T.nilable(String)).void }
  def instrument_billing_form_loaded(flow: nil)
    target = T.must_because(self.target) { "this action can only occur on a valid target" }
    page_params = params.dig(:form_loaded_from)
    target_type = with_database_error_fallback(fallback: :UNKNOWN) { target.instrumentation_object_type }

    GlobalInstrumenter.instrument("account_screening_profile.form_loaded", {
      actor: current_user,
      action: :LOADED,
      payment_flow_page: flow || page_params || "payment flow param missing",
      target_type: target_type,
      target_id: target.id,
      target_name: target.display_login
    })
  end

  sig { params(trade_screening_record_linked_to_org: T::Boolean).void }
  def set_flash_message(trade_screening_record_linked_to_org)
    if !trade_screening_record_linked_to_org
      flash[:error] = TradeControls::Notices.record_linking_error
      return
    end

    if session[:copilot_flash_pay_info_message].blank?
      flash[:notice] = TradeControls::Notices.record_linking_success
      return
    end

    flash[:copilot_notice_message] = "You have successfully linked your billing information with this organization account."
    instrument_flash_message
  end

  sig { void }
  def instrument_flash_message
    GlobalInstrumenter.instrument(
      "analytics.event",
      category: "new_org_copilot_add_on",
      action: "free_org_update_billing_info",
      label: "flash_message:billing_information_updated;",
    )
  end

  sig { overridable.returns(T.nilable(Billing::Types::Account)) }
  memoize def target
    return business_target if params[:target] == "business"
    return organization_target if params[:target] == "organization"

    current_user
  end

  sig { returns(T.nilable(Organization)) }
  memoize def organization_target
    org = current_organization_for_member_or_billing
    return unless org

    if org.billing_manageable_by?(current_user)
      org
    end
  end

  sig { returns(T.nilable(Business)) }
  memoize def business_target
    business = Business.find_by(slug: params[:business_id])
    return unless business

    if current_user_can_manage_settings(business) || business.billing_manager?(current_user)
      business
    end
  end
end
