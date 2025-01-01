# typed: true
# frozen_string_literal: true

# This API is called from Azure to interact with GitHub enterprises.
class Api::Internal::AzureEnterprises < Api::Internal
  include Api::App::EnterpriseCreationHelpers
  include Api::App::ErrorFormatting

  ALL_USERS_COPILOT_TEAM_NAME = "Azure DevOps Copilot"

  ALLOWED_GET_PARAMS = %i[tenant_id shortcode slug name].freeze

  COPILOT_EMU_ENTERPRISE_REQUIRED_PARAMS = %w[
    name
    slug
    shortcode
    admin_email
    subscription_id
    billing_country
  ].freeze

  before do
    deliver_error! 404 if GitHub.enterprise?
    deliver_error! 404 if GitHub.multi_tenant_enterprise?
  end

  # Maps internal model field names to their corresponding API parameter names.
  # This allows us to present consistent field names in API error responses that match
  # the parameter names clients use in their requests.
  #
  # Example:
  #   When a client sends:
  #   {
  #     "login_url": "https://example.com",
  #     "entra_identifier": "some-id",
  #     "certificate": "cert-data"
  #   }
  #
  #   The model stores these as:
  #   - sso_url
  #   - issuer
  #   - idp_certificate
  #
  #   This mapping ensures error responses use the API parameter names
  #   instead of internal model field names.
  FIELD_MAPPINGS = {
    "Business::SamlProvider" => {
      "sso_url" => "login_url",
      "issuer" => "entra_identifier",
      "idp_certificate" => "certificate"
    }
  }.freeze

  SAML_REQUIRED_PARAMS = %w[
    login_url
    entra_identifier
    certificate
  ].freeze

  def externally_accessible?
    # API should be accessible to Azure
    true
  end

  def require_request_hmac?
    # HMAC keys are stored in "GitHub.api_internal_azure_enterprises_hmac_keys"
    # which reads "API_INTERNAL_ENTRA_USER_LICENSED_FOR_GHE_HMAC_KEYS" environment variable
    true
  end

  def verify_request_hmac # rubocop:disable GitHub/ApiMethodsCallingDeliverBangMustHaveBangs
    unless hmac_authenticated_internal_service_request?
      headers["X-GLB-Rate-Limit"] = "true"
      headers[GitHub::Middleware::Constants::RETRY_AFTER] = "300"
      deliver_error! 403, errors: [api_domain_error(message: REQUEST_HMAC_INVALID)]
    end

    super
  end

  def authenticated_for_private_mode?
    true
  end

  post "/internal/azure/copilot/emu/enterprises", operation_id: :internal do
    @route_owner = "@github/external-identities"

    params = receive(Hash).with_indifferent_access
    params[:seats] = 0
    params[:seats_plan_type] = "basic"
    params[:copilot_max_seats] = 500000
    params[:billing_end_date] = 1.year.from_now.to_date.to_s

    business = Business.find_by(slug: params[:slug])
    business ||= create_copilot_emu_enterprise!(params)

    # Create the first admin owner for this enterprise if it doesn't already exist
    admin = find_or_create_first_emu_owner!(business, email: params[:admin_email])

    # Create the enterprise team that future provisioned users will be automatically added to if it doesn't already exist
    # If for some reason the team id returned from the config doesn't exist, we'll look for the ALL_USERS_COPILOT_TEAM_NAME
    # and set that in the config if it's found
    enterprise_team = find_or_create_all_users_copilot_team!(business, team_name: ALL_USERS_COPILOT_TEAM_NAME)

    # Set the AllUsersCopilotTeam configurable unless it's already correctly set.
    # This also kicks off the EnterpriseTeamAllUsersCopilotTeamJob
    # which handles the enterprise team assignment
    unless business.all_users_copilot_team_id == enterprise_team.id
      begin
        business.set_all_users_copilot_team(actor: admin, enterprise_team_id: T.must(enterprise_team).id)
      rescue Configurable::AllUsersCopilotTeam::AllUsersCopilotTeamError => error
        deliver_error! 400, errors: [api_domain_error(message: error.message)]
      end
    end

    # Instrument a new event here called "external_identity.enterprise_created"
    GlobalInstrumenter.instrument("external_identity.enterprise_created", {
      enterprise_id: business.id,
      name: business.name,
      website: params[:website],
      slug: business.slug,
      shortcode: business.shortcode,
      admin_email: params[:admin_email],
      enterprise_type: :EMU,
      seat_plan_type: :BASIC,
      subscription_id: params[:subscription_id],
      tp_id: params[:tp_id],
      billing_street: params[:billing_street],
      billing_city: params[:billing_city],
      billing_state: params[:billing_state],
      billing_zip: params[:billing_zip],
      billing_country: params[:billing_country],
      copilot_max_seats: params[:copilot_max_seats]
    })

    deliver_raw({
      id: business.id,
      name: business.name,
      slug: business.slug,
      shortcode: business.shortcode,
    }, status: 201)
  end

  post "/internal/azure/copilot/emu/enterprises/:enterprise_id/saml", operation_id: :internal do
    @route_owner = "@github/external-identities"

    business = find_enterprise!
    body_params = receive(Hash).with_indifferent_access
    existing_provider = business.saml_provider

    all_errors = []
    param_errors = validate_params_present(body_params, SAML_REQUIRED_PARAMS)
    all_errors.concat(param_errors)

    # Only proceed with model operations if we have all required params
    if param_errors.empty?
      immutable_login_url = existing_provider &&
                           existing_provider.sso_url != body_params[:login_url] &&
                           existing_provider.external_identities.any?

      if immutable_login_url
        all_errors << api_domain_error(
          field: "login_url",
          message: "Cannot change login_url when external identities exist"
        )
      end

      if existing_provider && !immutable_login_url
        existing_provider.assign_attributes(
          sso_url: body_params[:login_url],
          issuer: body_params[:entra_identifier],
          idp_certificate: body_params[:certificate]
        )

        unless existing_provider.save
          all_errors.concat(format_model_errors(existing_provider, FIELD_MAPPINGS))
        end
      else
        provider = business.build_saml_provider(
          sso_url: body_params[:login_url],
          issuer: body_params[:entra_identifier],
          idp_certificate: body_params[:certificate],
          scim_provisioning_state: :scim_provisioning_state_enabled,
          recovery_codes_viewed: true
        )

        unless provider.save
          all_errors.concat(format_model_errors(provider, FIELD_MAPPINGS))
        end
      end
    end

    if all_errors.any?
      deliver_error! 400, errors: all_errors
    else
      deliver_raw("", status: existing_provider ? 200 : 201)
    end
  end

  get "/internal/azure/copilot/emu/enterprises", operation_id: :internal do
    @route_owner = "@github/external-identities"

    validate_required_get_params_present!(params)

    return check_existing_tenant_id!(params[:tenant_id]) if params[:tenant_id].present?
    return check_existing_shortcode!(params[:shortcode]) if params[:shortcode].present?
    return check_existing_slug!(params[:slug]) if params[:slug].present?
    generate_business_slug_from_name(params[:name]) # params[:name] is guaranteed to be present
  end

  private

  def create_copilot_emu_enterprise!(params)
    validate_required_copilot_emu_enterprise_params!(params)

    business_hash = create_emu_business_hash(params)
    creator = Business::Creator.new(business_params: business_hash, require_owners: false)

    unless creator.valid?
      business_errors = format_model_errors(creator.business)
      message = business_errors.map { |error| "#{error[:field]} #{error[:message]}" }.join(", ")
      GitHub.logger.error(
        "code.namespace": self.class.name,
        "exception.message": message,
        "code.function": "create_copilot_emu_enterprise"
      )
      deliver_error! 400, errors: business_errors
    end

    creator.save!
    business = creator.business

    onboard_to_billing_platform(business, params[:subscription_id])
    set_business_copilot_max_seats(business, params)

    business
  end

  def validate_required_copilot_emu_enterprise_params!(params)
    param_errors = validate_params_present(params, COPILOT_EMU_ENTERPRISE_REQUIRED_PARAMS)

    unless User.valid_email?(params[:admin_email])
      param_errors << api_domain_error(
        field: "admin_email",
        message: "Enterprise admin email is invalid"
      )
    end

    unless param_errors.empty?
      deliver_error! 400, errors: param_errors
    end
  end

  # Looks for existing first emu owner, and returns it if found
  # Otherwise creates a new enterprise admin with the given email and returns it
  def find_or_create_first_emu_owner!(business, email:)
    unless admin = business.find_first_emu_owner
      begin
        admin = business.create_and_add_first_emu_owner(email: email, actor: nil, send_email_notification: true)
        unless admin
          deliver_error! 400, errors: [api_domain_error(message: "Failed to create the enterprise administrator")]
        end
      rescue ArgumentError, Business::UnableToCreateAdminUserError => error
        deliver_error! 400, errors: [api_domain_error(message: error.message)]
      end
    end

    admin
  end

  # Looks for existing all users copilot team by id and name, and returns it if found
  # Otherwise creates a new enterprise team with the given name and returns it
  def find_or_create_all_users_copilot_team!(business, team_name:)
    enterprise_team = EnterpriseTeam.find_by(id: business.all_users_copilot_team_id) if business.all_users_copilot_team_enabled?
    enterprise_team ||= EnterpriseTeam.find_by(business: business, name: team_name)
    unless enterprise_team.present?
      begin
        enterprise_team = EnterpriseTeams::Factory.create_enterprise_team(
          enterprise: business,
          team_name: team_name,
          sync_to_organizations: "disabled",
          idp_group_id: nil,
          is_security_manager: false,
        )
      rescue ActiveRecord::RecordInvalid => error
        deliver_error! 400, errors: [api_domain_error(message: error.message)]
      end
    end

    enterprise_team
  end

  def validate_required_get_params_present!(params)
    errors = []

    present_params_count = ALLOWED_GET_PARAMS.count { |allowed| params[allowed].present? }

    if present_params_count != 1
      allowed = ALLOWED_GET_PARAMS.join(", ")
      errors << api_domain_error(message: "Exactly one of #{allowed} must be provided")
    end

    unless errors.empty?
      deliver_error! 400, errors: errors
    end
  end

  # Check if there is an existing external provider already using this tenant id
  def check_existing_tenant_id!(tenant_id)
    existing_provider = Business::SamlProvider.where("sso_url LIKE ?", "https://login.microsoftonline.com/#{tenant_id}%").count > 0
    existing_provider ||= Organization::SamlProvider.where("sso_url LIKE ?", "https://login.microsoftonline.com/#{tenant_id}%").count > 0
    existing_provider ||= Business::OIDCProvider.where(tenant_id: tenant_id).count > 0

    if existing_provider
      deliver_empty status: 200
    else
      deliver_error! 404, errors: [api_domain_error(message: "Provider with tenant_id #{tenant_id} not found")]
    end
  end

  # Check if the shortcode is already in use
  def check_existing_shortcode!(shortcode)
    existing_business = Business.find_by(shortcode: shortcode)

    if existing_business.present?
      deliver_error! 409, errors: [api_domain_error(message: "Enterprise with shortcode #{shortcode} already exists")]
    else
      deliver_empty status: 200
    end
  end

  # check if the slug is already in use
  def check_existing_slug!(slug)
    existing_business = Business.find_by(slug: slug)

    if existing_business.present?
      deliver_error! 409, errors: [api_domain_error(message: "Enterprise with slug #{slug} already exists")]
    else
      deliver_empty status: 200
    end
  end

  # Generate a slug based on the name
  def generate_business_slug_from_name(name)
    slug = Business.unique_slug(name.parameterize)
    deliver_raw({ slug: slug }, status: 200)
  end
end
