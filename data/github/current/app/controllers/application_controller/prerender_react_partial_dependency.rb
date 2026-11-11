# typed: true
# frozen_string_literal: true

# Provides a request-scoped store for pre-rendered React partials.
# Controllers can call `prerender_react_partial` during before_actions to
# kick off async SSR early. The `render_react_partial` helper automatically
# picks up any matching pre-rendered renderer from the store, avoiding the
# need to thread ivars through layouts and components.

module ApplicationController::PrerenderReactPartialDependency
  extend ActiveSupport::Concern
  extend T::Helpers

  class ReactPartialStore < ActiveSupport::CurrentAttributes
    attribute :prerendered_react_partials
  end

  requires_ancestor { ApplicationController }

  sig { params(name: String, renderer: React::PartialRenderer).void }
  def prerender_react_partial(name:, renderer:)
    if ReactPartialStore.prerendered_react_partials.nil?
      ReactPartialStore.prerendered_react_partials = {}
    end

    ReactPartialStore.prerendered_react_partials[name] = renderer
  end
end
