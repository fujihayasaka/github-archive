# typed: true
# frozen_string_literal: true

# An HSL colour object. Internally, the hue (#h), saturation (#s), and
# brightness (#b) values are dealt with as fractional values in
# the range 0..1.

module Color
  class HSB
    # Creates an HSL colour object from fractional values 0..1.
    def self.from_fraction(h = 0.0, s = 0.0, b = 0.0)
      colour = Color::HSB.new
      colour.h = h
      colour.s = s
      colour.b = b
      colour
    end

    # Creates an HSL colour object from the standard values of degrees and
    # percentages (e.g., 145 deg, 30%, 50%).
    def initialize(h = 0, s = 0, b = 0)
      @h = h / 360.0
      @s = s / 100.0
      @b = b / 100.0
    end

    # Present the colour as an HTML/CSS colour string.
    def html
      to_rgb.html
    end

    # Present the colour as an RGB HTML/CSS colour string (e.g., "rgb(0%, 50%,
    # 100%)"). Note that this will perform a #to_rgb operation using the
    # default conversion formula.
    def css_rgb
      to_rgb.css_rgb
    end

    # Present the colour as an RGBA (with alpha) HTML/CSS colour string (e.g.,
    # "rgb(0%, 50%, 100%, 1)"). Note that this will perform a #to_rgb
    # operation using the default conversion formula.
    def css_rgba
      to_rgb.css_rgba
    end

    def to_rgb(ignored = nil)
      to_hsl.to_rgb
    end

    def to_hsl
      hh = @h
      ll = (2.0 - @s) * @b
      ss = @s * @b
      ss /= (ll <= 1.0) ? ll : 2.0 - ll
      ll /= 2.0

      HSL.from_fraction(hh, ss, ll)
    end

    # Converts to RGB then YIQ.
    def to_yiq
      to_rgb.to_yiq
    end

    # Converts to RGB then CMYK.
    def to_cmyk
      to_rgb.to_cmyk
    end

    # Returns the hue of the colour in degrees.
    def hue
      @h * 360.0
    end

    # Returns the hue of the colour in the range 0.0 .. 1.0.
    def h
      @h
    end

    # Sets the hue of the colour in degrees. Colour is perceived as a wheel,
    # so values should be set properly even with negative degree values.
    def hue=(hh)
      hh = hh / 360.0

      hh += 1.0 if hh < 0.0
      hh -= 1.0 if hh > 1.0

      @h = Color.normalize(hh)
    end

    # Sets the hue of the colour in the range 0.0 .. 1.0.
    def h=(hh)
      @h = Color.normalize(hh)
    end

    # Returns the percentage of saturation of the colour.
    def saturation
      @s * 100.0
    end

    # Returns the saturation of the colour in the range 0.0 .. 1.0.
    def s
      @s
    end

    # Sets the percentage of saturation of the colour.
    def saturation=(ss)
      @s = Color.normalize(ss / 100.0)
    end

    # Sets the saturation of the colour in the ragne 0.0 .. 1.0.
    def s=(ss)
      @s = Color.normalize(ss)
    end

    # Returns the percentage of brightness of the colour.
    def brightness
      @b * 100.0
    end

    # Returns the luminosity of the colour in the range 0.0 .. 1.0.
    def b
      @b
    end

    # Sets the percentage of luminosity of the colour.
    def brightness=(bb)
      @b = Color.normalize(bb / 100.0)
    end

    # Sets the luminosity of the colour in the ragne 0.0 .. 1.0.
    def b=(bb)
      @b = Color.normalize(bb)
    end

    def to_hsb
      self
    end

    def inspect
      "HSB [%.2f deg, %.2f%%, %.2f%%]" % [hue, saturation, brightness]
    end

    def self.from_hex(hex)
      raw = hex.gsub(/[^0-9a-fA-F]/, "")

      parts = nil
      case raw.size
      when 3
        parts = raw.scan(%r{[0-9A-Fa-f]}).map { |el| (el * 2).to_i(16) }
      when 6
        parts = raw.scan(%r<[0-9A-Fa-f]{2}>).map { |el| el.to_i(16) }
      else
        raise "Input color was #{raw} but must be either 3 or 6 digits in length."
      end

      Color::RGB.new(*parts).to_hsb
    end

    def to_hex
      rgb = self.to_rgb
      "%02x%02x%02x" % [rgb.r * 255, rgb.g * 255, rgb.b * 255]
    end

    def to_greyscale
      to_hsl.to_greyscale
    end
  end

  class HSL
    def to_hsb
      hh = @h
      ss = @s
      ll = @l

      h = hh
      ll *= 2.0
      ss *= (ll <= 1) ? ll : 2.0 - ll
      b = (ll + ss).to_f / 2.0
      s = (ll + ss) == 0 ? 0 : (2.0 * ss) / (ll + ss)

      HSB.from_fraction(h, s, b)
    end
  end

  class RGB
    def to_hsb
      to_hsl.to_hsb
    end
  end
end
