# typed: strict
# frozen_string_literal: true

# This module implements client ID generation and identification for OAuth Apps and GitHub Apps
#
# It handles multiple client ID formats by relying on the owning model to implement
# the following class methods:
# - client_id_types                    - A Hash of Regexp => Symbol pairs that match the client ID format
# - client_id_prefix(type)             - A String that is the prefix of the client ID
# - client_id_seperator(type)          - A String that separates the prefix and the random part of the client ID
# - client_id_random_part_length(type) - An Integer that is the length of the random part of the client ID
#
# It also provides the ability to determine the type of a client ID and check if a given string matches
# a client ID format for the owning class.
#
# The type of client ID is determined by the method `new_client_id_type` which by default checks the
# `globally_unique_client_ids` feature flag for the owner of the model. This can be overridden by the
# owning model to provide custom logic for determining the client ID type.
module OauthAccess::ClientId
  extend T::Sig
  extend T::Helpers

  @client_idable_classes = T.let([], T::Array[T.class_of(OauthAccess::ClientId)])

  # Public: The classes that implement the client ID interface
  # Used to provide a single entrypoint for finding OAuth enabled Apps via a Client ID.
  sig { returns(T::Array[T.class_of(OauthAccess::ClientId)]) }
  def self.client_idable_classes
    @client_idable_classes
  end

  # Public: Register models that implement the client ID interface
  sig { params(included: Module).void }
  def self.included(included)
    OauthAccess::ClientId.client_idable_classes << T.cast(included, T.class_of(OauthAccess::ClientId))
    super
  end

  # Public: Find the application by the client ID
  sig { params(key: String).returns(T.nilable(T.any(Integration, OauthApplication))) }
  def self.application(key:)
    client_idable_classes.each do |klass|
      # This is a bunch of nonsense to make Sorbet happy 🍨
      model_klass = T.cast(klass, T.class_of(ActiveRecord::Base))
      model_interface = T.cast(klass, ClassInterface)

      return model_klass.find_by(key: key) if model_interface.client_id?(key)
    end

    nil
  end

  # Public: Check if the given key is a client ID for any of the registered classes
  # If the application_klass is provided, it will only check that class
  sig { params(key: String, application_klass: T.nilable(OauthAccess::ClientId::ClassInterface)).returns(T::Boolean) }
  def self.client_id?(key, application_klass: nil)
    unless application_klass
      return client_idable_classes.any? { |klass| T.cast(klass, ClassInterface).client_id?(key) }
    end

    application_klass.client_id?(key)
  end

  module ClassInterface
    extend T::Sig
    extend T::Helpers
    abstract!

    #
    # Public interface methods that control client ID generation and identification
    #

    # Public: The Hash of Regexp => Symbol pairs that match the client ID format
    # {/pattern/ => :type}
    sig { abstract.returns(T::Hash[Regexp, Symbol]) }
    def client_id_types; end

    # Public: The prefix of the client ID for the given type
    sig { abstract.params(type: Symbol).returns(String) }
    def client_id_prefix(type:); end

    # Public: The seperator between the prefix and the random part of the client ID
    sig { abstract.params(type: Symbol).returns(String) }
    def client_id_seperator(type:); end

    # Public: The length of the random part of the client ID for the given type
    sig { abstract.params(type: Symbol).returns(Integer) }
    def client_id_random_part_length(type:); end

    sig { overridable.params(type: Symbol).returns(String) }
    def client_id_format(type:)
      "%<prefix>s%<seperator>s%<random>s"
    end

    sig { overridable.params(type: Symbol).returns(String) }
    def client_id_random_part(type:)
      length = client_id_random_part_length(type: type)
      case type
      when :v1
        SecureRandom.hex(length)
      when :v2
        SecureRandom.alphanumeric(length)
      end
    end

    sig { overridable.params(type: Symbol).returns(T::Hash[Regexp, String]) }
    def client_id_generation_variables(type:)
      prefix = client_id_prefix(type: type)
      seperator = client_id_seperator(type: type)
      random = client_id_random_part(type: type)

      {
        prefix: prefix,
        seperator: seperator,
        random: random
      }
    end

    # Private: Generate a random client ID for the given type
    # This method is used to generate a new client ID for a new record
    sig { overridable.params(type: Symbol).returns(String) }
    def generate_random_key(type:)
      client_id_format(type: type) % client_id_generation_variables(type: type)
    end

    #
    # Public interface methods for identifying client IDs and
    # client ID types
    #

    # Public: The symbol representing the type of client_id of string
    # or :none if the string is not a valid client_id.
    #
    # string - A String
    #
    # Returns a Symbol [:v1, :v2, :none]
    sig { params(string: String).returns(Symbol) }
    def client_id_type(string)
      client_id_types.each do |pattern, type|
        return type if pattern.match?(string)
      end

      :none
    end

    sig { params(string: String).returns(T::Boolean) }
    def client_id?(string)
      client_id_type(string) != :none
    end

    private

    # Private: Generate a random opaque string to be used as a location specifier
    # This value is stable for a given environment and is used to make the client
    # ID unique across all GitHub installations.
    #
    # This is an imperfect solution, the "sum" operation greatly reduces the
    # entropy of the SHA256 hash. Our target is a unique 3 character alphanumeric
    # string based on what will fit into the client ID which is the primary
    # constraint.
    #
    # However, given that we're encoding a deployement environment we're hopefully
    # limited in number and don't require a high degree of entropy.
    #
    # This value can evolve over time as long as it:
    # - Is stable for a given environment
    # - Is unique across all GitHub installations
    #
    # Steps:
    #  - GitHub.deployed_to       - Returns the stamp name or environment name
    #  - Digest::SHA256.hexdigest - Prevents collisions between stamp-01 and stamp-10
    #  - sum                      - Sum the char values of the SHA256 hexdigest
    #  - to_s(36)                 - Convert the integer to a base 36 string
    #  - ("%03s" % ...)           - Pad the string to 3 characters
    #  - sub(" ", "0")            - Replace any spaces with 0 to guarantee 3 characters
    #
    # Returns a String
    sig { returns(String) }
    def opaque_generated_location_specifier
      ("%03s" % Digest::SHA256.hexdigest(GitHub.deployed_to).sum.to_s(36)).sub(" ", "0")
    end
  end

  mixes_in_class_methods(ClassInterface)

  sig { void }
  def generate_client_id_if_needed
    T.bind(self, T.any(OauthApplication, Integration))

    return if read_attribute(:key).present?

    self.key = random_key
  end

  sig { returns(String) }
  def key
    generate_client_id_if_needed
    super
  end

  sig { returns(Symbol) }
  def new_client_id_type
    T.bind(self, T.any(OauthApplication, Integration))

    owner&.feature_enabled?(:globally_unique_client_ids) ? :v2 : :v1
  end

  sig { returns(String) }
  def random_key
    T.bind(self, T.any(OauthApplication, Integration))

    client_id_type = new_client_id_type
    self.class.generate_random_key(type: client_id_type)
  end
end
