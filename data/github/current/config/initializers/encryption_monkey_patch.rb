# typed: true
# frozen_string_literal: true

ActiveSupport.on_load(:active_record_encryption) do
  require "github/encryption/compression_patch"

  ActiveRecord::Encryption::Encryptor.prepend(GitHub::Encryption::CompressionPatch)
end
