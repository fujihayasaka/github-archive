# typed: true
# frozen_string_literal: true

# We no longer require this file directly in our application, but having it
# allows us to use prism in any gems that still require "parser/current"

require "parser"
require "prism"

module Parser
  CurrentRuby = ::Prism::Translation::ParserCurrent

  module Builders
    remove_const :Default
    const_set :Default, Prism::Translation::Parser::Builder
  end
end
