# typed: true
# frozen_string_literal: true

class MemexProjectWorkflow::ActionsValidator < ActiveModel::Validator

  def validate(record)
    unless record.actions_valid?
      record.errors.add(:actions, "must be a valid combination")
      nil
    end
  end
end
