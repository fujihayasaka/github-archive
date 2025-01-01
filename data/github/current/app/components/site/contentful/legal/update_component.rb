# typed: true
# frozen_string_literal: true

module Site
  module Contentful
    module Legal
      class UpdateComponent < ApplicationComponent
        def initialize(title:, text: nil)
          @title = title
          @text = text
        end

        def render?
          @title.present? && @text.present?
        end
      end
    end
  end
end
