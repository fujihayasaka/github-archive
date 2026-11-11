# typed: true
# frozen_string_literal: true

module Site
  module Contentful
    module About
      module Press
        class PressArticleTileComponent < ApplicationComponent
          def initialize(article)
            @article = article
          end

          def render?
            @article.present?
          end

          def date
            @article.date.strftime("%b %-d, %Y")
          end
        end
      end
    end
  end
end
