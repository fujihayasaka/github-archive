# frozen_string_literal: true

require "github/spokes/proto/version"

require "github/spokes/proto/client"
require "github/spokes/proto/gitauth"
require "github/spokes/proto/types"
require "github/spokes/proto/helpers/mode"

$LOAD_PATH.unshift File.join(File.dirname(__FILE__), "github", "spokes", "proto")

Dir["#{File.dirname(__FILE__)}/github/**/*_twirp.rb"].each { |file| require file }

# The loop above imports all service definitons,
# which in turn import the protobuf definitions required for those services.
# However, there is no service for the streaming endpoints, as we can't declare return type RPCs which aren't protobufs.
# Therefore, we're manually requiring the Twirp definitions for streaming requests here.
Dir["#{File.dirname(__FILE__)}/github/spokes/proto/spokes-api/streaming/**/*_pb.rb"].each { |file| require file }

module GitHub
  module Spokes
    module Proto
    end
  end
end
