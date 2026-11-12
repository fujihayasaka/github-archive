# frozen_string_literal: true

# NOTE: The autofix experiment is no longer active so the turboscan-client gem has been removed because it blocked
# upgrading to Ruby 3.4. So Turboscan::Autofix#generate_dependabot_fix now raises immediately.
# The full autofix code still needs to get cleaned up at some point, including other references to Turboscan.

module Turboscan
  class Autofix
    class Error < StandardError; end

    def generate_dependabot_fix(_autofix_job)
      raise Error, "Turboscan client has been removed. The autofix experiment is no longer active."
    end
  end
end
