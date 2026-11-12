# frozen_string_literal: true

require "failbot"
require "failbot/rails"

# Custom rollup: group exceptions by class + transaction (the Coach route class).
# This replaces the default rollup which uses exception class + backtrace line.
# When no transaction is set in the context, falls back to the default rollup.
#
# If a rollup is already present (e.g. passed explicitly in `other`), Failbot
# skips this block entirely, so jobs that compute their own rollup are unaffected.
Failbot.rollup do |exception, context, thread|
  transaction = context["transaction"]
  if transaction
    Digest::SHA256.hexdigest("#{exception.class}#{transaction}")
  else
    Failbot.default_rollup(exception, context, thread)
  end
end
