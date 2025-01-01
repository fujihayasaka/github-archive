# typed: true
# frozen_string_literal: true

module GitHub
  class LinearScale
    # Returns a lambda that maps the specified input domain and output range when
    # called with a value between domain
    #
    #   score = LinearScale.scale!([0, 500], [0, 1.0])
    #
    # This basically says: I'm going to give you a number between 0 and 500 and you
    # give me back an interpolated representation of that same number that fits
    # between 0 and 1.0
    #
    #   score.call(0) = 0
    #   score.call(250) = 0.5
    #   score.call(500) = 1.0
    #
    #
    # domain - Array. Input domain
    # range  - Array. Output range
    #
    # Returns lambda
    def self.scale!(domain, range)
      u = uninterpolate_number(domain[0], domain[1])
      i = interpolate_number(range[0], range[1])

      lambda do |x|
        x = ([domain[0], x, domain[1]].sort[1]).to_f
        i.call(u.call(x))
      end
    end

    # Returns a lambda used to determine what number is at t in the range of a and b
    #
    #   interpolate_number(0, 500).call(0.5) # 250
    #   interpolate_number(0, 500).call(1) # 500
    #
    def self.interpolate_number(a, b)
      a = a.to_f
      b = b.to_f
      b -= a
      lambda { |t| a + b * t }
    end
    private_class_method :interpolate_number

    # Returns a lambda used to determine where t lies between a and b with an ouput
    # range of 0 and 1
    #
    #   uninterpolate_number(0, 500).call(0)   # 0
    #   uninterpolate_number(0, 500).call(250) # 0.5
    #   uninterpolate_number(0, 500).call(500) # 1.0
    #
    def self.uninterpolate_number(a, b)
      a = a.to_f
      b = b.to_f
      b = b - a > 0 ? 1 / (b - a) : 0

      lambda { |x| (x - a) * b }
    end
    private_class_method :uninterpolate_number
  end
end
