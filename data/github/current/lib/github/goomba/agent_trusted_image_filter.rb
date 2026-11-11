# typed: true
# frozen_string_literal: true

module GitHub::Goomba
  # Filters images to only allow specific image formats for Copilot agent input.
  # Images with disallowed formats are removed entirely.
  class AgentTrustedImageFilter < NodeFilter
    ALLOWED_IMAGE_FORMATS = %w[.jpg .jpeg .png].freeze

    SELECTOR = Goomba::Selector.new("img")

    def selector
      SELECTOR
    end

    def call(element)
      src = element["src"]
      return false unless src

      uri = URI.parse(src)

      # Check if format is allowed
      return false unless allowed_format?(uri.path)

      nil
    rescue URI::InvalidURIError
      false
    end

    private

    def allowed_format?(path)
      return false unless path

      ALLOWED_IMAGE_FORMATS.any? { |format| path.downcase.end_with?(format) }
    end
  end
end
