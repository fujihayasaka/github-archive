# typed: true
# frozen_string_literal: true

module Site
  module Contentful
    module Legal
      class DocumentLinkComponent < ApplicationComponent
        def initialize(title:, href:, subtitle: nil, external: false)
          @title = title
          @href = href
          @subtitle = subtitle
          @external = external
        end

        def render?
          @title.present? && @href.present?
        end

        def icons
          if external?
            [Primer::Beta::Octicon.new(icon: "link", height: 32)]
          else
            [
              Primer::Beta::Octicon.new(icon: "file", height: 32),
              Primer::Beta::Octicon.new(icon: "file-symlink-file", height: 32)
            ]
          end
        end

        private

        def external?
          !!@external
        end
      end
    end
  end
end
