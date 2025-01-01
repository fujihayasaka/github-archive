# typed: true
# frozen_string_literal: true

module Platform
  module Inputs
    class RegistryPackageMetadatum < Platform::Inputs::Base
      description "Represents a single registry metadatum"

      argument :name, String, "Name of the metadatum.", required: true
      argument :value, String, "Value of the metadatum.", required: true
      argument :update, Boolean, "True, if the metadatum can be updated if it already exists", required: false
    end
  end
end
