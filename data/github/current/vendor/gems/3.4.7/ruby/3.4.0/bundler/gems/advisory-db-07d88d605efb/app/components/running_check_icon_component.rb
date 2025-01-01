# frozen_string_literal: true

class RunningCheckIconComponent < ApplicationComponent
  def initialize(id: nil)
    @id = id || "check-#{SecureRandom.hex(3)}"
  end
end
