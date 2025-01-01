# typed: true
# frozen_string_literal: true

module RepositoryActions
  class BillingWarningView < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels
    attr_reader :owner

    def show_legacy_plan_warning?
      return false unless plan_ineligible?

      owner_billing_managed_or_adminable_by?
    end

    def show_access_not_included_in_plan_warning?
      return false unless plan_ineligible?

      current_repository.writable_by?(current_user)
    end

    def show_disabled_warning?
      Billing::ActionsPermission.new(owner).status[:error][:reason] == "DISABLED"
    end

    private

    attr_reader :current_user
    attr_reader :current_repository

    def plan_ineligible?
      Billing::ActionsPermission.new(owner).status[:error][:reason] == "PLAN_INELIGIBLE"
    end

    def owner_billing_managed_or_adminable_by?
      owner.adminable_by?(current_user) || (owner.organization? && owner.billing_manager?(current_user))
    end
  end
end
