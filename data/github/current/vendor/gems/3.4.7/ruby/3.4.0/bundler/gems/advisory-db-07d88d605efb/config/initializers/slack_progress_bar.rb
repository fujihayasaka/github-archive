# frozen_string_literal: true

SlackProgressBar.configure do |config|
  config.aliases = {
    created: "g", # green
    updated: "b", # blue
    errored: "r", # red
    skipped: "y", # yellow
  }
end
