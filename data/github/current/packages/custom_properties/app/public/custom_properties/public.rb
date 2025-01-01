# typed: strict
# frozen_string_literal: true

module CustomProperties
  module Public
    include Kernel

    extend self

    # Public: Max number of property definitions per org
    DEFINITION_LIMIT = 100

    # Public: Max length of property names and values
    MAX_LENGTH = 75

    # Public: Max length of the description of a property
    DESCRIPTION_MAX_LENGTH = 255

    NAME_VALID_CHARS_REGEX_TEXT = "[a-zA-Z0-9_\\#\\$\\-]+"
    # Public: Regex to validate allowed characters in property names
    NAME_VALID_CHARS_REGEX = /\A#{NAME_VALID_CHARS_REGEX_TEXT}\z/

    # Public: Regex to find forbidden characters in property values. Allows all printable ASCII characters except
    # double quotes.
    #
    # This regex works because `"` is between `!` and `#` in the ASCII table.
    VALUE_INVALID_CHARS_REGEX = /[^ -!#-~]/

    # Public: Gets a definitions manager object used to interact with the properties of an org
    # The object keeps an internal cache of definitions list.
    # It is recommended to memoize it if it is used multiple times in the same request.
    #
    # org - org object. The manager will return definitions for the org and its parent enterprise.
    sig { params(org: Organization).returns(CustomPropertiesDefinitionsManager).checked(:always).on_failure(:raise) }
    def definitions_manager(org)
      CustomPropertiesDefinitionsManager.new(org, config)
    end

    # Public: Gets a definitions manager object used to interact with the properties of a business
    # The object keeps an internal cache of definitions list.
    # It is recommended to memoize it if it is used multiple times in the same request.
    #
    #   source - business object. When business is passed, it will return definitions for that business.
    sig { params(source: Business).returns(CustomPropertiesBusinessDefinitionsManager).checked(:always).on_failure(:raise) }
    def business_definitions_manager(source)
      CustomPropertiesBusinessDefinitionsManager.new(source, config)
    end

    # Public: Gets an object used to work with property values in the org
    #
    # definitions_manager - A definitions collection that can be used to manage property definitions
    sig { params(definitions_manager: CustomPropertiesDefinitionsManager).returns(CustomPropertiesValuesManager) }
    def values_manager(definitions_manager)
      CustomPropertiesValuesManager.new(definitions_manager)
    end

    private

    sig { returns(ICustomPropertiesConfig) }
    def config
      @config ||= T.let(Configs.new, T.nilable(ICustomPropertiesConfig))
    end

    # Temp config class to be used to ensure smoother migration of the managers usage
    class Configs
      include ICustomPropertiesConfig

      sig { override.returns(DefinitionModelImpl) }
      def definition_class
        CustomPropertyDefinition
      end
      sig { override.returns(ValueModelImpl) }
      def value_class
        CustomPropertyValue
      end
    end
  end
end
