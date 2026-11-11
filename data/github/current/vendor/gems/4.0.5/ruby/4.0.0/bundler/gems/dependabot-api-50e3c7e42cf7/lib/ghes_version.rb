# frozen_string_literal: true

require_relative "../app/actions/run_updater/actions/workflow"

class GhesVersion
  attr_reader :version

  include Comparable

  def self.current
    verion_tag = RunUpdater::Actions::Workflow::CURRENT_VERSION_TAG
    new(verion_tag.partition("-").last)
  end

  def initialize(version)
    @version = Gem::Version.new(version)
  end

  def to_s # rubocop:disable Rails/Delegate
    version.to_s
  end

  def <=>(other)
    version <=> other.version
  end
end
