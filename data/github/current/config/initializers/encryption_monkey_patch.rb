# typed: true
# frozen_string_literal: true
require "github/encryption/compression_patch"

ActiveRecord::Encryption::Encryptor.prepend(GitHub::Encryption::CompressionPatch)
