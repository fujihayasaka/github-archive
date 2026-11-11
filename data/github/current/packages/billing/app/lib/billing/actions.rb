# typed: true
# frozen_string_literal: true

module Billing
  module Actions
    # Dotcom runner sku names
    STANDARD_RUNNERS = %w[UBUNTU WINDOWS MACOS].freeze
    CUSTOM_RUNNERS = %w[
      ubuntu_4_core ubuntu_8_core ubuntu_16_core ubuntu_32_core ubuntu_64_core
      windows_4_core windows_8_core windows_16_core windows_32_core windows_64_core
    ].freeze

    # Meuse runner sku names
    MEUSE_STANDARD_RUNNERS = %w[linux windows macos linux_arm windows_arm].freeze
    MEUSE_CUSTOM_RUNNERS = %w[
      linux_4_core linux_8_core linux_16_core linux_32_core linux_64_core
      windows_4_core windows_8_core windows_16_core windows_32_core windows_64_core
    ].freeze

    MEUSE_SORTED_RUNNERS = %w[
      linux_4_core linux_8_core linux_16_core linux_32_core linux_64_core macos_12_core
      windows_4_core windows_8_core windows_16_core windows_32_core windows_64_core
    ]

    MACOS_RUNNERS = %w[macos_12_core].freeze

    RUNNERS = (STANDARD_RUNNERS + CUSTOM_RUNNERS + MACOS_RUNNERS).freeze
    MEUSE_RUNNERS = (MEUSE_STANDARD_RUNNERS + MEUSE_CUSTOM_RUNNERS + MACOS_RUNNERS).freeze
  end
end
