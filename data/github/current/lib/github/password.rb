# typed: true
# frozen_string_literal: true

require "base64"
require "argon2"
require "bcrypt"
require "openssl"

# Class that implements handling password hashing.
#
# This is the only place where implementations of passwords
# like Argon2, BCrypt or PBKDF2 are allowed to be referenced.
# No assumptions can be made that passwords always are a single
# algorithm everywhere.
#
# In general, we run Argon2 as the default everywhere unless
# it is in a FIPS mode environment. There PBKDF2 is used for
# hashing passwords as it is the only allowed algorithm according
# to FIPS.
#
# BCrypt is also provided here since that is the legacy implementation
# used before Argon2 and we likely will need support for a significant
# time as users get transitions on a new login automatically.
#
# After a certain amount of time and forced logins we could drop BCrypt
# at some point, but no such plans are present right now and there's
# no immediate urgency yet for example due to known problems with BCrypt.
#
# Each password type also gets an additional secret hashed in that
# is stored a separate 32 byte secret independent of the database. This is
# provided to github/github through an environment variable. With this
# addition, we can ensure that just the value in the database can't
# be brute forced.
module GitHub
  class Password

    class UnknownType < StandardError; end
    class InvalidHash < StandardError; end
    class HashDisallowed < StandardError; end
    class NoSecretConfigured < StandardError; end

    # Build a new password from a hash
    def initialize(hash)
      raise NotImplementedError, "needs to be able to initialize a hash from a string"
    end

    def verify(password)
      raise NotImplementedError, "needs to be able to verify a password"
    end

    def to_s
      raise NotImplementedError, "needs to be able to convert the password to a hash"
    end

    def needs_upgrade?(secret)
      self.class != self.class.default_password_type || secret != GitHub.user_password_secrets.first
    end

    def self.from_hash(hash)
      case hash
      when /\A\$bcrypt-github/
        return Password::ForbiddenAlgorithm.new if GitHub.fips_mode?
        Password::BCrypt.new(hash)
      when /\A\$argon2(id?|d)/
        return Password::ForbiddenAlgorithm.new if GitHub.fips_mode?
        Password::Argon2.new(hash)
      when /\A\$pbkdf2-sha256/
        Password::PBKDF2.new(hash)
      else
        raise UnknownType, "Unknown password type: #{hash}"
      end
    end

    def self.create(password)
      default_password_type.create(password)
    end

    def self.default_password_type
      if GitHub.fips_mode?
        Password::PBKDF2
      else
        Password::Argon2
      end
    end

    def self.new_password_secret
      if GitHub.user_password_secrets.empty?
        raise NoSecretConfigured, "No secret configured to mix into passwords"
      end
      GitHub.user_password_secrets.first
    end

    class Result
      attr_reader :success
      attr_reader :needs_upgrade
      alias_method :needs_upgrade?, :needs_upgrade
      def initialize(success, needs_upgrade)
        @success = success
        @needs_upgrade = needs_upgrade
      end
    end

    class ForbiddenAlgorithm < Password
      def initialize(*)
      end

      def verify(*)
        Result.new(false, false)
      end

      def to_s
        "(forbidden algorithm, password must be reset)"
      end
    end

    class PBKDF2 < Password
      # Format used here as described in
      # https://passlib.readthedocs.io/en/stable/lib/passlib.hash.pbkdf2_digest.html#format-algorithm
      # but with regular base64 instead.
      def self.generate_pbkdf2(password, salt, secret, iterations, digest)
        hash = OpenSSL::KDF.pbkdf2_hmac(password,
          salt: "#{salt}#{secret}",
          iterations: iterations,
          length: digest.digest_length,
          hash: digest)

        encoded_salt = Base64.strict_encode64(salt)
        encoded_hash = Base64.strict_encode64(hash)
        "$pbkdf2-#{digest.name.downcase}$#{iterations}$#{encoded_salt}$#{encoded_hash}"
      end

      def self.digest
        OpenSSL::Digest::SHA256.new
      end

      def initialize(hash)
        @hash = hash
        @iterations, @salt, @checksum = extract_parts(hash)
      end

      def verify(password)
        GitHub.user_password_secrets.each do |secret|
          if SecurityUtils.secure_compare(@hash, self.class.generate_pbkdf2(password, @salt, secret, @iterations, self.class.digest))
            return Result.new(true, needs_upgrade?(secret))
          end
        end
        Result.new(false, false)
      end

      def needs_upgrade?(secret)
        super(secret) || @iterations < GitHub.pbkdf2_iterations
      end

      def to_s
        @hash
      end

      def self.create(password)
        salt = OpenSSL::Random.random_bytes(digest.digest_length)
        new(generate_pbkdf2(password, salt, new_password_secret, GitHub.pbkdf2_iterations, digest))
      end

      private

      def extract_parts(hash)
        _, _, iterations, salt, checksum = hash.split("$")
        [iterations.to_i, Base64.decode64(salt), Base64.decode64(checksum)]
      end
    end

    class Argon2 < Password
      def initialize(hash)
        raise InvalidHash, "Invalid Argon2 hash" unless ::Argon2::Password.valid_hash?(hash)
        @hash = hash
      end

      def verify(password)
        return Result.new(false, false) if GitHub.fips_mode?
        GitHub.user_password_secrets.each do |secret|
          if ::Argon2::Password.verify_password(password, @hash, secret)
            return Result.new(true, needs_upgrade?(secret))
          end
        end
        Result.new(false, false)
      end

      def to_s
        @hash
      end

      def needs_upgrade?(secret)
        super(secret) || begin
          _, _, _, params, _ = @hash.split("$")
          matches = params.match(/m=(?<memory>\d+),t=(?<time>\d+)/)
          raise InvalidHash, "Invalid Argon2 hash" unless matches && matches[:memory] && matches[:time]
          matches[:memory].to_i < (1 << GitHub.argon2_memory_cost) || matches[:time].to_i < GitHub.argon2_time_cost
        end
      end

      def self.create(password)
        raise HashDisallowed, "Argon2 not allowed in FIPS mode" if GitHub.fips_mode?
        argon = ::Argon2::Password.new(t_cost: GitHub.argon2_time_cost, m_cost: GitHub.argon2_memory_cost, secret: new_password_secret)
        new(argon.create(password))
      end
    end

    class BCrypt < Password
      # This is a slightly customized version of BCrypt. It uses
      # the standard BCrypt hashing, but it hashes the final checksum
      # with an HMAC with the GitHub.user_password_secrets so that
      # the values in the database are not brute forceable in any way
      # and we can replicate this password to other places where needed.
      # The HMAC addition is so that we can convert all existing
      # passwords without having to wait for a re-login of a user.
      def initialize(hash)
        @hash = hash
        @cost, @salt, @checksum = extract_parts(hash)
      end

      def verify(password)
        return Result.new(false, false) if GitHub.fips_mode?
        bcrypt_salt = @salt.gsub(/\A\$bcrypt-github?/, "$2a")
        hashed = ::BCrypt::Password.new(::BCrypt::Engine.hash_secret(password, bcrypt_salt))
        GitHub.user_password_secrets.each do |secret|
          if SecurityUtils.secure_compare(@checksum, Base64.strict_encode64(self.class.hmac(secret).update(hashed.checksum).digest))
            return Result.new(true, needs_upgrade?(secret))
          end
        end
        Result.new(false, false)
      rescue ::BCrypt::Errors::InvalidHash
        Result.new(false, false)
      end

      def to_s
        @hash.to_s
      end

      def needs_upgrade?(secret)
        super(secret) || @cost < GitHub.bcrypt_password_cost
      end

      def self.create(password)
        raise HashDisallowed, "BCrypt not allowed in FIPS mode" if GitHub.fips_mode?
        new(convert(::BCrypt::Password.create(password, cost: GitHub.bcrypt_password_cost)))
      end

      def self.convert_bcrypt_github_bcrypt(bcrypt_hash)
        hash = ::BCrypt::Password.new(bcrypt_hash)
        convert(hash)
      end

      private

      def extract_parts(hash)
        [hash.byteslice(16, 18).to_i, hash.byteslice(0..39), hash.byteslice(40..-1)]
      end

      class << self
        def hmac(secret)
          OpenSSL::HMAC.new(secret, OpenSSL::Digest::SHA256.new)
        end

        private

        def convert(bcrypt_hash)
          "#{bcrypt_hash.salt.gsub(/\A\$2(a|y|b)?/, "$bcrypt-github")}#{Base64.strict_encode64(hmac(new_password_secret).update(bcrypt_hash.checksum).digest)}"
        end
      end
    end
  end
end
