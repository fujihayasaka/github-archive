# typed: true
# frozen_string_literal: true

module SlashCommands
  class Item
    attr_reader :value, :text, :description, :id

    # Takes array of items or hashes and returns array of Item instances.
    def self.wrap(objects)
      objects = objects.is_a?(Hash) ? [objects] : Array(objects)

      objects.map do |object|
        from(object)
      end
    end

    def self.from(object)
      case object
      when Item
        object
      when Hash
        Item.new(**hash_to_kwargs(object))
      when String
        Item.new(value: object)
      else
        raise ArgumentError.new("Can't derive item from #{object}")
      end
    end

    def initialize(value:, text: nil, description: nil, id: nil)
      @value = value
      @text = text || value
      @description = description
      @id = id
    end

    def ==(other)
      value == other.value &&
      text == other.text &&
      description == other.description
    end

    # Adapts hash into one that can be used to instantiate an Item
    def self.hash_to_kwargs(hash)
      text = hash["text"] || hash[:text]
      text ||= hash["name"] || hash[:name]
      text ||= hash["label"] || hash[:label]

      value = hash["value"] || hash[:value]
      value ||= hash["name"] || hash[:name]
      value ||= hash["label"] || hash[:label]

      description ||= hash["description"] || hash[:description]

      {
        text: text,
        value: value,
        description: description,
      }
    end
  end
end
