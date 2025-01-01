# typed: true
# frozen_string_literal: true

class Repos::SecurityAndAnalysis::CWEController < ApplicationController
  before_action :require_xhr

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Notify,
    ApplicationRecord::Collab,
    only: [:show]

  def show
    c = cwe
    return render_404 unless c.present?
    render Repos::Security::CWESectionItemContentComponent.new(cwe: c), layout: false
  end


  private

  # CWEs are public
  def target_for_conditional_access
    :no_target_for_conditional_access # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
  end

  sig { returns T.nilable(CWE) }
  def cwe
    CWE.find_by(cwe_id: "CWE-#{params.expect(:id)}")
  end

end
