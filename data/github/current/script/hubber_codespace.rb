# typed: true
# frozen_string_literal: true

module HubberCodespace
  def self.hcs?
    !!(ENV["HCS"] == "1")
  end

  # when workaround is true, we're running on a local mac from a fresh checkout & make
  # decisions accordingly (to deal with Defender completely breaking performance)
  def self.defender_workaround?
    !!(ENV["HCS_DEFENDER_WORKAROUND"] == "1")
  end
end
