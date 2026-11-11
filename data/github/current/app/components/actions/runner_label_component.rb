# typed: true
# frozen_string_literal: true

class Actions::RunnerLabelComponent < ApplicationComponent
  attr_reader :label, :form_id

  def initialize(label:, selected: false, indeterminate: false, form_id: nil)
    @label = label
    @selected = selected
    @indeterminate = indeterminate
    @form_id = form_id
  end

  def selected?
    @selected
  end

  def indeterminate?
    @indeterminate
  end
end
