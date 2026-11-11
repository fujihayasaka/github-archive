# typed: true
# frozen_string_literal: true

module GitHub
  module HashAlgorithm
    extend T::Helpers
    interface!

    VALID_BYTESIZES = [20, 32].freeze
    VALID_HEXSIZES = [40, 64].freeze

    FULL_OID_REGEXP = /[a-f0-9]{40}(?:[a-f0-9]{24})?/
    FULL_OID_STANDALONE_REGEXP = /\A[a-f0-9]{40}(?:[a-f0-9]{24})?\z/
    SHORT_OID_REGEXP = /[a-f0-9]{7,64}/
    SHORT_OID_STANDALONE_REGEXP = /\A[a-f0-9]{7,64}\z/

    def self.included(base)
      base.extend(ClassMethods)
    end

    module ClassMethods
      include Kernel
      extend T::Helpers
      abstract!

      sig { abstract.returns(Symbol) }
      def name; end

      sig { abstract.returns(Integer) }
      def byte_length; end

      sig { abstract.returns(Integer) }
      def format_id; end

      sig { abstract.returns(String) }
      def empty_blob; end

      sig { abstract.returns(String) }
      def empty_tree; end

      sig { abstract.returns(String) }
      def gpgsig_header; end

      sig { returns(Integer) }
      def bytesize; byte_length; end

      sig { returns(Integer) }
      def hexsize; hex_length; end

      # The length of an object ID in hex characters.
      sig { returns(Integer) }
      def hex_length
        byte_length * 2
      end

      # The all-zeros object ID.
      sig { returns(String) }
      def null_oid
        "0" * hex_length
      end

      # Is this the all-zeros object ID?
      sig { params(oid: String).returns(T::Boolean) }
      def null_oid?(oid)
        oid == null_oid
      end

      # Is this a valid short hex object ID?
      sig { params(oid: String).returns(T::Boolean) }
      def valid_short_oid?(oid)
        !!(oid.length >= 7 && oid.length <= hex_length && oid =~ /\A[0-9a-f]+\z/)
      end

      # Is this a valid full hex object ID?
      sig { params(oid: String).returns(T::Boolean) }
      def valid_full_oid?(oid)
        !!(oid.length == hex_length && oid =~ /\A[0-9a-f]+\z/)
      end

      def choose(sha1:, sha256:)
        case name
        when :sha1
          sha1
        when :sha256
          sha256
        end
      end
    end

    mixes_in_class_methods(ClassMethods)

    # Get a class object for the hash algorithm defined by `hash`.
    #
    # hash - String or Symbol identifying the hash (either `sha1` or `sha256`)
    # default - GitHub::HashAlgorithm instance (or nil) to return if there is no match.
    #
    # Returns a class deriving from GitHub::HashAlgorithm.
    sig do
      params(hash: T.nilable(T.any(String, Symbol)), default: T.nilable(GitHub::HashAlgorithm::ClassMethods)).
      returns(T.nilable(GitHub::HashAlgorithm::ClassMethods))
    end
    def self.from_sym(hash, default: nil)
      case hash&.to_sym
      when :sha1
        GitHub::HashAlgorithm::SHA1
      when :sha256
        GitHub::HashAlgorithm::SHA256
      else
        default
      end
    end

    # Get a class object for the hash algorithm read from the test environment.
    #
    # Returns a class deriving from GitHub::HashAlgorithm.
    sig { returns(GitHub::HashAlgorithm::ClassMethods) }
    def self.from_test_env
      T.must(from_sym(ENV["TEST_DEFAULT_HASH"], default: GitHub::HashAlgorithm::SHA1))
    end

    def self.choose(sha1:, sha256:, hash:)
      hash = self.from_sym(hash) if hash.is_a?(Symbol) || hash.is_a?(String)
      hash.choose(sha1: sha1, sha256: sha256)
    end

    # The insecure and obsolete SHA-1 hash algorithm.
    class SHA1
      include HashAlgorithm

      # The name of the hash algorithm as a Symbol.
      #
      # This is in the format accepted by Git.
      def self.name
        :sha1
      end

      # The four-byte format ID of the hash algorithm as used by Git.
      #
      # This is the constant which should be used to identify this hash
      # algorithm in binary data formats.
      def self.format_id
        # "sha1", big-endian
        0x73686131
      end

      # The object ID of the empty blob.
      def self.empty_blob
        "e69de29bb2d1d6434b8b29ae775ad8c2e48c5391"
      end

      # The object ID of the empty tree.
      def self.empty_tree
        "4b825dc642cb6eb9a060e54bf8d69288fbee4904"
      end

      # The length of a raw object ID in bytes.
      def self.byte_length
        20
      end

      # The name of the header field for signatures.
      def self.gpgsig_header
        "gpgsig"
      end
    end

    # The SHA-256 hash algorithm.
    class SHA256
      include HashAlgorithm

      # The name of the hash algorithm as a Symbol.
      #
      # This is in the format accepted by Git.
      def self.name
        :sha256
      end

      # The four-byte format ID of the hash algorithm as used by Git.
      #
      # This is the constant which should be used to identify this hash
      # algorithm in binary data formats.
      def self.format_id
        # "s256", big-endian
        0x73323536
      end

      # The object ID of the empty blob.
      def self.empty_blob
        "473a0f4c3be8a93681a267e3b1e9a7dcda1185436fe141f7749120a303721813"
      end

      # The object ID of the empty tree.
      def self.empty_tree
        "6ef19b41225c5369f1c104d45d8d85efa9b057b53b14b4b9b939dd74decc5321"
      end

      # The length of a raw object ID in bytes.
      def self.byte_length
        32
      end

      # The name of the header field for signatures.
      def self.gpgsig_header
        "gpgsig-sha256"
      end
    end
  end
end
