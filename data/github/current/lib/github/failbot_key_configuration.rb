# typed: true
# frozen_string_literal: true

module GitHub
  class FailbotKeyConfiguration
    include Singleton

    sig { params(key_name: T.any(String, Symbol)).returns(T::Boolean) }
    def self.key_allowed?(key_name)
      return false unless self.instance.definitions[key_name.to_s]

      self.instance.definitions[key_name.to_s]["allowed"] == true
    end

    sig { returns(Hash) }
    def definitions
      @definitions
    end

    sig { returns(T::Array[String]) }
    def self.all_allowed_keys
      self.instance.definitions.keys.select { |key_name| self.key_allowed?(key_name) }
    end

    private

    def initialize
      path = GitHub::AppEnvironment.root.join("docs", "sensitive-data.yaml")
      parsed_yaml = YAML.safe_load(path.read)
      @definitions = stitch_definitions(parsed_yaml)
    end

    # This takes the YAML file with its lists of key definitions and key types,
    # and stitches them together so that we can use that combined data to
    # answer questions like "Is this key allowed to go to Failbot/Sentry?"
    sig { params(parsed_yaml: T::Hash[String, T::Hash[String, Hash]]).returns(Hash) }
    def stitch_definitions(parsed_yaml)
      definitions = T.cast(parsed_yaml["failbot_key_dictionary"], Hash)
      types = T.cast(parsed_yaml["types"], Hash)

      definitions.map do |failbot_key, key_definition|
        target_type = key_definition["type"]
        unless target_type && target_type.is_a?(String) && types.has_key?(target_type)
          next [failbot_key, key_definition]
        end

        found_type = types[target_type]

        value = {
          "type_description" => found_type["description"],
          "allowed" => found_type.fetch("allowed", false)
        }.merge(key_definition)

        [failbot_key, value]
      end.to_h
    end
  end
end
