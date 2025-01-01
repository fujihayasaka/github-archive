# typed: strict
# frozen_string_literal: true

module AdvancedSecurityEntrypointHelper

  sig do
    params(
      organization: T.nilable(Organization),
      user: T.nilable(User),
    ).returns(Symbol)
  end
  def show_advanced_security_entrypoint?(organization:, user:)
    return :do_not_show unless organization.present?
    return :do_not_show unless user.present?
    return :do_not_show unless organization.advanced_security_eligible_for_entity?

    entity = organization
    if organization.delegate_billing_to_business?
      entity = T.must(organization.business)
    end

    return :do_not_show unless entity.adminable_by?(user)
    return :do_not_show if entity.advanced_security_purchased_for_entity?

    # self-serve
    if entity.is_a?(Business) && entity.self_serve_payment?
      return :do_not_show unless entity.eligible_for_self_serve_advanced_security_trial?
      return :self_serve
    end

    # sales-serve
    return :do_not_show if entity.get_advanced_security_trial_expires_at.present?
    :sales_serve
  end
end
