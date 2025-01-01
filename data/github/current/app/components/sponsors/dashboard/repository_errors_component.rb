# typed: true
# frozen_string_literal: true

class Sponsors::Dashboard::RepositoryErrorsComponent < ApplicationComponent
  # repository - the Repository we're rendering errors for
  # errors - an Array of error Strings for this repository
  def initialize(repository:, errors:)
    @repository = repository
    @errors = errors
  end

  private

  attr_reader :errors, :repository

  def render?
    errors.any?
  end
end
