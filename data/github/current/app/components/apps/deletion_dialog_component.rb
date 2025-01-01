# typed: strict
# frozen_string_literal: true

class Apps::DeletionDialogComponent < ApplicationComponent
  sig { params(integration: Integration).void }
  def initialize(integration:)
    @integration = integration
  end

  private

  sig { returns(Integration) }
  attr_reader :integration
end
