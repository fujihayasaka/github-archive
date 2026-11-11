# typed: true
# frozen_string_literal: true

class Codespaces::RepositoryListItemComponent < ApplicationComponent
  attr_reader :repository, :selected, :disabled

  def initialize(repository:, selected: false, disabled: false)
    @repository, @selected, @disabled =
      repository, selected, disabled
  end
end
