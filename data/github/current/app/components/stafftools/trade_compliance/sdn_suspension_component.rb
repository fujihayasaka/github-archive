# typed: strict
# frozen_string_literal: true

class Stafftools::TradeCompliance::SdnSuspensionComponent < ApplicationComponent
  include Stafftools::AccessControlHelper
  include Stafftools::TradeComplianceHelper

  sig { params(target: Billing::Types::Account).void }
  def initialize(target:)
    @target = target
  end

  private

  sig { returns(Billing::Types::Account) }
  attr_reader :target

  sig { returns(T::Boolean) }
  def authorized_staffer?
    controller = Stafftools::Users::TradeCompliance::SdnSuspensionController

    stafftools_action_authorized?(controller: controller, action: :create)
  end

  sig { returns(String) }
  def form_path
    if target.user? || target.organization?
      stafftools_user_trade_compliance_sdn_suspension_path(target)
    else
      stafftools_enterprise_trade_compliance_sdn_suspension_path(target)
    end
  end

  sig { returns(Symbol) }
  def form_method
    return :delete if target.sdn_suspended?
    :post
  end

  sig { returns(String) }
  def prefix
    return "un" if target.sdn_suspended?
    ""
  end

  sig { returns(String) }
  def title
    return "SDN Unsuspend Account" if target.sdn_suspended?
    "SDN Suspend Account"
  end

  sig { returns(String) }
  def repository_count
    target = self.target
    return "" if target.is_a?(Business)
    body = <<~BODY
      <li #{ test_selector("repositories-count") } >
        has <b>#{ target.repository_counts.total_repositories }</b> repositories<br>
      </li>
    BODY

    sanitize(body, attributes: %w(data-test-selector))
  end

  sig { returns(String) }
  def member_count
    target = self.target
    return "" unless target.is_a?(Organization) || target.is_a?(Business)
    body = <<~BODY
      <li #{ test_selector("members-count") }>
          has <b>#{ target.members_count }</b> members<br>
      </li>
    BODY

    sanitize(body, attributes: %w(data-test-selector))
  end

  sig { returns(String) }
  def organization_count
    return "" if target.organization?
    selector = target.user? ? "memberships-count" : "organizations-count"
    membership_text = target.user? ? "is a member of" : "has"
    body = <<~BODY
      <li #{ test_selector(selector) }>
          #{membership_text} <b>#{ target.organizations.count }</b> organizations<br>
      </li>
    BODY

    sanitize(body, attributes: %w(data-test-selector))
  end

  sig { returns(String) }
  def suspension_warning
    return "" if target.sdn_suspended?
    body = <<~BODY
      <p>Suspending an account will severely limit functionality.</p>
    BODY

    sanitize(body, attributes: %w(data-test-selector))
  end
end
