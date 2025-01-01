# typed: true
# frozen_string_literal: true

module ApplicationController::PartialRenderWithLayoutDependency
  extend T::Helpers
  requires_ancestor { ApplicationController }

  private

  def partial_fragment_layout
    return false unless permit_fragment_layout?
    "layouts/fragment_dev_mode_partial"
  end

  def component_fragment_layout
    return false unless permit_fragment_layout?
    "layouts/fragment_dev_mode"
  end

  def permit_fragment_layout?
    return false unless params[:layout].present?
    return false if params[:flamegraph] == "1"
    return false unless current_user&.site_admin? || Rails.env.development?
    true
  end
end
