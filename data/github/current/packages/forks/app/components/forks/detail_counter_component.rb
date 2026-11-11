# typed: true
# frozen_string_literal: true

class Forks::DetailCounterComponent < ApplicationComponent
  sig { params(detail_value: T.any(Integer, String), detail_label: String, detail_icon: String, detail_url: T.nilable(String)).void }
  def initialize(detail_value, detail_label, detail_icon, detail_url = nil)
    @detail_value = detail_value
    @detail_icon = detail_icon
    @detail_url = detail_url
    @detail_label = detail_label
  end

  private

  sig { returns(T.nilable(String)) }
  attr_reader :detail_url

  sig { returns(T.any(Integer, String)) }
  attr_reader :detail_value

  sig { returns(String) }
  attr_reader :detail_icon, :detail_label
end
