# typed: true
# frozen_string_literal: true

require "color"
require "chunky_png"

class Identicon
  PIXEL_SIZE   = 70 # how big each "pixel" is
  SPRITE_SIZE  = 5  # how many rows and columns

  COLORS = [
    [ # gray
      ["#586069", "#f6f8fa"],
      ["#ffffff", "#d1d5da"],
      ["#f6f8fa", "#586069"],
    ],
    [ # blue
      ["#005cc5", "#dbedff"],
      ["#ffffff", "#79b8ff"],
      ["#dbedff", "#005cc5"],
    ],
    [ # green
      ["#22863a", "#dcffe4"],
      ["#ffffff", "#85e89d"],
      ["#dcffe4", "#22863a"],
    ],
    [ # purple
      ["#5a32a3", "#e6dcfd"],
      ["#ffffff", "#b392f0"],
      ["#e6dcfd", "#5a32a3"],
    ],
    [ # yellow
      ["#f9c513", "#fffbdd"],
      ["#ffffff", "#ffea7f"],
      ["#fffbdd", "#f9c513"],
    ],
    [ # orange
      ["#e36209", "#ffebda"],
      ["#ffffff", "#ffab70"],
      ["#ffebda", "#e36209"],
    ],
    [ # red
      ["#cb2431", "#ffdce0"],
      ["#ffffff", "#f97583"],
      ["#ffdce0", "#cb2431"],
    ],
    [ # white
      ["#cb2431", "#ffffff"], # red on white
      ["#22863a", "#ffffff"], # green on white
      ["#005cc5", "#ffffff"],  # blue on white
    ],
  ].freeze

  attr_reader :hash

  # Public: Get a Hash for generating an identicon.
  #
  # seed - optional String or Integer to seed the hash
  #
  # Returns a 40-character String.
  def self.generate_hash(seed = nil)
    if GitHub.fips_mode?
      Digest::SHA256.hexdigest((seed || rand).to_s)
    else
      Digest::SHA1.hexdigest((seed || rand).to_s) # rubocop:disable GitHub/InsecureHashAlgorithm
    end
  end

  def initialize(gravatar_id)
    @hash = gravatar_id
    @sprite_color = nil
    generate_color
  end

  # Public: Determine if a pixel should be drawn at the given index in the identicon.
  #
  # index - an Integer
  #
  # Returns a Boolean.
  def draw_pixel_at?(index)
    hash[index].to_i(16) % 2 == 0
  end

  # Public: Get a foreground and background color for an identicon.
  #
  # Returns an Array of two Strings, e.g.:
  #   # => ["#5a32a3", "#e6dcfd"]
  def foreground_background_colors
    @foreground_background_colors ||= begin
      colors = colors_subset
      variation_index = self.class.map(hash[26].to_i(16), 0, 15, 0, colors.length).ceil
      variation_index -= 1 if variation_index > 0
      fg_color = colors[variation_index][0]
      bg_color = colors[variation_index][1]

      [fg_color, bg_color]
    end
  end

  # Public: Get the background color for this identicon without the leading '#'.
  #
  # Returns a hex color code as a String, e.g., "005cc5".
  def background_color
    foreground_background_colors.last.sub(/\A#/, "")
  end

  def generate_image
    half_axis   = (SPRITE_SIZE - 1) / 2
    margin_size = PIXEL_SIZE / 2

    png = ChunkyPNG::Image.new(420, 420, @bg_color)

    i = 0 # overall count
    x = half_axis * PIXEL_SIZE
    while x >= 0
      y = 0
      while y < SPRITE_SIZE * PIXEL_SIZE
        if hash[i].to_i(16) % 2 == 0
          png.rect(x + margin_size, y + margin_size, x + PIXEL_SIZE + margin_size,
                   y + PIXEL_SIZE + margin_size, @sprite_color, @sprite_color)
          if x != half_axis * PIXEL_SIZE
            x_start = 2 * half_axis * PIXEL_SIZE - x
            png.rect(x_start + margin_size, y + margin_size, x_start + PIXEL_SIZE + margin_size,
                     y + PIXEL_SIZE + margin_size, @sprite_color, @sprite_color)
          end
        end
        i += 1
        y += PIXEL_SIZE
      end
      x -= PIXEL_SIZE
    end

    png.to_blob(:fast_rgb)
  end

  # Ruby implementation of Processing's map function
  # http://processing.org/reference/map_.html
  def self.map(value, v_min, v_max, d_min, d_max) # v for value, d for desired
    v_value = value.to_f # so it returns float

    v_range = v_max - v_min
    d_range = d_max - d_min
    d_value = (v_value - v_min) * d_range / v_range + d_min
  end

  private

  def generate_color
    # use values at the end of the hash to determine HSL values
    hue = self.class.map(hash[25, 3].to_i(16), 0, 4095, 0, 360)
    sat = self.class.map(hash[28, 2].to_i(16), 0, 255, 0, 20)
    lum = self.class.map(hash[30, 2].to_i(16), 0, 255, 0, 20)

    color = Color::HSL.new(hue, 65 - sat, 75 - lum)
    rgb = color.to_rgb
    r = (rgb.r * 255).round
    g = (rgb.g * 255).round
    b = (rgb.b * 255).round

    @bg_color     = ChunkyPNG::Color.rgb(240, 240, 240)
    @sprite_color = ChunkyPNG::Color.rgb(r, g, b)
  end

  # Private: Get a list of predefined color choices for use in an identicon.
  #
  # Returns an Array of Arrays of String colors, e.g.:
  #   # => [["#5a32a3", "#e6dcfd"], ["#ffffff", "#b392f0"], ["#e6dcfd", "#5a32a3"]]
  def colors_subset
    @colors_subset ||= begin
      index = self.class.map(hash[25].to_i(16), 0, 15, 0, COLORS.length).ceil
      index -= 1 if index > 0
      COLORS[index]
    end
  end
end
