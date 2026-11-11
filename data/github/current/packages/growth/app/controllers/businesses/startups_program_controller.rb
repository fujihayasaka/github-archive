# typed: strict
# frozen_string_literal: true

class Businesses::StartupsProgramController < ::Businesses::BusinessController
  include GitHub::RateLimitedRequest

  before_action :dotcom_required
  before_action :login_required

  rate_limit_requests \
    only: :create,
    key: :gfs_apply_rate_limit_key,
    max: 5,
    ttl: 1.hour.to_i

  helper_method :startup_program_enterprise_account_options
  helper_method :startup_program_enterprise_accounts_and_ineligibility_reasons
  helper_method :valid_partner_id?
  helper_method :company_emails
  helper_method :proof_of_funding_required?

  depends_on_clusters ApplicationRecord::Mysql1
  depends_on_clusters ApplicationRecord::Collab
  depends_on_clusters ApplicationRecord::IamAbilities
  depends_on_clusters ApplicationRecord::Billing

  CLUSTER_DEPENDENCIES_ALLOWED_NON_GET_REQUESTS = T.let([
    "#{self}#create"
  ].freeze, T::Array[String])

  sig { void }
  def new
    render "startups_program/new"
  end

  sig { void }
  def create
    form_data = params
      .require(:startup_application)
      .permit(BusinessStartupsProgram::Application::FORM_PARAMS)
      .to_h

    business = Business.find_by(id: form_data["business_id"].to_i)
    return render_404 unless business&.owner?(current_user)

    startup_application = BusinessStartupsProgram::Application.new(form_data.merge(user: current_user, business:))

    return render_unprocessable_entity(startup_application) unless startup_application.valid?

    startups_program = BusinessStartupsProgram.find_or_create_by!(business: business)
    startups_program.update!(
      application_status: :processing,
      submitted_at: Time.current,
      payment_card_fingerprint: business.customer&.payment_method&.card_fingerprint,
      payment_azure_subscription_id: business.customer&.azure_subscription_id,
      application_data: form_data.merge("user_id" => current_user.id, "partner_id" => T.unsafe(startup_application).partner_id)
    )

    GlobalInstrumenter.instrument("business_startups_program.submitted", {
      application: startups_program,
      business: business,
      actor: current_user,
    })

    if FeatureFlag.vexi.enabled?(:gfs_auto_approval, default: false)
      BusinessStartupsApplicationProcessingJob.perform_later(business_startups_program_id: startups_program.id)
    end

    redirect_to enterprise_startups_thanks_path
  end

  sig { void }
  def show
    render "startups_program/show"
  end

  private

  sig { returns(T::Array[T::Array[Object]]) }
  memoize def startup_program_enterprise_account_options
    startup_program_enterprise_accounts_and_ineligibility_reasons.map do |business, reasons|
      if reasons.any?
        invalid_label = reasons.map { |reason| "invalid: #{reason}" }.join(", ")
        ["#{business.slug} (#{invalid_label})", business.id, { disabled: true }]
      else
        [business.slug, business.id]
      end
    end
  end

  sig { returns(T::Array[[Business, T::Array[String]]]) }
  memoize def startup_program_enterprise_accounts_and_ineligibility_reasons
    businesses = current_user
      .businesses(membership_type: :admin)
      .includes(:customer, :startups_program)
      .limit(100)
      .sort_by(&:slug)
    businesses.map do |business|
      [business, BusinessStartupsProgram::Application.business_ineligibility_reasons(business)]
    end
  end

  sig { params(startup_application: BusinessStartupsProgram::Application).void }
  def render_unprocessable_entity(startup_application)
    render "startups_program/new", status: :unprocessable_entity, locals: { startup_application: startup_application }
  end

  sig { returns(T::Array[String]) }
  memoize def company_emails
    BusinessStartupsProgram::Application.company_emails(current_user)
  end

  sig { params(partner_id: String).returns(T::Boolean) }
  def valid_partner_id?(partner_id)
    BusinessStartupsProgram::Partners.valid?(partner_id)
  end

  sig { returns(T::Boolean) }
  def proof_of_funding_required?
    !FeatureFlag.vexi.enabled?(:gfs_remove_proof_of_funding, default: false)
  end

  sig { returns(String) }
  def gfs_apply_rate_limit_key
    "gfs_apply:#{current_user.id}"
  end
end
