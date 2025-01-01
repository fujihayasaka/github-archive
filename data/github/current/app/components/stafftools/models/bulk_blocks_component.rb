# typed: strict
# frozen_string_literal: true

class Stafftools::Models::BulkBlocksComponent < ApplicationComponent
  extend T::Helpers

  sig { void }
  def initialize
  end

  private

  sig { returns T::Array[String] }
  def block_reasons
    GitHubModels.domain.blocks.reasons
  end
end
