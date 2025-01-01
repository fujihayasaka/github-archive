# typed: true
# frozen_string_literal: true

require "github/linear_scale"

module GitHub
  class LogScale
    # Returns a lambda that maps an input domain to an output range after
    # applying a log10 transformation to the data.
    #
    #   score = GitHub::LogScale.scale!(domain: [1, 42], range: [0, 1.0])
    #   score.call(0)  # => 0.0
    #   score.call(10) # => 0.61604
    #   score.call(42) # => 1.0
    #
    # domain - An Array of Integer objects in the domain data set. Typically just
    #          two numbers: the min and max of the set.
    # range  - An Array of Integer outputs to which to map the domain values.
    #
    # Returns a lambda.
    def self.scale!(domain:, range:)
      domain = domain.map { |x| Math.log10(positive(x)) }
      linear = LinearScale.scale!(domain, range)

      lambda do |x|
        x = positive(x)
        linear.call(x.zero? ? 0 : Math.log10(x))
      end
    end

    def self.positive(x)
      x.to_f < 0 ? 0 : x.to_f
    end
  end
end
