# typed: true
# frozen_string_literal: true

# rubocop:disable ViewComponent/ComponentsHaveUnitTests
class Stafftools::Codespaces::ManageCodespacesComponent < ApplicationComponent
  attr_reader :codespaces_length, :deleted_codespaces_length, :user

  def initialize(user, codespaces_length, deleted_codespaces_length)
    @user = user
    @codespaces_length = codespaces_length
    @deleted_codespaces_length = deleted_codespaces_length
  end

  def render?
    codespaces_length.positive? || deleted_codespaces_length.positive?
  end
end
# rubocop:enable ViewComponent/ComponentsHaveUnitTests
