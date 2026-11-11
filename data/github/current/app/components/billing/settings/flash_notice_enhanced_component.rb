# typed: true
# frozen_string_literal: true

class Billing::Settings::FlashNoticeEnhancedComponent < ApplicationComponent
  attr_reader :heading, :message, :action_text, :action_href

  def initialize(flash:)
    @flash = flash

    if flash.is_a? Hash
      @heading = flash["heading"]
      @message = flash["message"]
      @action_text = flash["action_text"]
      @action_href = flash["action_href"]
    elsif flash
      @message = flash
    end
  end

  def render?
    message.present?
  end
end
