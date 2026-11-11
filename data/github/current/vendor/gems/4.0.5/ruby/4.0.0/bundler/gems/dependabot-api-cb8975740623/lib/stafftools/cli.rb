# frozen_string_literal: true

require "thor"
require "stafftools/cli/main"

module Stafftools
  module Cli
    def self.start(*args)
      Main.start(*args)
    end
  end
end
