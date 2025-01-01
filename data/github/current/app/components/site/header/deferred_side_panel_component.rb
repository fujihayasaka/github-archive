# typed: true
# frozen_string_literal: true

module Site
  module Header
    class DeferredSidePanelComponent < ApplicationComponent
      attr_reader :url

      renders_one :placeholder, types: {
        global: lambda { |rich_content_enabled, **system_arguments|
          GlobalSidePanelComponent.new(load_everything: false, rich_content_enabled: rich_content_enabled, **system_arguments)
        },
        user: lambda { |**system_arguments|
          UserDrawerSidePanelComponent.new(load_everything: false, **system_arguments)
        }
      }

      def initialize(url:)
        @url = url
      end
    end
  end
end
