# typed: true
# frozen_string_literal: true

module SecurityCenter
  module AlertCentricView
    class UnlockRepositoryComponent < ApplicationComponent # rubocop:disable ViewComponent/ComponentsHaveUnitTests
      attr_reader :link_text, :form_url, :icon, :return_to, :system_arguments

      def initialize(link_text:, form_url:, icon: nil, return_to: nil, **system_arguments)
        @link_text = link_text
        @icon = icon
        @form_url = form_url
        @return_to = return_to
        @system_arguments = system_arguments
      end
    end
  end
end
