# frozen_string_literal: true

# Loads instrumentation hooks in the after_initialize block.
#
# See config/instrumentation.rb for actual custom instrumentations.

Rails.configuration.after_initialize { require "#{Rails.root}/config/instrumentation.rb" }
