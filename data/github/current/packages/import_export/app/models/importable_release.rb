# typed: true
# frozen_string_literal: true

class ImportableRelease < Release
  include Importable
  def type
    "Release"
  end

  def event_prefix
    :release
  end
end
