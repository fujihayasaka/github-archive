# typed: true
# frozen_string_literal: true

class Billing::Settings::Codespaces::BusinessUsageComponent < ApplicationComponent
  attr_reader :organizations_codespaces_usage, :number_of_organizations_without_codespaces_usage

  def initialize(
    organizations_codespaces_usage:,
    number_of_organizations_without_codespaces_usage:
  )

    @organizations_codespaces_usage = organizations_codespaces_usage
    @number_of_organizations_without_codespaces_usage = number_of_organizations_without_codespaces_usage
  end
end
