# typed: true
# frozen_string_literal: true

class Organizations::HeaderNav::TabComponent < ApplicationComponent
  def initialize(url:, text:, tab_id:, icon:, counter_class: nil, count: nil, test_selector: nil, hotkey: nil, link_classes: nil)
    @url = url
    @text = text
    @tab_id = tab_id
    @icon = icon
    @counter_class = counter_class
    @count = count
    @test_selector = test_selector
    @hotkey = hotkey
    @link_classes = link_classes
  end
end
