# typed: strict
# frozen_string_literal: true

# ActiveModel::Validator adapter for the unified FeatureValidator.
# Wire this with `validates_with` on SecurityConfiguration and its subclasses.
class SecurityProductsEnablement::SecurityConfigurationRules::Validator < ActiveModel::Validator
  sig { params(config: SecurityConfiguration).void }
  def validate(config)
    SecurityProductsEnablement::SecurityConfigurationRules::FeatureValidator
      .compute_errors(config)
      .each do |attribute, messages|
        messages.each { |message| config.errors.add(attribute, message) }
      end
  end
end
