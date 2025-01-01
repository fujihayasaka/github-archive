# typed: false
# frozen_string_literal: true

module SCIM
  class Operation

    class OperationError < StandardError; end
    class InvalidOperationValue < OperationError; end

    class Result
      attr_reader :user_data, :error

      def initialize(user_data: nil, error: nil)
        @user_data = user_data
        @error = error
      end

      def self.success(user_data:)
        new(user_data: user_data)
      end

      def self.failure(error:)
        new(error: error)
      end

      # Public: Was the result of reconciliation successful?
      #
      # Returns true or false
      def success?
        @error.nil?
      end
    end

    # Defines regexes for determining attribute type. Knowing the type
    # tells us how to go about setting or updating the attribute.
    SINGLE_VALUE_ATTRIBUTE_REGEX     = /\A(userName|externalId|displayName)\z/
    BOOLEAN_VALUE_ATTRIBUTE_REGEX    = /\A(active)\z/
    COMPLEX_VALUE_ATTRIBUTE_REGEX    = /\A(name)\z/
    COMPLEX_VALUE_SUBATTRIBUTE_REGEX = /\Aname\.(givenName|familyName|formatted)\z/
    MULTI_VALUE_ATTRIBUTE_REGEX      = /\A(emails)\z/
    MEMBERS_VALUE_ATTRIBUTE_REGEX    = /\A(members)\z/
    MEMBERS_VALUE_PATH_REGEX         = /\A((members)\[value eq \"([^"]+)\"\])\z/
    EMAILS_TYPE_MULTI_VALUE_REGEX    = /\A(emails\[type eq \"([^"]+)\"\]\.value)\z/
    ROLES_VALUE_ATTRIBUTE_REGEX      = /\A(roles)\z/
    GROUPS_VALUE_ATTRIBUTE_REGEX     = /\A(groups|http:\/\/schemas.microsoft.com\/ws\/2008\/06\/identity\/claims\/groups)\z/

    # Public: Applies all the SCIM operation in the patch to the user data.
    #
    # Example:
    #
    #   apply_add_operations user_data, \
    #     {"Operations": [
    #     {
    #       "op":"add",
    #       "value": {
    #         "emails":[
    #           { "value":"babs@jensen.org", "type":"home" }
    #         ],
    #         "nickname":"Babs"
    #       }
    #     }
    #     ]}
    #
    # user_data   - The UserData to apply the operation to.
    # operation   - A SCIM operation Hash.
    #
    # input_user_data - The UserData to apply the operations to.
    # json            - A SCIM operations json that need to applied to user data.
    #
    # Returns the UserData with the operation applied.
    def self.process_json(input_user_data, json, target: nil)
      json["Operations"].each do |op|
        scim_op = op["op"]&.downcase
        if scim_op == "remove" && op["path"].blank?
          return result_error(400, scim_type: "noTarget")
        else
          begin
            input_user_data = apply(input_user_data, op, target: target)
          rescue OperationError => e
            return result_error(400, scim_type: "invalidSyntax", detail: e.message)
          end
        end
      end

      result_no_error(input_user_data)
    end

    # Internal: Applies a SCIM operation to the user data.
    # Does not mutate the passed in UserData object.
    #
    # Example:
    #
    #   apply user_data \
    #     "op" => "add",
    #     "path" => "userName",
    #     "value" => "new-user-name"
    #
    # input_user_data - The UserData to apply the operation to. This
    #                   object will not be mutated.
    # operation       - A SCIM operation Hash.
    # target          - An optional target parameter that can be used for targeted feature flag enablement.
    #
    # Returns the copy of UserData with the operation applied.
    def self.apply(input_user_data, operation, target: nil)
      expand_operation(operation, target: target).each_with_object(input_user_data.dup) do |op, user_data|
        case op["op"]
        when "add"
          apply_add_operation(user_data, op, target: target)
        when "remove"
          apply_remove_operation(user_data, op, target: target)
        when "replace"
          apply_replace_operation(user_data, op, target: target)
        end
      end
    end

    # Internal: Applies a SCIM 'add' operation to the user data.
    #
    # https://tools.ietf.org/html/rfc7644#section-3.5.2.1
    #
    # Example:
    #
    #   apply_add_operation user_data, \
    #     "op" => "add",
    #     "path" => "userName",
    #     "value" => "new-user-name"
    #
    # user_data   - The UserData to apply the operation to.
    # operation   - A SCIM operation Hash.
    # target      - An optional target parameter that can be used for targeted feature flag enablement.
    #
    # Returns the UserData with the operation applied.
    def self.apply_add_operation(user_data, operation, target: nil)
      return user_data unless operation["op"] == "add"

      case path = operation["path"]
      when SINGLE_VALUE_ATTRIBUTE_REGEX
        user_data.replace(path, operation["value"])
      when BOOLEAN_VALUE_ATTRIBUTE_REGEX
        user_data.replace(path, operation["value"].to_s)
      when COMPLEX_VALUE_ATTRIBUTE_REGEX
        operation["value"].each do |subattribute, value|
          user_data.replace("#{ path }.#{ subattribute }", value)
        end
      when COMPLEX_VALUE_SUBATTRIBUTE_REGEX
        user_data.replace(path, operation["value"])
      when EMAILS_TYPE_MULTI_VALUE_REGEX
        type = $2
        value = operation["value"]

        raise InvalidOperationValue, "Email values must be valid email addresses." unless User.valid_email?(value)

        user_data.append("emails", value, { type: type })
      when MEMBERS_VALUE_ATTRIBUTE_REGEX
        process_member_operation_values(operation_type: :add, operation_value: operation["value"], path: path, user_data: user_data)
      when MULTI_VALUE_ATTRIBUTE_REGEX, GROUPS_VALUE_ATTRIBUTE_REGEX
        if operation["value"] && operation["value"].is_a?(String)
          raise InvalidOperationValue, "Invalid operation value: #{operation["value"]}"
        end

        operation["value"].each do |value|
          value = Hash[*value][operation["path"]] if value.is_a?(Array)

          value = [value] unless value.is_a?(Array)
          value.each do |val|
            demote_primary_multi_value(user_data, path) if val["primary"]

            if path == "emails"
              raise InvalidOperationValue, "Email values must be valid email addresses." unless User.valid_email?(val["value"])
            end

            user_data.append(path, val["value"], val.except("value"))
          end
        end
      end

      user_data
    end

    # Internal: Applies a SCIM 'remove' operation to the user data.
    #
    # https://tools.ietf.org/html/rfc7644#section-3.5.2.2
    #
    # Example:
    #
    #   apply_remove_operation user_data, \
    #     "op" => "remove",
    #     "path" => "name.familyName",
    #
    # user_data   - The UserData to apply the operation to.
    # operation   - A SCIM operation Hash.
    # target      - An optional target parameter that can be used for targeted feature flag enablement.
    #
    # Returns the UserData with the operation applied.
    def self.apply_remove_operation(user_data, operation, target: nil)
      return user_data unless operation["op"] == "remove"

      case path = operation["path"]
      when SINGLE_VALUE_ATTRIBUTE_REGEX
        user_data.delete(path)
      when BOOLEAN_VALUE_ATTRIBUTE_REGEX
        user_data.delete(path)
      when COMPLEX_VALUE_ATTRIBUTE_REGEX
        user_data.delete_if { |attr| attr["name"].starts_with?("#{ path }.") }
      when COMPLEX_VALUE_SUBATTRIBUTE_REGEX
        user_data.delete(path)
      when EMAILS_TYPE_MULTI_VALUE_REGEX
        type = $2
        if operation["value"]
          user_data.delete_if { |attr| attr["name"] == "emails" && attr["value"] == operation["value"] && attr.dig("metadata", "type") == type }
        else
          user_data.delete_if { |attr| attr["name"] == "emails" && attr.dig("metadata", "type") == type }
        end
      when MEMBERS_VALUE_ATTRIBUTE_REGEX
        process_member_operation_values(operation_type: :remove, operation_value: operation["value"], path: path, user_data: user_data)
      when MEMBERS_VALUE_PATH_REGEX
        user_data.append($2, $3, { operation: :remove })
      when MULTI_VALUE_ATTRIBUTE_REGEX
        user_data.delete_all(path)
      when GROUPS_VALUE_ATTRIBUTE_REGEX
        groups_key = operation.dig("meta", "groups_path_key") || "groups"
        groups_to_remove = operation.dig("value", groups_key).map { |group| group.dig("value") }
        user_data.delete_if { |attr| attr["name"] == groups_key && groups_to_remove.include?(attr["value"]) }
      end

      user_data
    end

    # Internal: Applies a SCIM 'replace' operation to the user data.
    #
    # https://tools.ietf.org/html/rfc7644#section-3.5.2.3
    #
    # Example:
    #
    #   apply_add_operations user_data, \
    #     "op" => "replace",
    #     "path" => "emails",
    #     "value" => [
    #       { "value" => "new-email@example.com" }
    #     ]
    #
    # user_data   - The UserData to apply the operation to.
    # operation   - A SCIM operation Hash.
    # target      - An optional target parameter that can be used for targeted feature flag enablement.
    #
    # Returns the UserData with the operation applied.
    def self.apply_replace_operation(user_data, operation, target: nil)
      return user_data unless operation["op"] == "replace"

      case path = operation["path"]
      when SINGLE_VALUE_ATTRIBUTE_REGEX
        user_data.replace(path, operation["value"])
      when BOOLEAN_VALUE_ATTRIBUTE_REGEX
        user_data.replace(path, operation["value"].to_s)
      when COMPLEX_VALUE_ATTRIBUTE_REGEX
        user_data.delete_if { |attr| attr["name"].starts_with?("#{ path }.") }
        operation["value"].each do |subattribute, value|
          user_data.append("#{ path }.#{ subattribute }", value)
        end
      when EMAILS_TYPE_MULTI_VALUE_REGEX
        type = $2

        raise InvalidOperationValue, "Email values must be valid email addresses." unless User.valid_email?(operation["value"])

        user_data.each do |attr|
          attr["value"] = operation["value"] if attr["name"] == "emails" && attr.dig("metadata", "type") == type
        end
      when MEMBERS_VALUE_ATTRIBUTE_REGEX
        user_data.replace_all_members(true)
        process_member_operation_values(operation_type: :add, operation_value: operation["value"], path: path, user_data: user_data)
      when COMPLEX_VALUE_SUBATTRIBUTE_REGEX
        user_data.replace(path, operation["value"])
      when MULTI_VALUE_ATTRIBUTE_REGEX, GROUPS_VALUE_ATTRIBUTE_REGEX, ROLES_VALUE_ATTRIBUTE_REGEX
        user_data.delete_all(path)

        if operation["value"] && !operation["value"].is_a?(Array)
          raise InvalidOperationValue, "Invalid operation value: #{operation["value"]}"
        end

        operation["value"].each do |value|
          value = convert_value_to_json(value) if value.is_a?(String)

          if path == "emails"
            raise InvalidOperationValue, "Email values must be valid email addresses." unless User.valid_email?(value["value"])
          end

          user_data.append(path, value["value"], value.except("value"))
        end
      end

      user_data
    end

    # Private: Processes the operation values for members and appends them to user_data.
    # It expects the operation value to be an array of hashes, each containing a "value" key.
    #
    # @param [Symbol] operation_type The type of operation to be performed (e.g., :add, :remove, :replace).
    # @param [Array<Hash>] operation_value The array of hashes containing the values to be processed.
    # @param [String] path The path to which the values will be appended.
    # @param [Object] user_data The user data object that has an append method.
    #
    # @raise [InvalidOperationValue] If the operation value is not an array.
    #
    # @return [void]
    def self.process_member_operation_values(operation_type: nil, operation_value: nil, path: nil, user_data: nil)
      if !operation_value.is_a?(Array)
        raise InvalidOperationValue, "Invalid operation value for 'members': #{operation_value}. It should be an array."
      end

      operation_value.each do |value|
        val = value["value"]
        user_data.append(path, val, { operation: operation_type })
      end
    end

    # Private: Converts a string value to a JSON object if possible.
    #
    # Returns the value as a JSON object if possible, throws an InvalidOperationValue
    def self.convert_value_to_json(value)
      begin
        JSON.parse(value)
      rescue JSON::ParserError
        raise InvalidOperationValue, "Invalid operation value: #{value}"
      end
    end
    private_class_method :convert_value_to_json

    # Internal: Expands bundled SCIM operations into a series of simple operations. This
    # allows the apply logic to focus on a single format.
    #
    # SCIM allows bundling multiple "add" or "replace" operations into a single operation hash.
    # For example the following two operation payloads are equivalent:
    #
    # # Bundled
    #
    #   {"Operations": [
    #     {
    #       "op":"add",
    #       "value": {
    #         "emails":[
    #           { "value":"babs@jensen.org", "type":"home" }
    #         ],
    #         "nickname":"Babs"
    #       }
    #     }
    #   ]}
    #
    # # Expanded
    #   {"Operations":[
    #     {
    #       "op":"add",
    #       "path": "emails",
    #       "value":[
    #         { "value":"babs@jensen.org", "type":"home" }
    #       ]
    #     },
    #     {
    #       "op": "add",
    #       "path": "nickname",
    #       "value": "Babs"
    #     }
    #   ]}
    #
    # Returns an Array of single operation Hashes.
    def self.expand_operation(operation, target: nil)
      # AAD sends ops titleized, `Add` versus `add`
      operation["op"] = operation.dig("op")&.downcase
      if %w(add replace).include?(operation["op"]) && operation["path"].blank?
        # Arrays and Hashes are valid values for an operation
        unless operation["value"].is_a?(Array) || operation["value"].is_a?(Hash)
          raise OperationError.new("Invalid type #{operation["value"].class.name} for an operation value: #{operation}. Value must be an array or a hash.")
        end

        operation["value"].map do |path, value|
          {
            "op"    => operation["op"],
            "path"  => path,
            "value" => value,
          }
        end
      else
        [operation]
      end
    end

    # Internal: Demotes the current primary item, if any, for a multi-value attribute.
    #
    # user_data  - The UserData containing the attributes.
    # attribute  - The multi-value attribute name.
    #
    # Returns nothing.
    def self.demote_primary_multi_value(user_data, attribute)
      existing_primary = user_data.fetch_all(attribute).detect { |attr| attr["metadata"]["primary"] }

      existing_primary["metadata"].delete("primary") if existing_primary
    end

    # Private: Delivers a SCIM formatted error and halts processing.
    #
    # https://tools.ietf.org/html/rfc7644#section-3.12
    #
    # status    - The Integer status code for the error.
    # scim_type  - (Optional) A String error type as defined by the spec.
    # detail    - (Optional) A human-readable message describing the error.
    #
    # Returns nothing.
    def self.result_error(status, scim_type: nil, detail: nil)
      scim_error = SCIM::ErrorResponse.new(status: status, scim_type: scim_type, detail: detail)

      Result.failure(error: scim_error)
    end

    def self.result_no_error(user_data)
      Result.success(user_data: user_data)
    end
  end
end
