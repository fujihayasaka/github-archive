# typed: true
# frozen_string_literal: true
module TeamSync
  class SetupFlow
    include Instrumentation::Model
    STARTING_STATES = %w(unknown pending disabled)
    APPROVAL_STATE = "ready"
    ENABLED_STATE = "enabled"

    STATE_TOKEN_SCOPE = "TeamSync:setup:%s"

    delegate :provider_id, to: :tenant
    delegate :provider_type, to: :tenant
    delegate :status, to: :tenant
    delegate :status=, to: :tenant
    delegate :encrypted_ssws_token, to: :tenant
    delegate :url, to: :tenant

    attr_accessor :organization, :business, :actor
    attr_reader :service_client, :tenant

    def initialize(organization: nil, business: nil, actor:, service_client: GroupSyncer.client)
      raise ArgumentError.new("must specify one of organization or business") unless !!organization ^ !!business
      @organization = organization
      @business = business
      @actor = actor
      @tenant = tenant_owner.team_sync_tenant || tenant_owner.build_team_sync_tenant

      @service_client = service_client
    end

    def pending?
      %(pending).include?(status || "unknown")
    end

    def review_required?
      status == "ready"
    end

    def self.callback(token:, provider_id:, actor:)
      parsed_token = get_token(token, provider_id)
      return nil, :invalid_state unless parsed_token.valid?

      global_relay_id = parsed_token.data["global_relay_id"]
      type, tenant_owner_id = Platform::Helpers::NodeIdentification.from_global_id(global_relay_id)

      # TODO: validate provider_type matches saved provider_type
      # to prevent invariant where callback is called with different provider type

      case type
      when "Organization"
        org = Organization.find(tenant_owner_id)
        new(organization: org, actor: actor)
      when "Enterprise"
        business = Business.find(tenant_owner_id)
        new(business: business, actor: actor)
      else
        [nil, :invalid_state]
      end
    end

    def initiate_setup(provider_type:, provider_id:, encrypted_ssws_token: nil, url: nil)
      return :invalid_state_transition unless tenant.status.nil? || STARTING_STATES.include?(tenant.status)
      return :invalid_provider_type unless TeamSync::Tenant::PROVIDER_TYPE_MAP.key?(provider_type)
      return :invalid_provider_id unless provider_id.present?

      # Save the provider type and id so we have it when we start setup.
      tenant.update(
        provider_type: provider_type,
        provider_id: provider_id,
        status: "pending",
        encrypted_ssws_token: encrypted_ssws_token,
        url: url,
      )

      # Integration app is not installed on a business, but rather on each of
      # its orgs (once setup is completed, when they join the business, etc.)
      trigger_app_installation if organization

      instrument "setup_initiated"
      nil # no error
    end

    def generate_setup_lease_token
      # register with provider_type with group_syncer so service knows the correct adapter to use for the tenant
      # which affects the setup_url returned
      err = tenant.register
      return err, :registration_error if err.present?

      generate_token
    end

    def setup_callback(provider_type:, params:)
      return :invalid_state_transition unless tenant.status == "pending"
      return :admin_consent_failed unless params.fetch("admin_consent", "False").downcase == "true"

      provider_id = params[:tenant]

      # validate given provider_type matches saved provider type
      return :provider_type_mismatch unless provider_type == tenant.provider_type

      success = tenant.update(
        # persist provider_id (check valid provider_type)
        provider_id: provider_id,
        # change state to ready (pending approval)
        status: "ready",
      )
      return :tenant_update_failed if !success

      instrument "ready_for_review"
      nil # no error
    end

    def approve
      return :invalid_state_transition unless self.status == APPROVAL_STATE

      # change state to enabled
      tenant.update(status: "enabled")

      # register tenant provider type, ID
      err = tenant.register
      return :registration_error, err if err.present?

      # configure tenants for organizations in business, if needed
      if business.present?
        business.organizations.each do |org|
          UpdateTeamSyncForBusinessOrganizationJob.perform_later(org_id: org.id)
        end
      end

      instrument "enabled"
      nil # no error
    end

    def cancel
      return :invalid_state_transition unless %w(ready).include?(self.status)
      tenant.update(status: "pending")
      err = tenant.register
      return :registration_error, err if err.present?

      instrument "setup_canceled"
      nil # no error
    end

    def disable
      return :invalid_state_transition unless %w(enabled).include?(self.status)

      # change state to disabled
      tenant.disable

      # register tenant as disabled
      err = tenant.register
      return :registration_error, err if err.present?

      # disable tenants for organizations in business, if needed
      if business.present?
        business.organizations.each do |org|
          UpdateTeamSyncForBusinessOrganizationJob.perform_later(org_id: org.id)
        end
      end

      instrument "disabled"
      nil # no error
    end

    def setup_url(redirect_uri:, token:)
      return nil unless tenant.setup_url_template.present?
      template = Addressable::Template.new(URI.decode_www_form_component(tenant.setup_url_template))
      template.expand(
        tenant: tenant.provider_id,
        state: token,
        redirect_uri: redirect_uri,
      )
    end

    def reload
      tenant.reload
    end

    def reset
      tenant.destroy if tenant
    end

    def self.get_token(token, provider_id)
      GitHub::Authentication::SignedAuthToken.verify(
        scope: STATE_TOKEN_SCOPE % provider_id,
        token: token,
      )
    end

    def get_token(token)
      self.class.get_token(token, provider_id)
    end

    private

    def tenant_owner
      business || organization
    end

    def event_prefix
      :team_sync_tenant
    end

    def event_payload
      owner = @business ? { "business": business } : { "org": organization }
      owner.merge(
        {
          provider_type: provider_type,
          actor: actor,
          status: status,
        },
      )
    end

    def trigger_app_installation
      AutomaticAppInstallation.trigger(
        type: :team_sync_enabled,
        originator: organization,
        actor: actor,
      )
    end

    def generate_token
      GitHub::Authentication::SignedAuthToken.generate(
        user: actor,
        scope: STATE_TOKEN_SCOPE % provider_id,
        expires: 1.week.from_now,
        data: {
          global_relay_id: tenant_owner.global_relay_id,
          provider_type: provider_type,
        })
    end
  end
end
