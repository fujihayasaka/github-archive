# typed: true
# frozen_string_literal: true

# When we run `/bin/tapioca dsl` Tapioca does not use the sorbet/tapioca/require.rb file.
# When we want to run a dsl compiler against files in the gems/ directory, we need to require the file manually here.

require "octo_core/auth/hmac"
require "octo_core/telemetry/stats/datadog"
