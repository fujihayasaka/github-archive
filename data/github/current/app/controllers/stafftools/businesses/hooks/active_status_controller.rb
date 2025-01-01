# typed: true
# frozen_string_literal: true

class Stafftools::Businesses::Hooks::ActiveStatusController < Stafftools::Businesses::BusinessBaseController
  before_action :hook_view, only: %i(update)

  def update
    this_hook.toggle_active_status_from_stafftools(disable_reason: params[:disable_reason])
    flash[:notice] = "Okay, the webhook was successfully #{hook_view.hook_active_status}."
    redirect_to :back
  end

  private

  memoize def hook_view
    @hook_view = Hooks::ShowView.new hook: this_hook
  end

  memoize def this_hook
    @hook = this_business.hooks.find(params[:id])
  end
end
