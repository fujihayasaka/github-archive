# typed: strict
# frozen_string_literal: true

module Stafftools::TradeComplianceHelper
  include StafftoolsHelper
  extend T::Helpers

  abstract!

  sig { abstract.returns(T.untyped) }
  def current_user; end

  # Returns all trade compliance audit logs events
  sig { params(target: T.nilable(Billing::Types::Account)).returns(String) }
  def stafftools_audit_log_events_query(target: nil)
    actions = %w(
      trade_controls*
      trade_compliance*
      trade_screening*
      account_screening*
      org.trade_controls*
      org.trade_screening*
      org.account_screening*
      staff.trade_compliance*
    )

    query = if target
      stafftools_audit_log_query(target).dup
    else
      String.new("")
    end

    if driftwood_ade_query?(current_user)
      query = String.new("webevents | where ") unless target
      actions_string = actions.map do |action|
        if action.include?("*")
          "action startswith '#{action.gsub("*", "")}'"
        else
          "action == '#{action}'"
        end
      end.join(" or ")
      query << " and " if target
      query << "(#{actions_string})"
    else
      query << " AND " if target
      query << "action:(#{actions.join(" OR ")})"
    end

    UrlHelpers.stafftools_audit_log_path(query: query)
  end

  # Returns default template for Microsoft trade help email
  sig { params(target: Billing::Types::Account).returns(String) }
  def microsoft_trade_help_default_template(target)
    <<~EOF
      Hi Trade help,

      Could you please provide some additional information as to why a Business Partner has been given the #{target.trade_screening_record.msft_trade_screening_status} status.
      The Entity Number of the account is: #{target.trade_screening_record.external_uuid}.
      GitHub username is #{target.display_login}.
      [Staffer can add additional information or remove this line]

      Thank you.
    EOF
  end

  sig { params(target: Billing::Types::Account).returns(T::Boolean) }
  def sales_managed_enterprise?(target:)
    return false unless target.is_a?(Business)
    target.invoiced?
  end
end
