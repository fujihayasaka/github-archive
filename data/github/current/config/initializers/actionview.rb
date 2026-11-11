# typed: true
# frozen_string_literal: true

# Configure ERB to use inlining via fast render enhancer
require "github/erb_implementation"
ActionView::Template::Handlers::ERB.erb_implementation = GitHub::ErbImplementation

require "actionview_precompiler"
erb_handler_without_inlining = Class.new(ActionView::Template::Handlers::ERB::Erubi) do
  prepend GraphQL::Client::ErubiEnhancer
end
ActionviewPrecompiler::HANDLERS_FOR_EXTENSION["erb"] = ->(_template, erb) {
  erb_handler_without_inlining.new(erb).src
}
