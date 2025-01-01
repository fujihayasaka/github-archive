# typed: true
# frozen_string_literal: true

class Api::Staff::LicensingModelTransitions < Api::Staff::App
  before do
    deliver_error! 404 if GitHub.enterprise? || GitHub.multi_tenant_enterprise?
    deliver_error! 404 unless current_user.feature_enabled?(:license_model_transitions_api)
  end

  get "/staff/licensing_model_transitions/:business_slug", operation_id: :internal do # rubocop:todo GitHub/ControlAccess
    @route_owner = "@github/licensing"
    business = Business.find_by(slug: params[:business_slug])
    deliver_error!(422, message: "Business cannot be found.") unless business.present?
    ghas_only = params[:ghas_only]&.to_s == "true"

    if ghas_only
      licensing_model_transition = Licensing::LicensingModelTransition.where(customer_id: business.customer_id, ghas_only: true).order(created_at: :asc).last
    else
      licensing_model_transition = Licensing::LicensingModelTransition.where(customer_id: business.customer_id, ghas_only: false).order(created_at: :asc).last
    end

    deliver_raw payload(licensing_model_transition, business, ghas_only), status: 200
  end

  # rubocop:disable GitHub/DuplicateRoutesAreDefinedTogether
  post "/staff/licensing_model_transitions/:business_slug", operation_id: :internal do # rubocop:todo GitHub/ControlAccess
    @route_owner = "@github/licensing"

    business = Business.find_by(slug: params[:business_slug])
    deliver_error!(422, message: "Business cannot be found.") unless business.present?

    data = T.let(attr(receive(Hash), :transition_date, :licensing_model, :ghas_only, :reset_ghas_configuration), T::Hash[T.untyped, T.untyped])
    data[:ghas_only] = data[:ghas_only]&.to_s == "true"
    data[:customer_id] = business.customer_id
    data[:status] = "scheduled"
    data[:actor] = current_user
    begin
      licensing_model_transition = Licensing::LicensingModelTransition.create!(data)
    rescue ActiveRecord::RecordInvalid => e
      deliver_error!(422, message: e.message)
    end

    payload = payload(licensing_model_transition, business, licensing_model_transition.ghas_only)

    if licensing_model_transition.transition_date == Date.current && licensing_model_transition.scheduled?
      licensing_model_transition.enqueue
    end

    deliver_raw payload, status: 200
  end

  # rubocop:disable GitHub/DuplicateRoutesAreDefinedTogether
  patch "/staff/licensing_model_transitions/:business_slug", operation_id: :internal do # rubocop:todo GitHub/ControlAccess
    @route_owner = "@github/licensing"
    business = Business.find_by(slug: params[:business_slug])
    deliver_error!(422, message: "Business cannot be found.") unless business.present?

    licensing_model_transition = Licensing::LicensingModelTransition.scheduled.where(customer_id: business.customer_id).order(transition_date: :asc).last
    deliver_error!(422, message: "Only scheduled transitions can be modified, please create a new transition.") unless licensing_model_transition&.scheduled?

    data = attr(receive(Hash), :status, :transition_date, :reset_ghas_configuration)
    data[:actor] = current_user
    data.delete(:reset_ghas_configuration) if data[:reset_ghas_configuration].nil?
    deliver_error!(422, message: "Status must be either 'cancelled' or 'scheduled'") unless %w[cancelled scheduled].include?(data[:status])

    begin
      licensing_model_transition.update!(data)
    rescue ActiveRecord::RecordInvalid => e
      deliver_error!(422, message: e.message)
    end

    payload = payload(licensing_model_transition, business, licensing_model_transition.ghas_only)

    if licensing_model_transition.transition_date == Date.current && licensing_model_transition.scheduled?
      licensing_model_transition.enqueue
    end

    deliver_raw payload, status: 200
  end

  private

  def payload(licensing_model_transition, business, ghas_only)
    result = {
      customer_id: business.customer_id,
      status: licensing_model_transition&.status,
      transition_date: licensing_model_transition&.transition_date,
      licensing_model: licensing_model_transition&.licensing_model,
      reset_ghas_configuration: licensing_model_transition&.reset_ghas_configuration,
      actor: licensing_model_transition&.actor&.name,
      ghas_only: licensing_model_transition&.ghas_only
    }

    result[:error_message] = licensing_model_transition&.message if licensing_model_transition&.message.present?

    if ghas_only
      if business.advanced_security_metered_for_entity?
        result[:can_transition_to_volume] = false
        result[:issues_preventing_transition] = "Business is already on metered billing for GHAS"
      else
        result[:can_transition_to_metered] = business.eligible_for_metered_ghas?
        unless result[:can_transition_to_metered]
          result[:issues_preventing_transition] = business.issues_preventing_ghas_transition
        end
      end
    else
      if business.metered_plan?
        result[:can_transition_to_volume] = true
      else
        result[:can_transition_to_metered] = business.eligible_for_metered_licensing?
        unless result[:can_transition_to_metered]
          result[:issues_preventing_transition] = business.issues_preventing_transition
        end
      end
    end

    result
  end
end
