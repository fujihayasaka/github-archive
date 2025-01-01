# typed: true
# frozen_string_literal: true

module Events
  class NilView < View
    def should_render?
      false
    end

    def title_text
      nil
    end
  end
end
