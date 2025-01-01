# frozen_string_literal: true

# Throw the protos into the load path
# Below is an Issue that goes over the reasoning why protos needs to be in the RUBYLIB path
# https://github.com/protocolbuffers/protobuf/issues/1137#issuecomment-1005929588
$LOAD_PATH.unshift File.expand_path('authzd/proto', __dir__)

require_relative "authzd/authorizer/client"
require_relative "authzd/enumerator/client"
require_relative "authzd/capevaluator/client"
require_relative "authzd/controlaccess/client"
