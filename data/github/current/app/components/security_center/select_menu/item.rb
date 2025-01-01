# typed: true
# frozen_string_literal: true

module SecurityCenter
  module SelectMenu
    class Item # rubocop:disable ViewComponent/ComponentsHaveUnitTests
      attr_reader :label, :qualifier, :slug, :count, :description

      def initialize(label:, qualifier:, slug:, count: nil, description: nil)
        @label = label
        @qualifier = qualifier
        @slug = slug
        @count = count
        @description = description
      end
    end
  end
end
