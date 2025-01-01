# typed: strict
# frozen_string_literal: true

module SecretScanning
  module Mailers
    class LayoutComponent < ApplicationComponent # rubocop:disable ViewComponent/ComponentsHaveUnitTests
      renders_one :header_text
      renders_one :subheader_text
      renders_one :main_section
      renders_one :content_footer
      renders_one :footer_text

      sig { params(title: String, icon: T.nilable(String)).void }
      def initialize(title:, icon:)
        @title = title
        @icon = icon
      end
    end
  end
end
