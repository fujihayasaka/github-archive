# typed: true
# frozen_string_literal: true

class Azure::BaseController < ApplicationController
  include Azure::SubscriptionsDependency

  before_action :login_required,
    :ensure_billing_enabled

  private

  def target_for_conditional_access # rubocop:todo GitHub/UseRestfulActions
    target || :no_target_for_conditional_access # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
  end

  memoize def target # rubocop:todo GitHub/UseRestfulActions
    current_user&.organizations&.find_by_login!(params[:account_id])
  end
end
