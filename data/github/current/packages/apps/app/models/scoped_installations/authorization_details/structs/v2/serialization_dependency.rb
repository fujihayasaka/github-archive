# typed: strict
# frozen_string_literal: true

# Internal: Overwrite the .from_hash and #serialize methods for the struct. We
# need to further serialize the attributes due to use of Union types
# https://sorbet.org/docs/tstruct#serialize-gotchas.
module ScopedInstallations
  module AuthorizationDetails
    module Structs
      module V2::SerializationDependency
        extend T::Helpers

        module ClassMethods
          extend T::Helpers

          requires_ancestor { Kernel }

          sig do
            params(
              hash: T::Hash[String, T.untyped], strict: T::Boolean
            ).returns(::ScopedInstallations::AuthorizationDetails::Structs::V2)
          end
          def from_hash(hash, strict = false)
            GitHub.tracer.in_span("ScopedInstallations::AuthorizationDetails::Structs::V2.from_hash", kind: :internal) do |_span|
              result = super(hash, strict)

              result.properties.each do |property|
                value = T.let(
                  result.public_send(property), # rubocop:disable GitHub/AvoidObjectSendWithDynamicMethod
                  T.nilable(T.any(Integer, T::Hash[String, T.untyped], T::Struct))
                )

                case value
                when V2::SelectionWithPermissions
                  # Because the selection is a union type, we have to manually
                  # serialize the string to an enum.
                  if value.selection.is_a?(String)
                    value.selection = T.unsafe(Selection.deserialize(value.selection))
                    result.public_send("#{property}=", value)
                  end
                when Hash
                  case property
                  when :repository
                    result.public_send("#{property}=", repository_selection_from_hash(value))
                  else
                    struct = V2::SelectionWithPermissions.from_hash(value)
                    struct.selection = Selection.deserialize(struct.selection)

                    result.public_send("#{property}=", struct)
                  end
                end
              end

              result
            end
          end

          sig do
            params(hash: T::Hash[String, T.untyped]).returns(T.any(
              V2::SelectionWithPermissions,
              V2::ElevatedAccessSelection
            ))
          end
          def repository_selection_from_hash(hash)
            struct =
              if hash.key?("permissions") && hash["permissions"].all? { |_, action| action.is_a?(Integer) }
                V2::SelectionWithPermissions.from_hash(hash)
              else
                V2::ElevatedAccessSelection.from_hash(hash)
              end

            if struct.selection.is_a?(String)
              struct.selection = Selection.deserialize(struct.selection)
            end

            return struct if struct.is_a?(V2::SelectionWithPermissions)

            new_permissions = T.let({}, T::Hash[String, T.any(
              Permission::Action,
              V2::ElevatedAccessSelection::AccessHash
            )])

            struct.permissions.transform_values! do |value|
              case value
              when Hash
                value.transform_keys! { |key| Permission::ActionString.deserialize(key) }

                value.transform_values! do |action_value|
                  case action_value
                  when Hash
                    if action_value["inherit_selection"]
                      V2::InheritSelectionWithIds.from_hash(action_value)
                    else
                      raise ArgumentError, "Unexpected value: #{action_value}"
                    end
                  else
                    action_value
                  end
                end

                value
              when Integer
                Permission::Action.deserialize(value)
              else
                value
              end
            end

            struct
          end
        end

        sig { returns(T::Array[Symbol]) }
        def properties
          T.bind(self, V2)
          self.instance_variables.map(&:to_s).map { |ivar| ivar.delete_prefix("@").to_sym }
        end

        sig { params(strict: T::Boolean).returns(T::Hash[String, T.untyped]) }
        def serialize(strict = true)
          GitHub.tracer.in_span("ScopedInstallations::AuthorizationDetails::Structs::V2#serialize", kind: :internal) do |_span|
            deep_serialize(super(strict))
          end
        end

        mixes_in_class_methods(ClassMethods)

        private

        sig { params(hash: T::Hash[String, T.untyped]).returns(T::Hash[String, T.untyped]) }
        def deep_serialize(hash)
          GitHub.tracer.in_span("ScopedInstallations::AuthorizationDetails::Structs::V2#deep_serialize", kind: :internal) do |_span|
            hash.deep_transform_keys! do |key|
              case key
              when T::Enum
                key.serialize
              else
                key
              end
            end

            hash.transform_values! do |value|
              case value
              when Hash
                deep_serialize(value)
              when T::Enum
                value.serialize
              when T::Struct
                deep_serialize(value.serialize)
              else
                value
              end
            end

            hash
          end
        end
      end
    end
  end
end
