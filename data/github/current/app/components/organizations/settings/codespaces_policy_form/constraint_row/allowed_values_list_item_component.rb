# typed: true
# frozen_string_literal: true

class Organizations::Settings::CodespacesPolicyForm::ConstraintRow::AllowedValuesListItemComponent < ApplicationComponent
  attr_reader :allowed_value, :data_target, :hidden

  def initialize(data_target:, allowed_value: nil, hidden: false)
    @allowed_value = allowed_value
    @data_target = data_target
    @hidden = hidden
  end
end
