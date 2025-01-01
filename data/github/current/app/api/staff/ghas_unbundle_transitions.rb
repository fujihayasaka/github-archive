# typed: true
# frozen_string_literal: true

class Api::Staff::GhasUnbundleTransitions < Api::Staff::App
  before do
    deliver_error! 404 if GitHub.enterprise? || GitHub.multi_tenant_enterprise?
    deliver_error! 404 unless current_user.feature_enabled?(:ghas_unbundle_transitions)
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

    data = T.let(attr(receive(Hash), :transition_date), T::Hash[T.untyped, T.untyped])
    data[:customer_id] = business.customer_id
    data[:status] = "scheduled"
    data[:actor] = current_user
    begin
      ghas_unbundle_transition = Licensing::GhasUnbundleTransition.create!(data)
    rescue ActiveRecord::RecordInvalid => e
      deliver_error!(422, message: e.message)
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

    ghas_unbundle_transition = Licensing::GhasUnbundleTransition.scheduled.where(customer_id: business.customer_id).order(transition_date: :asc).last
    deliver_error!(422, message: "Only scheduled transitions can be modified, please create a new transition.") unless ghas_unbundle_transition&.scheduled?

    data = attr(receive(Hash), :status, :transition_date)
    data[:actor] = current_user
    deliver_error!(422, message: "Status must be either 'cancelled' or 'scheduled'") unless %w[cancelled scheduled].include?(data[:status])

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
    }

    result[:error_message] = ghas_unbundle_transition&.message if ghas_unbundle_transition&.message.present?

    result
  end
end
