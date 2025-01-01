# typed: true
# frozen_string_literal: true

class Api::Staff::Enterprises < Api::Staff::App

  before do
    deliver_error! 404 if GitHub.enterprise?
    deliver_error! 404 if GitHub.multi_tenant_enterprise?
  end

  post "/staff/enterprises/emu/validate", operation_id: :internal do # rubocop:todo GitHub/ControlAccess
    @route_owner = "@github/external-identities"

    params = receive(Hash).with_indifferent_access
    validate_required_emu_enterprise_params_present(params)

    business_hash = create_emu_business_hash(params)

    creator = Business::Creator.new(business_params: business_hash, require_owners: false)

    if !creator.valid?
      messages = creator.business.errors.full_messages
      deliver_error! 400, message: messages.join("; ")
    end

    deliver_raw message: "Enterprise is valid", status: 200
  end

  post "/staff/enterprises/classic/validate", operation_id: :internal do # rubocop:todo GitHub/ControlAccess
    @route_owner = "@github/external-identities"

    params = receive(Hash).with_indifferent_access
    validate_required_classic_enterprise_params_present(params)

    business_hash = create_classic_business_hash(params)

    creator = Business::Creator.new(business_params: business_hash, require_owners: false)

    if !creator.valid?
      messages = creator.business.errors.full_messages
      deliver_error! 400, message: messages.join("; ")
    end

    deliver_raw message: "Enterprise is valid", status: 200
  end

  post "/staff/enterprises/classic/create", operation_id: :internal do # rubocop:todo GitHub/ControlAccess
    @route_owner = "@github/external-identities"

    params = receive(Hash).with_indifferent_access
    validate_required_classic_enterprise_params_present(params)

    business_hash = create_classic_business_hash(params)

    creator = Business::Creator.new(business_params: business_hash, require_owners: false)

    if creator.valid?
      creator.save!
      business = creator.business

      onboard_to_billing_platform(current_user, business)

      if params[:seats_plan_type] == "basic" && params[:copilot_max_seats].present?
        copilot_max_seats = params[:copilot_max_seats].to_i
        business.copilot_max_seats = copilot_max_seats
      end
      business_object = {
        id: business.id,
        name: business.name,
        slug: business.slug,
      }
      deliver_raw business_object, status: 201
    else
      messages = creator.business.errors.full_messages.join("; ")
      GitHub.logger.error(
        "code.namespace": "Api::Staff::Enterprises",
        "exception.message":  messages,
        "code.function": "Create"
      )
      deliver_error! 400, message: messages
    end
  end

  post "/staff/enterprises/emu/create", operation_id: :internal do # rubocop:todo GitHub/ControlAccess
    @route_owner = "@github/external-identities"

    params = receive(Hash).with_indifferent_access
    validate_required_emu_enterprise_params_present(params)

    business_hash = create_emu_business_hash(params)

    creator = Business::Creator.new(business_params: business_hash, require_owners: false)

    if creator.valid?
      creator.save!
      business = creator.business

      onboard_to_billing_platform(current_user, business)

      if params[:seats_plan_type] == "basic" && params[:copilot_max_seats].present?
        copilot_max_seats = params[:copilot_max_seats].to_i
        business.copilot_max_seats = copilot_max_seats
      end
      business_object = {
        id: business.id,
        name: business.name,
        slug: business.slug,
        shortcode: business.shortcode,
      }
      deliver_raw business_object, status: 201
    else
      messages = creator.business.errors.full_messages.join("; ")
      GitHub.logger.error(
        "code.namespace": "Api::Staff::Enterprises",
        "exception.message":  messages,
        "code.function": "Create"
      )
      deliver_error! 400, message: messages
    end
  end

  post "/staff/enterprises/emu/:slug/first-admin", operation_id: :internal do # rubocop:todo GitHub/ControlAccess
    @route_owner = "@github/external-identities"
    enterprise = Business.find_by(slug: params[:slug])
    return deliver_error 404, message: "Enterprise not found" if enterprise.nil?
    return deliver_error 400, message: "Enterprise is not an EMU enterprise" if enterprise.default_managed?

    params = receive(Hash).with_indifferent_access

    if params[:email].blank?
      deliver_error! 400, message: "Email is required"
    end

    if !User.valid_email?(params[:email])
      deliver_error! 400, message: "Email is invalid"
    end

    begin
      enterprise.create_and_add_first_emu_owner(email: params[:email], actor: nil)
    rescue ArgumentError, Business::UnableToCreateAdminUserError, Business::AdminAlreadyExistsError => e
      deliver_error! 400, message: e.message
    end

    owner = enterprise.find_first_emu_owner
    owner_object = {
      id: owner.id,
      login: owner.display_login,
      enterprise_id: enterprise.id,
    }

    deliver_raw owner_object, status: 201
  end

  post "/staff/enterprises/classic/:slug/first-admin", operation_id: :internal do # rubocop:todo GitHub/ControlAccess
    @route_owner = "@github/external-identities"
    enterprise = Business.find_by(slug: params[:slug])
    return deliver_error 404, message: "Enterprise not found" if enterprise.nil?

    return deliver_error 400, message: "Enterprise is not a classic enterprise" if enterprise.enterprise_managed?
    return deliver_error 400, message: "Enterprise already has an owner" if enterprise.owners.any?

    params = receive(Hash).with_indifferent_access

    if params[:email].blank? && params[:login].blank?
      deliver_error! 400, message: "Email or login is required"
    end

    if params[:email].present? && params[:login].present?
      deliver_error! 400, message: "Email and login cannot both be present"
    end

    user = nil

    if params[:login].present?
      user = User.find_by_login(params[:login])
    else
      if !User.valid_email?(params[:email])
        deliver_error! 400, message: "Email is invalid"
      end
      user = User.find_by_email(params[:email])
    end

    deliver_error! 400, message: "User not found" if user.nil?

    deliver_error! 400, message: "Owner must be a user" unless user.user?



    begin
      enterprise.add_owner(user, actor: nil, send_email_notification: true)
    rescue Business::UserHasNoExternalIdentityError, Business::UserHasTwoFactorDisabledError
      Business::InvalidAdminStateError => error
      deliver_error! 400, message: error.message
    end
    owner_object = {
      id: user.id,
      login: user.display_login,
      enterprise_id: enterprise.id,
    }

    deliver_raw owner_object, status: 201
  end

  post "/staff/enterprises/emu/:slug/reset-first-admin", operation_id: :internal do # rubocop:todo GitHub/ControlAccess
    @route_owner = "@github/external-identities"
    enterprise = Business.find_by(slug: params[:slug])
    return deliver_error 404, message: "Enterprise not found" if enterprise.nil?
    return deliver_error 400, message: "Enterprise is not an EMU enterprise" if enterprise.default_managed?
    return deliver_error 400, message: "Enterprise already has members" if enterprise.user_accounts.many?

    begin
      owner = enterprise.reset_first_emu_owner
    rescue Business::UnableToFindExistingAdminUserError => error
      deliver_error! 400, message: error.message
    end

    owner_object = {
      id: owner.id,
      login: owner.display_login,
      enterprise_id: enterprise.id
    }

    deliver_raw owner_object, status: 201
  end

  post "/staff/enterprises/classic/:slug/reset-first-admin", operation_id: :internal do # rubocop:todo GitHub/ControlAccess
    @route_owner = "@github/external-identities"
    enterprise = Business.find_by(slug: params[:slug])
    return deliver_error 404, message: "Enterprise not found" if enterprise.nil?

    return deliver_error 400, message: "Enterprise is not a classic enterprise" if enterprise.enterprise_managed?
    return deliver_error 400, message: "Unable to reset admin" if enterprise.owners.none?
    return deliver_error 400, message: "Enterprise already has members" if enterprise.user_accounts.many?

    params = receive(Hash).with_indifferent_access

    if params[:email].blank? && params[:login].blank?
      deliver_error! 400, message: "Email or login is required"
    end

    if params[:email].present? && params[:login].present?
      deliver_error! 400, message: "Email and login cannot both be present"
    end

    user = nil

    if params[:login].present?
      user = User.find_by_login(params[:login])
    else
      if !User.valid_email?(params[:email])
        deliver_error! 400, message: "Email is invalid"
      end
      user = User.find_by_email(params[:email])
    end

    deliver_error! 400, message: "User not found" if user.nil?

    deliver_error! 400, message: "Owner must be a user" unless user.user?


    current_owner = enterprise.owners.first
    return deliver_error 400, message: "User is not the first owner of the enterprise account" if current_owner.id != user.id

    reset = PasswordReset.create(
      user: current_owner,
      email: current_owner.outbound_email,
      force: true,
      expires: 7.days.from_now,
    )

    return deliver_error 400, message: "Unable to reset password for #{current_owner.display_login}" unless reset.valid?

    owner_object = {
      id: current_owner.id,
      login: current_owner.display_login,
      enterprise_id: enterprise.id,
    }

    deliver_raw owner_object, status: 201
  end


  def validate_required_emu_enterprise_params_present(params)
    errors = []
    if params[:name].blank?
      errors.push "Enterprise name is required"
    end
    if params[:slug].blank?
      errors.push "Enterprise slug is required"
    end
    if params[:shortcode].blank?
      errors.push "Enterprise shortcode is required"
    end
    if params[:seats].blank?
      errors.push "Enterprise seats is required"
    end
    if params[:seats].to_i < 0
      errors.push "Enterprise seats must be zero or greater"
    end
    if params[:billing_end_date].blank?
      errors.push "Enterprise billing end date is required"
    end
    if params[:billing_end_date]&.to_time.nil? || params[:billing_end_date]&.to_time.past?
      errors.push "Enterprise billing end date must be a date in the future of the format YYYY-MM-DD"
    end
    if params[:seats_plan_type].blank?
      errors.push "Enterprise seats plan type is required"
    end
    if params[:seats_plan_type] != "full" && params[:seats_plan_type] != "basic"
      errors.push "Enterprise seats plan type must be either full or basic"
    end
    if params[:seats_plan_type] == "basic" && params[:copilot_max_seats].blank?
      errors.push "Enterprise copilot max seats is required for basic seats plan type"
    end

    unless errors.empty?
      deliver_error! 400, message: errors.join("; ")
    end
  end

  def validate_required_classic_enterprise_params_present(params)
    errors = []
    if params[:name].blank?
      errors.push "Enterprise name is required"
    end
    if params[:slug].blank?
      errors.push "Enterprise slug is required"
    end
    if params[:seats].blank?
      errors.push "Enterprise seats is required"
    end
    if params[:seats].to_i < 0
      errors.push "Enterprise seats must be zero or greater"
    end
    if params[:billing_end_date].blank?
      errors.push "Enterprise billing end date is required"
    end
    if params[:billing_end_date]&.to_time.nil? || params[:billing_end_date]&.to_time.past?
      errors.push "Enterprise billing end date must be a date in the future of the format YYYY-MM-DD"
    end
    if params[:seats_plan_type].blank?
      errors.push "Enterprise seats plan type is required"
    end
    if params[:seats_plan_type] != "full" && params[:seats_plan_type] != "basic"
      errors.push "Enterprise seats plan type must be either full or basic"
    end
    if params[:seats_plan_type] == "basic" && params[:copilot_max_seats].blank?
      errors.push "Enterprise copilot max seats is required for basic seats plan type"
    end

    unless errors.empty?
      deliver_error! 400, message: errors.join("; ")
    end
  end

  def create_emu_business_hash(params)
    ghec_seats = nil
    if params[:seats_plan_type] == "basic"
      ghec_seats = 0
    else
      ghec_seats = params[:seats].to_i
    end
    {
      name: params[:name],
      slug: params[:slug],
      shortcode: params[:shortcode],
      staff_owned: false,
      seats: ghec_seats,
      business_type: "enterprise_managed",
      seats_plan_type: params[:seats_plan_type],
      customer_attributes: { billing_end_date: params[:billing_end_date].to_time, name: params[:name], billing_type: "invoice", billing_attempts: 0, term_length: 12 },
      any_length_shortcode_feature_flag_enabled: false,
      owners: []
    }
  end

  def create_classic_business_hash(params)
    ghec_seats = nil
    if params[:seats_plan_type] == "basic"
      ghec_seats = 0
    else
      ghec_seats = params[:seats].to_i
    end
    {
      name: params[:name],
      slug: params[:slug],
      staff_owned: false,
      seats: ghec_seats,
      business_type: "default_managed",
      seats_plan_type: params[:seats_plan_type],
      customer_attributes: { billing_end_date: params[:billing_end_date].to_time, name: params[:name], billing_type: "invoice", billing_attempts: 0, term_length: 12 },
      owners: []
    }
  end

  def onboard_to_billing_platform(current_user, business)
    GitHub.dogstats.increment("billing_platform.onboard_standalone_sales_serve_to_billing_platform")

    T.must(business.customer).update!(metered_plan: true)
    business.customer.onboard_to_billing_platform(
      products: [
        ::Billing::OnboardCustomerToProductInBillingPlatformJob::ProductEnum::Actions.serialize,
        ::Billing::OnboardCustomerToProductInBillingPlatformJob::ProductEnum::Codespaces.serialize,
        ::Billing::OnboardCustomerToProductInBillingPlatformJob::ProductEnum::Copilot.serialize,
        ::Billing::OnboardCustomerToProductInBillingPlatformJob::ProductEnum::Git_Lfs.serialize,
        ::Billing::OnboardCustomerToProductInBillingPlatformJob::ProductEnum::Packages.serialize,
        ::Billing::OnboardCustomerToProductInBillingPlatformJob::ProductEnum::Ghec.serialize,
        ::Billing::OnboardCustomerToProductInBillingPlatformJob::ProductEnum::Ghas.serialize
      ]
    )
  end
end
