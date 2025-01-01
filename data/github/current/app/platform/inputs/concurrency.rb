# typed: true
# frozen_string_literal: true

module Platform
  module Inputs
    class Concurrency < Platform::Inputs::Base
      description "concurrency data."

      argument :group, String, "Group name the run is waiting for.", required: true
      argument :waiting_on_resource, Inputs::WaitingOnResource, "Information containing which resources are blocking",  required: false
    end
  end
end
