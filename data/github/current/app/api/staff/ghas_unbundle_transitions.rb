# typed: true
# frozen_string_literal: true

class Api::Staff::GhasUnbundleTransitions < Api::Staff::App
  before do
    deliver_error! 404 if GitHub.enterprise? || GitHub.multi_tenant_enterprise?
  end

  get "/staff/ghas_unbundle_transitions/:business_slug", operation_id: :internal do # rubocop:todo GitHub/ControlAccess
    @route_owner = "@github/licensing"

    business = Business.find_by(slug: params[:business_slug])
    deliver_error!(422, message: "Business cannot be found.") unless business.present?

    ghas_unbundle_transition = Licensing::GhasUnbundleTransition.where(customer_id: business.customer_id).order(created_at: :asc).last

    deliver_raw payload(ghas_unbundle_transition, business), status: 200
  end

  # rubocop:disable GitHub/DuplicateRoutesAreDefinedTogether
  post "/staff/ghas_unbundle_transitions/:business_slug", operation_id: :internal do # rubocop:todo GitHub/ControlAccess
    @route_owner = "@github/licensing"

    business = Business.find_by(slug: params[:business_slug])
    deliver_error!(422, message: "Business cannot be found.") unless business.present?

    data = T.let(attr(receive(Hash), :transition_date, :sfdc_account_url, :code_security_enablement_strategy), T::Hash[T.any(Symbol, String), T.untyped])
    if data[:sfdc_account_url].blank?
      deliver_error!(422, message: "Validation failed: Sfdc account url can't be blank")
    end
    if !strategy_valid?(data[:code_security_enablement_strategy])
      deliver_error!(422, message: "Validation failed: '#{data[:code_security_enablement_strategy]}' is not a valid strategy")
    end
    data[:customer_id] = business.customer_id
    data[:status] = "scheduled"
    data[:actor] = current_user

    begin
      ghas_unbundle_transition = Licensing::GhasUnbundleTransition.create!(data)
    rescue ActiveRecord::RecordInvalid => e
      deliver_error!(422, message: e.message)
    rescue ActiveRecord::RecordNotUnique => _e
      deliver_error!(422, message: "A transition for this customer already exists.")
    end

    payload = payload(ghas_unbundle_transition, business)

    if ghas_unbundle_transition.transition_date == Date.current && ghas_unbundle_transition.scheduled?
      ghas_unbundle_transition.enqueue
    end

    deliver_raw payload, status: 200
  end

  # rubocop:disable GitHub/DuplicateRoutesAreDefinedTogether
  patch "/staff/ghas_unbundle_transitions/:business_slug", operation_id: :internal do # rubocop:todo GitHub/ControlAccess
    @route_owner = "@github/licensing"

    business = Business.find_by(slug: params[:business_slug])
    deliver_error!(422, message: "Business cannot be found.") unless business.present?

    ghas_unbundle_transition = Licensing::GhasUnbundleTransition.where(customer_id: business.customer_id).order(transition_date: :asc).last
    deliver_error!(422, message: "Transition cannot be found.") unless ghas_unbundle_transition.present?

    data = T.let(attr(receive(Hash), :status, :transition_date, :sfdc_account_url, :code_security_enablement_strategy), T::Hash[T.any(Symbol, String), T.untyped])
    if data[:status].present?
      deliver_error!(422, message: "Only scheduled or cancelled transitions can be modified, please create a new transition.") unless ghas_unbundle_transition.scheduled? || ghas_unbundle_transition.cancelled?
      deliver_error!(422, message: "Status must be either 'cancelled' or 'scheduled'") unless %w[cancelled scheduled].include?(data[:status])
    end
    if !strategy_valid?(data[:code_security_enablement_strategy])
      deliver_error!(422, message: "Validation failed: '#{data[:code_security_enablement_strategy]}' is not a valid strategy")
    end
    data[:actor] = current_user

    begin
      ghas_unbundle_transition.update!(data)
    rescue ActiveRecord::RecordInvalid => e
      deliver_error!(422, message: e.message)
    end

    payload = payload(ghas_unbundle_transition, business)

    if ghas_unbundle_transition.transition_date == Date.current && ghas_unbundle_transition.scheduled?
      ghas_unbundle_transition.enqueue
    end

    deliver_raw payload, status: 200
  end

  private

  def payload(ghas_unbundle_transition, business)
    result = {
      customer_id: business.customer_id,
      status: ghas_unbundle_transition&.status,
      transition_date: ghas_unbundle_transition&.transition_date,
      actor: ghas_unbundle_transition&.actor&.name,
      sfdc_account_url: ghas_unbundle_transition&.sfdc_account_url,
      code_security_enablement_strategy: ghas_unbundle_transition&.code_security_enablement_strategy
    }

    result[:error_message] = ghas_unbundle_transition&.message if ghas_unbundle_transition&.message.present?

    result
  end

  sig { params(strategy: T.nilable(String)).returns(T::Boolean) }
  def strategy_valid?(strategy)
    return true if strategy.blank?

    Licensing::GhasUnbundleTransition.code_security_enablement_strategies.keys.include?(strategy)
  end
end
