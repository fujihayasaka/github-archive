# typed: true
# frozen_string_literal: true

module Issue::DirtyDependency
  attr_accessor :dirty

  def changed?
    dirty || super
  end
end
