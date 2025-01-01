# typed: false
# frozen_string_literal: true

require "msgpack"

module MessagePack
  singleton_class.send(:alias_method, :real_pack, :pack)

  # Force msgpack's compatibility_mode to be on globally
  def self.pack(obj, opts = {})
    real_pack(obj, compatibility_mode: true)
  end
end
