# typed: true
# frozen_string_literal: true

class Hovercards::AdvisoriesController < ApplicationController
  include Hovercards::ConditionalAccessMethods

  before_action :require_xhr

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Notify,
    ApplicationRecord::Collab,
    only: [:show]

  def show
    return render_404 unless advisory.globally_available?

    view = create_view_model(GlobalAdvisories::ShowView, advisory: advisory)
    render "hovercards/advisories/show", layout: false, locals: { view: view }
  end

  private

  memoize def advisory
    Vulnerability.find_by!(ghsa_id: params[:id])
  end

  def two_factor_enforceable
    return :no if action_name == "show"
    :yes
  end

  # CAP bypass is fine here as advisories are public.
  def target_for_conditional_access
    :no_target_for_conditional_access # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
  end
end
