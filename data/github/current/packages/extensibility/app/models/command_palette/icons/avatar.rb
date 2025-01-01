# typed: true
# frozen_string_literal: true

module CommandPalette
  module Icons
    class Avatar < CommandPalette::Icon
      attr_reader :url, :alt

      def initialize(url:, alt:)
        super(type: :avatar)
        @url = url
        @alt = alt
      end

      def as_json(*)
        {
          type: type,
          url: url,
          alt: alt,
        }
      end
    end
  end
end
