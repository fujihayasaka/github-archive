# typed: true
# frozen_string_literal: true

# Creates a new Business, optionally with a single initial organization. If the provided
# organization is changing to the Business Plus plan, also sets up billing for
# that organization. Also responsible for setting up a business's customer relation.
#
# See also SeatsController#switch, Stafftools::BusinessController#create
class Business::Creator
  include ActionView::Helpers

  attr_reader :business_params, :organization, :organization_plan, :error_message, :require_owners
  attr_writer :organization
  attr_writer :organization_plan
  attr_accessor :actor, :settings_to_transfer

  # business_params   - hash of fields to set on new Business
  # organization      - the Organization joining the new Business
  # organization_plan - if the organization is changing plans in this same request, their desired plan
  # require_owners    - Boolean indicating whether the Business must be created with initial owners
  # actor             - User representing the actor
  # settings_to_transfer - Array of Hash of settings to transfer from org to enterprise.
  # billing_full_name - Full name of the billing contact
  # marketing_consent - Boolean indicating whether the billing contact has given marketing consent
  def initialize(
    business_params:,
    organization: nil,
    organization_plan: nil,
    require_owners: true,
    actor: nil,
    settings_to_transfer: [],
    # The following fields are only used for Salesforce
    billing_full_name: nil,
    marketing_consent: nil
  )
    @business_params = business_params
    # TODO check if we're already sending customer attributes here? we should be...
    @actor = actor
    @organization = organization
    @organization_plan = GitHub::Plan.find(
      organization_plan,
      account: organization,
    )
    @organization_plan ||= organization&.plan
    @require_owners = require_owners

    @error_message = nil
    @business = nil
    @settings_to_transfer = settings_to_transfer

    @billing_full_name = billing_full_name
    @marketing_consent = marketing_consent
  end

  def valid?
    if organization
      unless business_params.present?
        # An org is changing its plan but isn't
        # upgrading to a business (or already belongs to one). We're "valid"
        # in that we don't have anything to create and save! becomes a no-op
        if !organization.business && organization_plan.business_plus?
          @error_message = "An enterprise account is required for the #{GitHub::Plan.business_plus.titleized_display_name} plan"
          return false
        else
          return true
        end
      end

      unless organization_plan.business_plus?
        @error_message = "Enterprise accounts can only be created on the #{GitHub::Plan.business_plus.titleized_display_name} plan"
        return false
      end

      if organization.business
        @error_message = "Organization already belongs to an enterprise"
        return false
      end

      if organization.upgrade_to_enterprise_in_progress?
        @error_message = "Organization has already initiated an upgrade to the Enterprise plan"
        return false
      end

      unless business.has_sufficient_licenses_for_organization?(organization)
        @error_message = "Not enough seats to add the organization to the enterprise account. " +
        "Please contact sales at #{GitHub.enterprise_web_url}/contact" +
        " to add more seats before proceeding"
        return false
      end
    else
      unless business_params.present?
        @error_message = "Enterprise account information required."
        return false
      end

      if metered_ghe? && !metered_ghec_trial? && business.seats > 0
        @error_message = "Metered plans cannot have seats."
        return false
      end
    end

    if require_owners && owners.blank?
      @error_message = "An Enterprise account needs at least one owner"
      return false
    end

    begin
      if business.valid?
        true
      else
        @error_message = business.errors.full_messages.to_sentence
        false
      end
    rescue ArgumentError => e
      if e.message.include? "is not a valid business_type"
        @error_message = "Invalid business type"
      else
        @error_message = "Invalid parameters"
      end
      false
    end
  end

  def business_attributes
    business_params.merge(
      customer_attributes: {
        billing_end_date: billing_end_date,
        name: business_params[:name],
        metered_ghe: business_params.dig(:customer_attributes, :metered_ghe) || false,
        billing_type: business_params.dig(:customer_attributes, :billing_type) || "card",
        billing_attempts: 0,
        term_length: business_params.dig(:customer_attributes, :term_length) || 12,
      })
  end

  def owners
    business_params[:owners]
  end

  def billing_email
    business_params[:billing_email]
  end

  def billing_end_date
    business_params.dig(:customer_attributes, :billing_end_date) || GitHub::Billing.today + 1.year
  end

  def business
    return @business if @business
    return nil unless business_params.present?

    business = Business.new(business_attributes)

    business.seats = business_params.fetch(:seats, organization&.default_seats)

    # N.B. this field will eventually be retired
    business.billing_term_ends_at = billing_end_date
    @business = business
  end

  def save!
    unless valid?
      raise ArgumentError, @error_message
    end
    return unless business

    if organization
      business.attach_organization_for_upgrade(organization, actor, settings_to_transfer: settings_to_transfer)
    else
      business.save!
    end
    business.instrument_create_trial(
      actor,
      organization,
      billing_full_name: @billing_full_name,
      marketing_consent: @marketing_consent,
    )

    # Experiment - Wait for replication lag on mysql1 for at most 2s
    # mysql1 stores the installation data, that launch relies on.
    # mysql1 is the default cluster the waiter will wait on, no need to specify it.
    waiter = WaitForReplication.new(Timestamp.from_time(Time.now), max_wait_seconds: 2)
    begin
      waiter.wait!
      GitHub::Logger::log(
        msg: "Business::Creator: waited for replication",
        fn: "Business::Creator#save!",
        business_id: business.id,
        waited: waiter.waited,
      )
    rescue WaitForReplication::DataUnavailable => e
      GitHub::Logger::log(
        msg: "Business::Creator: timed out waiting for replication",
        fn: "Business::Creator#save!",
        business_id: business.id,
        waited: waiter.waited,
        error: e.message,
      )
    end
    true
  end

  private

  def metered_ghec_trial?
    metered_ghe? &&
      business_params[:trial_expires_at].present?
  end

  def metered_ghe?
    business_params.dig(:customer_attributes, :metered_ghe).to_s == "true"
  end
end
