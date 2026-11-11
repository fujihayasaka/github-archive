# typed: true
# frozen_string_literal: true

class Stafftools::Codespaces::SuspendEnvironmentComponent < ApplicationComponent
  attr_reader :codespace, :environment

  def initialize(codespace:, environment:)
    @codespace = codespace
    @environment = environment
  end

  def suspended?
    environment.suspended?
  end
end
