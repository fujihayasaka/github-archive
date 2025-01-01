# typed: true
# frozen_string_literal: true

module Platform
  module Helpers
    module GlobalId
      # Version identifiers for Hydro
      VERSION_LEGACY = :LEGACY
      VERSION_NEXT   = :NEXT
      TOP_LEVEL_TYPES = %w(Repository User Organization Enterprise Bot Mannequin).freeze

      COHORT_1 = "2021-09-01"
      COHORT_2 = "2021-09-08"
      COHORT_3 = "2021-09-14"
      COHORT_4 = "2021-09-21"
      COHORT_5 = "2021-09-28"

      # This is not present in legacy IDs (which use `encode64` -- this character isn't in the output set)
      DELIMITER = "_"
      SHORTNAME_MAX_LENGTH = 6

      # Public: Whether the ID provided matches the next Global ID format
      #
      # id - the ID
      #
      # Returns a Boolean.
      def self.next?(id)
        id.to_s.include?(DELIMITER)
      end

      # Public: Whether the ID provided matches the legacy (Relay) Global ID format
      #
      # id - the ID
      #
      # Returns a Boolean.
      def self.legacy?(id)
        !next?(id)
      end

      # Public: Return the version of a global ID, for use with Hydro enums.
      #
      # id - the ID
      #
      # Returns a Symbol.
      def self.version(id)
        next?(id) ? VERSION_NEXT : VERSION_LEGACY
      end

      # Public: Is the ID deprecated, based on the created date of the record
      # compared to the ready date set for the record.
      #
      # Returns a Boolean.
      def self.deprecated?(id, record)
        object_type = ::Platform::Helpers::NodeIdentification.type_from_object(record)
        if GitHub.flipper[:deprecated_all_legacy_global_ids].enabled? && !GitHub.enterprise?
          legacy?(id)
        else
          legacy?(id) && object_type.use_next_id?(record)
        end
      end

      # Public: Return the correct global ID given the model's global
      #         ID configuration, ready date, and user preference.
      #
      # Returns a String.
      def self.for(record, **kwargs)
        async_for(record, nil, **kwargs).sync
      end

      def self.async_for(record, type, **kwargs)
        if use_next?(record, type, **T.unsafe(kwargs))
          Platform::Helpers::NodeIdentification.async_to_next_global_id(record, type)
        else
          object_type = Platform::Schema.get_type(type&.to_s) if record.respond_to?(:platform_type_name=)
          record.platform_type_name = object_type.type_name if object_type.present?

          Promise.resolve(record.global_relay_id)
        end
      end

      def self.parse(id)
        GlobalId.next?(id) ? Next.parse(id) : Legacy.parse(id)
      end

      class TypeNameExpansionMissingError < ArgumentError
        def initialize(name)
          message = "No compressed type name registered for #{name.inspect}; use `implements_node ..., as: '...'` to register a short type name for it."
          super(message)
        end
      end

      def self.expand_type_name(short_type_name)
        EXPAND_TYPE_NAMES[short_type_name] || raise(TypeNameExpansionMissingError, short_type_name) # rubocop:disable GitHub/UsePlatformErrors
      end

      def self.compress_type_name(long_type_name)
        COMPRESS_TYPE_NAMES[long_type_name] || raise(TypeNameExpansionMissingError, long_type_name) # rubocop:disable GitHub/UsePlatformErrors
      end

      class ShortNameRegistrationError < StandardError
      end

      # @param as [String] the short name
      # @param graphql_name [String] the full GraphQL type name
      # @return void
      # @api private This is called by `implement_node`
      def self.register_short_name(as, graphql_name, allow_longer: false)
        # rubocop:disable GitHub/UsePlatformErrors
        if as !~ /\A[A-Z]+\Z/
          raise ShortNameRegistrationError, "#{as.inspect} must be all upper-case (for consistency)"
        elsif as.size > SHORTNAME_MAX_LENGTH && !allow_longer
          raise ShortNameRegistrationError, "#{as.inspect} must be #{SHORTNAME_MAX_LENGTH} characters or less (come chat with #api-platform if you have an exception to this rule)"
        elsif EXPAND_TYPE_NAMES.key?(as)
          raise ShortNameRegistrationError, "#{as.inspect} is already registered as a short name (for #{EXPAND_TYPE_NAMES[as].inspect}), choose another short name for #{graphql_name.inspect}"
        elsif COMPRESS_TYPE_NAMES.key?(graphql_name)
          raise ShortNameRegistrationError, "#{graphql_name.inspect} is already registered with #{COMPRESS_TYPE_NAMES[graphql_name].inspect}, don't register another short name for it."
        else
          EXPAND_TYPE_NAMES[as] = graphql_name
          COMPRESS_TYPE_NAMES[graphql_name] = as
        end
        # rubocop:enable GitHub/UsePlatformErrors
        nil
      end

      EXPAND_TYPE_NAMES = {}
      COMPRESS_TYPE_NAMES = {}

      private_constant :EXPAND_TYPE_NAMES
      private_constant :COMPRESS_TYPE_NAMES

      # Public: Determine whether the next global ID should be
      #         used given the the model's global ID configuration,
      #         ready date, and user preference.
      #
      # Returns a boolean.
      def self.use_next?(record = nil, type = nil,  user_preference:, user_opt_out:)
        return false if user_opt_out
        return false unless record
        object_type = Platform::Schema.get_type(type&.to_s) if record.respond_to?(:platform_type_name=)
        object_type ||= ::Platform::Helpers::NodeIdentification.type_from_object(record)

        return false if object_type.nil?

        # Don't use next global id if there isnt a ready date
        # for this type's global id
        return false if !object_type.has_ready_global_id?

        # `ready_date` only applies on GitHub.com --
        # on Enterprise, the source code is out of sync from the database,
        # so headers should be used there instead.
        if GitHub.runtime.dotcom? && object_type.use_next_id?(record)
          true
        else
          !!user_preference
        end
      end

      # Public: Manually builds the next global ID for a top-level object given the type name and database ID.
      # Returns a String.
      def self.build_next_global_id(type_name, id)
        unless TOP_LEVEL_TYPES.include?(type_name)
          raise Platform::Errors::Internal, "#{type_name} is not a valid top-level owner type: #{TOP_LEVEL_TYPES.join(', ')}"
        end

        id = MessagePack.pack([0, id])
        encoded_id = Base64.urlsafe_encode64(id).sub(/=+\Z/, "")
        compress_type_name(type_name) + DELIMITER + encoded_id
      end
    end
  end
end
