# typed: false
# frozen_string_literal: true

module Platform
  module Provisioning
    # A class containing all of the user information provided by the identity
    # provider. Underlying attributes are stored as an array of maps. E.g.:
    #
    #   [
    #     { "name" => "userName", "value" => "defunkt", "metadata" => {} },
    #     { "name" => "emails",   "value" => "defunkt@github.com", "metadata" => { "primary" => true } },
    #     { "name" => "emails",   "value" => "ceo@github.com", "metadata" => {} }
    #   ]
    #
    # NOTE: Data types are primitives to remain friendly to serialization.
    class UserData
      include Enumerable

      # Public: Defines a reader helper for easily fetching an attributes
      # value and metadata.
      #
      # attrs   - A list of attribute names to define readers for.
      #
      # Examples
      #
      #   UserData.user_data_reader  user_name: "userName"
      #   user_data.user_name
      #   #=> "mona.octocat"
      #   user_data.user_name_metadata
      #   #=> {"format" => "…"}
      #
      # Returns nothing.
      def self.user_data_reader(attr_map)
        attr_map.each do |method_name, attr|
          define_method(method_name) do
            fetch(attr, {})["value"]
          end

          define_method(:"#{ method_name }_metadata") do
            fetch(attr, {})["metadata"] || {}
          end
        end
      end

      attr_accessor :rebuild_contributions

      def initialize(attributes = [])
        @attributes = attributes
        @rebuild_contributions = false
      end

      # Public: Allows enumeration over the underlying attributes.
      def each(&block)
        @attributes.each(&block)
      end

      # Public: Adds an attribute with the given name and value. Does not
      # replace any existing attributes with the same name.
      #
      # name      - The String name of the attribute.
      # value     - The value of the attribute.
      # metadata  - (Optional) A Hash of metadata for the attribute.
      #
      # Returns nothing.
      def append(name, value, metadata = {})
        @attributes << { "name" => name, "value" => value, "metadata" => metadata }
      end

      # Public: Replaces a given attribute by name. If multiple attributes exists
      # for the same name, only the first match is replaced.
      #
      # name      - The String name of the attribute to replace.
      # value     - The new value of the attribute.
      # metadata  - (Optional) A Hash of metadata for the attribute.
      #
      # Returns nothing.
      def replace(name, value, metadata = {})
        delete(name)
        append(name, value, metadata)
      end

      # Public: Deletes a given attribute by name. If multiple attributes exists
      # for the same name, only the first match is deleted..
      #
      # name      - The String name of the attribute to delete.
      #
      # Returns nothing.
      def delete(name)
        @attributes.delete fetch(name)
      end

      # Public: Deletes all attributes with the given name.
      #
      # name      - The String name of the attributes to delete.
      #
      # Returns nothing.
      def delete_all(name)
        @attributes -= fetch_all(name)
      end

      # Public: Deletes all attributes matched by the given block.
      #
      # block      - A block which will be yielded each attribute. If the
      #             block returns a truthy value, the attribute will be deleted.
      #
      # Returns nothing.
      def delete_if(&block)
        attrs_to_delete = select(&block)
        @attributes -= attrs_to_delete
      end

      # Public: Fetch the first attribute found with a given name, if any.
      #
      # name    - The String name of the attribute you want to return.
      # default - (Optional) Value to return if attribute does not exist.
      #
      # Returns a attribute Hash map.
      def fetch(name, default = nil)
        found = detect { |attr| attr["name"] == name.to_s }
        found || default
      end

      # Public: Fetch all attributes found with a given name, if any.
      #
      # name    - The String name of the attribute you want to return.
      #
      # Returns an Array of attribute Hash maps.
      def fetch_all(name)
        select { |attr| attr["name"] == name.to_s }
      end

      # Public: Returns a new instance of the UserData only containing
      # the desired attribute names.
      #
      # names     - One or more desired attribute names.
      #
      # Returns an instance of UserData
      def slice(*names)
        names = Array.wrap(names).map(&:to_s)

        sliced_attrs = select { |attr| names.include?(attr["name"]) }
        self.class.new(sliced_attrs)
      end
    end
  end
end
