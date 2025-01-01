# typed: strict
# frozen_string_literal: true

module Stafftools
  module BillingPermissionCheck
    extend T::Sig
    extend T::Helpers
    extend ActiveSupport::Concern
    include Stafftools::BillingHelper

    requires_ancestor { StafftoolsController }

    # Skip billing checks for :packages and :storage for an year
    # Adds a comment in the github/gitcoin/issues/4042 issue for tracking
    sig { params(billing_entity: ::Billing::Types::Account, current_user: ::User).void }
    def stop_billing_check_helper(billing_entity, current_user)
      if GitHub.flipper[:bypass_actions_permission_checks].enabled?(billing_entity)
        result = stop_billing_check_actions(billing_entity, current_user)
      else
        result = stop_billing_check_packages(billing_entity, current_user)
      end
      flash[:notice] = result
      redirect_to :back
    end
  end
end
