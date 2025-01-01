# typed: true
# frozen_string_literal: true

module Codespaces
  class VscsTargetValidator < ActiveModel::Validator
    def validate(record)
      Codespaces::VscsTargetValidationHelper.validate(record)
    end
  end
end
