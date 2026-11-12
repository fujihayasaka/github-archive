# frozen_string_literal: true

# Flipper was our original feature flagging library, but it's now deprecated in favor of
# monolith-based feature flags (see config/initializers/feature_flags.rb). Once the remaining flags have been migrated,
# we will remove Flipper. Details: https://github.com/github/dependabot-updates/blob/main/docs/feature-flags.md
#
# Flipper's ActiveRecord adapter is auto-configured on require.
require "flipper/adapters/active_record"
