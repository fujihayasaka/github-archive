# frozen_string_literal: true

require "normal_yaml"

class NormalValidator < ActiveModel::EachValidator
  def validate_each(record, attribute, value)
    record.errors.add(attribute, :abnormal) unless NormalYAML.normal?(value)
  end
end
