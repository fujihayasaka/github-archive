# typed: true
# frozen_string_literal: true

class Dependabot::SuggestedFixDependencyMetadataComponent < ApplicationComponent
  attr_reader :dependency_metadata

  def initialize(dependency_metadata:)
    @dependency_metadata = dependency_metadata
  end

  def render?
    dependency_metadata.any?
  end
end
