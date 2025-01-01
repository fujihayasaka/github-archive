# typed: true
# frozen_string_literal: true

module Site
  module Contentful
    module Legal
      class UpdateListComponent < ApplicationComponent
        def initialize(title: nil, updates: [])
          @title = title
          @updates = updates
        end

        def render?
          @updates.present?
        end

        def updates
          @updates.map do |update|
            Site::Contentful::Legal::UpdateComponent.new(
              title: update.title,
              text: update.text
            )
          end
        end
      end
    end
  end
end
