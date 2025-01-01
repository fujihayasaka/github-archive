require 'tmpdir'
require 'tempfile'
require 'base64'
require 'digest/md5'
require 'time'
require 'date'
require 'gpgme'
require 'json'
require 'stringio'
require 'thread'
require 'fileutils'
require 'securerandom'

module Enterprise
  module Crypto
    class << self
      attr_accessor :customer_vault, :license_vault, :package_vault, :key_size
    end

    def self.key_size
      @key_size || 4096
    end

    def self.vaults
      @vaults ||= []
    end

    def self.current_vault
      vaults.last
    end

    def self.with_vault(vault, cleanup = false)
      current_vault.close! if current_vault
      vaults.push(vault)
      vault.open!

      yield
    ensure
      vault.cleanup!
      vaults.pop
      current_vault.open! if current_vault
    end
  end
end

require 'enterprise/crypto/error'
require 'enterprise/crypto/vault_validator'

require 'enterprise/crypto/safe_dir'
require 'enterprise/crypto/tar'

require 'enterprise/crypto/vault'
require 'enterprise/crypto/customer_vault'
require 'enterprise/crypto/license_vault'
require 'enterprise/crypto/package_vault'

require 'enterprise/crypto/customer'
require 'enterprise/crypto/license'
require 'enterprise/crypto/package'
