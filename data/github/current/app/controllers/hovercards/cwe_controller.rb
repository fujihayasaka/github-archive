# typed: true
# frozen_string_literal: true

# TODO delete after cwe_summary_discourse FF fully ships
class Hovercards::CWEController < ApplicationController
  include Hovercards::ConditionalAccessMethods

  before_action :require_xhr

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Notify,
    ApplicationRecord::Collab,
    only: [:show]

  def show
    return render_404 unless cwe.present?
    hide_link = card_params[:hide_link] == "true"
    render "hovercards/cwe/show", locals: { cwe: cwe, hide_link: hide_link }, layout: false
  end

  private

  def two_factor_enforceable
    return :no if action_name == "show"
    :yes
  end

  # CAP bypass is fine here as advisories are public.
  def target_for_conditional_access
    :no_target_for_conditional_access # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
  end

  memoize def cwe
    CWE.find_by(cwe_id: "CWE-#{params[:id]}")
  end

  def card_params
    params.permit(:hide_link, :subject, :current_path, :id)
  end
end
