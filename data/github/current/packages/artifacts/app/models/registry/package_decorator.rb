# typed: true
# frozen_string_literal: true

class Registry::PackageDecorator < SimpleDelegator
  attr_reader :latest_version
  def initialize(package, latest_version)
    super(package)
    @latest_version = latest_version
  end
end
