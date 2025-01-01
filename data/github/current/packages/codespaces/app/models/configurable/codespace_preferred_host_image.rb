# typed: true
# frozen_string_literal: true

module Configurable
  module CodespacePreferredHostImage
    extend T::Helpers
    extend Configurable::Async

    requires_ancestor { Configurable }
    requires_ancestor { Kernel }

    class InvalidCodespaceHostImage < ArgumentError; end

    KEY = "codespace_preferred_host_image"

    def codespace_preferred_host_image
      config.get(KEY) || Codespaces::Settings::PREFERRED_HOST_IMAGE_STABLE
    end

    def update_codespace_preferred_host_image(host_image, force = false, actor:)
      raise InvalidCodespaceHostImage unless Codespaces::Settings::HOST_IMAGES.include?(host_image)
      changed = config.set!(KEY, host_image, actor, force)
      return unless changed

      GitHub.dogstats.increment("codespace_preferred_host_image.updated")
    end
  end
end
