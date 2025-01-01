# typed: strict
# frozen_string_literal: true

class CustomPropertyUsage < ApplicationRecord::Domain::Repositories
  include CustomProperties::IPropertyUsage

  belongs_to :definition, class_name: "CustomPropertyDefinition", foreign_key: :definition_id, inverse_of: :custom_property_usages

  ALLOWED_CONSUMER_TYPES = T.let(%w(ruleset), T::Array[String])

  validates :consumer_type, inclusion: { in: ALLOWED_CONSUMER_TYPES, message: "'%{value}' is unknown consumer type" }
  delegate :property_name, to: :definition
end
