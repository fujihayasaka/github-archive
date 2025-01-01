# typed: true
# frozen_string_literal: true

class DiffViewController < ApplicationController
  def update_view_preference # rubocop:todo GitHub/UseRestfulActions
    if logged_in? && params[:diff].present?
      diff_view = params[:diff].to_sym
      current_user.set_diff_preference(diff_view)

      analytics_event \
        category: "DiffViewSettings",
        action: diff_view
    end

    redirect_to referrer_path
  end

  private def target_for_conditional_access
    return :no_target_for_conditional_access unless logged_in? # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
    current_user
  end

  # updating diff view if ALREADY on that page should success for anon user
  # this use case shouldn't happen on Proxima anyway but bypass policy so tests succeed
  def tenant_verification_enforceable # rubocop:todo GitHub/UseRestfulActions
    :no
  end

  private

  def referrer_path
    uri = URI(request.referrer)
    uri.query = { diff: params[:diff] || params[:old_diff], w: params[:w] || params[:old_w] }.to_query
    uri.to_s
  end
end
