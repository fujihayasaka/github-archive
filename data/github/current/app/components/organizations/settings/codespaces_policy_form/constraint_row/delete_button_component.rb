# typed: true
# frozen_string_literal: true

class Organizations::Settings::CodespacesPolicyForm::ConstraintRow::DeleteButtonComponent < ApplicationComponent
  attr_reader :constraint_name

  def initialize(constraint_name:)
    @constraint_name = constraint_name
  end
end
