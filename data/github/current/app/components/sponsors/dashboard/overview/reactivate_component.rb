# typed: true
# frozen_string_literal: true

class Sponsors::Dashboard::Overview::ReactivateComponent < ApplicationComponent
  def initialize(form_path:, can_reactivate:)
    @form_path = form_path
    @can_reactivate = can_reactivate
  end

  private

  attr_reader :form_path

  def render?
    @can_reactivate
  end
end
