# typed: true
# frozen_string_literal: true

class Businesses::BusinessRulesRelaxedRenameController < Businesses::BusinessController
  before_action :business_owner_required
  before_action :business_not_downgraded_to_free_plan_required
  before_action :business_full_plan_required

  def update
    if !FeatureFlag.vexi.enabled?(:branch_rename_enterprise_rule_protections_enforce, this_business, default: false) ||
       !FeatureFlag.vexi.enabled?(:ent_rules_relaxed_rename, this_business, default: false)
      redirect_to :back
      return
    end

    setting_value = business_rules_relaxed_rename_params[:business_rules_relaxed_rename]
    validate_setting value: setting_value, valid_values: %w[enabled disabled]

    message = case setting_value
    when "enabled"
      this_business.enable_business_rules_relaxed_rename(actor: current_user)
      "Branch rename settings were updated."
    when "disabled"
      this_business.disable_business_rules_relaxed_rename(actor: current_user)
      "Branch rename settings were updated."
    end

    redirect_to :back, notice: message
  end

  private

  memoize def business_rules_relaxed_rename_params
    params.require(:business).permit(:business_rules_relaxed_rename)
  end
end
