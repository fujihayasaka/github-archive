# frozen_string_literal: true

require "goomba"

GitHub::Application.configure do
  config.after_initialize do
    if config.cache_classes
      # Warm Goomba once in the Unicorn master.
      Goomba::DocumentFragment.new("<p>hello</p>").to_html
    end
  end
end
