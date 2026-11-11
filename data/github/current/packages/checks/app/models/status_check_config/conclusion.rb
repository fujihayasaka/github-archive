# typed: true
# frozen_string_literal: true

class StatusCheckConfig::Conclusion < StatusCheckConfig::Status
  attr_accessor :check_icon_color_class, :sentence_for_check

  def check_icon_class
    color = check_icon_color_class || "color-fg-attention"
    "#{color} selected-color-white"
  end
end
