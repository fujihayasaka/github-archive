# typed: true
# frozen_string_literal: true

class Stafftools::Copilot::TechnicalPreviewComponent < ApplicationComponent
  attr_reader :technical_preview_user

  def initialize(technical_preview_user)
    @technical_preview_user = technical_preview_user
  end
end
