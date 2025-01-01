# typed: true
# frozen_string_literal: true

module RepositoryActions
  module Colors
    # These are the colors we support for Actions.
    # Users can label with the color name or hex.
    #
    # icon_color is so that the icon is clearly displayed.
    #
    # https://styleguide.github.com/primer/support/color-system
    PRIMER_COLORS = [
      { name: "white", color_hex: "ffffff", icon_color_hex: "23292e" },
      { name: "black", color_hex: "1b1f23", icon_color_hex: "ffffff" },
      { name: "yellow", color_hex: "ffd33d", icon_color_hex: "23292e" },
      { name: "blue", color_hex: "0366d6", icon_color_hex: "ffffff" },
      { name: "green", color_hex: "28a745", icon_color_hex: "ffffff" },
      { name: "orange", color_hex: "f66a0a", icon_color_hex: "ffffff" },
      { name: "red", color_hex: "d73a49", icon_color_hex: "ffffff" },
      { name: "purple", color_hex: "6f42c1", icon_color_hex: "ffffff" },
      { name: "gray-dark", color_hex: "24292e", icon_color_hex: "ffffff" },
    ]

    ICON_COLOR_MAPPING = PRIMER_COLORS.each_with_object(Hash.new("ffffff")) do |primer_color, hash|
      hash[primer_color[:color_hex]] = primer_color[:icon_color_hex]
    end

    def self.select_by_name_or_hex(name_or_hex)
      return unless name_or_hex
      name_or_hex = name_or_hex.downcase

      PRIMER_COLORS.find { |primer_color| name_or_hex == primer_color[:name] || name_or_hex == primer_color[:color_hex] }
    end

    def self.generate_default_color(name)
      # Somewhere, the name is being sent as a hash. We still should generate a color regardless of
      # what is sent, so force name to be a string.
      unless name.is_a?(String)
        name = name.to_s
        GitHub.logger.info("Repository action name was not a string", {
          "repo_action_name" => name,
          "code.function" => "generate_default_color",
          "code.namespace" => "RepositoryActions::Colors",
        })
      end

      # If no color provided by user. We set one from the list.
      # Deterministic based on Action name, so it does not change unexpectedly on every update.
      not_random_at_all = Random.new(name.bytes.sum)
      PRIMER_COLORS.sample(random: not_random_at_all)
    end
  end
end
