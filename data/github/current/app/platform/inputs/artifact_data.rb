# typed: true
# frozen_string_literal: true

module Platform
  module Inputs
    class ArtifactData < Platform::Inputs::Base
      description "Details about a collection of files produced by a check suite."
      visibility :internal

      argument :source_url, Scalars::URI, "The full URL to download all files in the artifact.", required: true
      argument :name, String, "The name of the artifact.", required: true
      argument :size, Int, "The size of the artifact in bytes.", required: true
      argument :created_at, Scalars::DateTime, "The datetime the artifact was created.", required: true
      argument :expires_at, Scalars::DateTime, "The datetime the artifact expires.", required: false
    end
  end
end
