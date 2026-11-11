# typed: true
# frozen_string_literal: true

# Reduce the maximum nesting depth allowed in form/query parameters.
#
# The default param_depth_limit is 100. Combined with params_limit=4096,
# a crafted POST with deeply-nested keys triggers ~409,600 recursive
# normalization calls (~11s CPU per request on GHES), enabling pre-auth
# CPU-exhaustion DoS.
#
# Our deepest real-world form nesting is ~3 levels. Setting the limit to 32
# matches the Rack 3.x default and eliminates the attack vector with a wide
# safety margin.
#
# See: https://github.com/github/monolith-platform/issues/1972

param_depth_limit = 32

# Rails 8.2+ uses its own ActionDispatch::ParamBuilder for parameter parsing,
# bypassing Rack::Utils.default_query_parser entirely. We must set the limit
# on both to cover all parsing paths.
ActionDispatch::ParamBuilder.default = ActionDispatch::ParamBuilder.make_default(param_depth_limit)
Rack::Utils.param_depth_limit = param_depth_limit
