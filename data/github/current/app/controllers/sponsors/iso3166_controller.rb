# typed: true
# frozen_string_literal: true

class Sponsors::ISO3166Controller < ApplicationController
  before_action :render_404, unless: :logged_in?
  before_action :require_xhr

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Collab,
    ApplicationRecord::IamAbilities,
    only: [:index]

  def index
    return render_404 unless country_code
    return render_404 unless subdivisions.present?

    render partial: "sponsors/iso3166", locals: { subdivisions: subdivisions }
  end

  private

  def target_for_conditional_access
    # no protected resources provided by this controller
    :no_target_for_conditional_access # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
  end

  def country_code
    params[:country_code].presence
  end

  memoize def subdivisions
    subdivisions = Sponsors::ISO3166.subdivisions(country_code: country_code)
    # These are inverted because Rails wants name -> value and we have value -> name
    subdivisions.invert
  end
end
