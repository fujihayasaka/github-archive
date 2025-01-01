# typed: false
# frozen_string_literal: true

class ExternalIdentityAttribute
  module AssociationExtension

    # Public: Sets the IdP provided attributes by the specified scheme.
    #
    # If an attribute record with the same name and value already exists, it
    # will be updated to ensure the metadata is up to data. Existing attributes
    # not specified in the newly assigned attributes will be marked for removal
    # when the identity is saved.
    #
    # scheme          - The scheme during which the attributes were provided by
    #                   the IdP (e.g "saml" or "scim").
    # assigned_attrs  - An array of attribute hashes.
    #
    # Returns nothing.
    def set_scheme_attributes(scheme, assigned_attrs)
      assigned_attrs = normalize_attributes(assigned_attrs)
      existing_attrs = attributes_by_scheme[scheme]

      existing_by_key = keyed_attributes(scheme, existing_attrs)
      assigned_by_key = keyed_attributes(scheme, assigned_attrs)

      attrs_to_add = assigned_by_key.keys - existing_by_key.keys
      attrs_to_update = assigned_by_key.keys & existing_by_key.keys
      attrs_to_remove = existing_by_key.keys - assigned_by_key.keys

      attrs_to_add.each do |key|
        attr = assigned_by_key[key]
        build \
          scheme: scheme,
          name: attr["name"],
          value: attr["value"],
          metadata: attr["metadata"]
      end

      attrs_to_update.each do |key|
        attr = assigned_by_key[key]
        existing_record = detect { |record| record.key == key }
        existing_record.value = attr["value"]
        existing_record.metadata = attr["metadata"]
      end

      attrs_to_remove.each do |key|
        existing_record = detect { |record| record.key == key }
        existing_record.mark_for_destruction
      end

      assigned_attrs
    end

    # Public: Gets IdP provided attributes grouped by scheme
    #
    # Examples
    #
    #   self.attributes_by_scheme
    #   # => {
    #     "saml" => [
    #       { "name" => "name_id", "value" => "hubot", "metatdata" => {} }
    #     ],
    #     "scim" => [
    #       { "name" => "emails", "value" => "hubot@github.com", "metatdata" => { "primary" => true } },
    #       { "name" => "emails", "value" => "hubot@robots.org", "metatdata" => {} }
    #     ],
    #   }
    #
    # Returns a Arrays of attributes grouped by scheme.
    def attributes_by_scheme
      active_attrs = reject(&:marked_for_destruction?)

      by_scheme = ActiveSupport::HashWithIndifferentAccess.new([])
      active_attrs.each_with_object(by_scheme) do |record, result|
        result[record.scheme] += [record.to_hash]
      end.freeze
    end

    private

    def normalize_attributes(attrs)
      attrs = attrs.map(&:stringify_keys)
      attrs.reject { |attr| attr["name"].blank? || attr["value"].blank? }
    end

    # Private: Takes an array of attributes and returns them keyed
    # by an identifying key. Since attributes are primitive data, these keys
    # can be used for determining equivalency between the Hash representation
    # and existing attribute records.
    #
    # Used internally to determine which attributes should be added, removed,
    # or updated on assignment.
    def keyed_attributes(scheme, attrs)
      attrs.each_with_object({}) do |attr, result|
        name, value = attr.values_at("name", "value")
        key = ExternalIdentityAttribute.generate_key(scheme.downcase, name.downcase, value.downcase)

        result[key] = attr
      end
    end
  end
end
