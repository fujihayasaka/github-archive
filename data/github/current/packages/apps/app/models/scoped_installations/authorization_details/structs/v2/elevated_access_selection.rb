# typed: strict
# frozen_string_literal: true

# Internal: Represents a mix of access that is for internal use only. Right now
# this is only used for Codespaces when granting 'elevated' access to some repos and
# not to others.
#
# Below is an example abbreviated example of the `github/github` devcontainer.json file
# https://github.com/github/github/blob/770a09c63f32d0b9e7395b01ed3ed228065a437f/.devcontainer/devcontainer.json
#
# Examples:
#
#   ElevatedAccessSelection.new(
#     selection: Selection::All,
#     permissions: {
#       "actions" => {
#         Permission::ActionString::Read => [GITHUB_ACTIONS_COMPUTE_PROVISIONER],
#         Permission::ActionString::Write => [GITHUB_GITHUB]
#       },
#       "contents" => {
#         Permission::ActionString::Read => InheritSelectionWithIds.new(ids: [DOTFILES])
#         Permission::ActionString::Write => [GITHUB_GITHUB, GITHUB_ACTIONS_COMPUTE_PROVISIONER]
#       },
#       "metadata" => {
#         Permission::ActionString::Read => InheritSelectionWithIds.new(ids: [DOTFILES])
#       }
#       "packages" => Permission::Action::Read,
#       "pull_requests" => {
#         Permission::ActionString::Write => [GITHUB_ACTIONS_COMPUTE_PROVISIONER]
#       }
#     }
#   )
module ScopedInstallations
  module AuthorizationDetails
    module Structs
      class V2
        class ElevatedAccessSelection < T::Struct
          extend T::Sig
          include ResourceSelection
          extend ResourceSelectionDefaultable

          SubjectIds = T.type_alias { T::Array[Integer] }

          AccessHash = T.type_alias do
            T::Hash[Permission::ActionString, T.any(InheritSelectionWithIds, String, SubjectIds)]
          end

          # We use this key to reference the original selection key.
          #
          # We also enforce this string in the JSON schema, but just to play it
          # on the safe side...
          INHERIT_SELECTION = "inherit_selection"

          prop :selection, T.any(Selection::All, SubjectIds)
          prop :permissions, T::Hash[String, T.any(Permission::Action, AccessHash)]

          sig { override.returns(V2::ElevatedAccessSelection) }
          def self.default_value
            new(permissions: {}, selection: [])
          end

          sig { override.params(name: String).returns(T.nilable(Permission::Action)) }
          def granted_access_on_all_subjects(name)
            return unless selection == Selection::All

            access = permissions[name]

            case access
            when Hash
              action = access.select do |_, granted|
                granted.is_a?(InheritSelectionWithIds) || granted == INHERIT_SELECTION
              end.keys.max

              action.present? ? Permission::Action.from(action.to_i) : nil
            when Permission::Action
              access
            end
          end

          sig { override.params(name: String, subject_ids: SubjectIds).returns(PublicMethods::SubjectIdActionPairs) }
          def granted_subject_ids_with_actions_for(name, subject_ids)
            access = permissions[name]
            dupped_selection = selection

            granted_ids_and_actions =
              case access
              when Permission::Action
                return [] unless dupped_selection.is_a?(Array)

                action = access.serialize
                dupped_selection.map { |subject_id| [subject_id, action] }.to_h
              when Hash
                access.each_with_object({}) do |(action_string, granted), hash|
                  granted_action = action_string.to_i

                  ids =
                    case granted
                    when Array
                      granted
                    when InheritSelectionWithIds
                      ids = granted.ids
                      ids += dupped_selection if dupped_selection.is_a?(Array)

                      ids
                    when String # inherited
                      if granted == INHERIT_SELECTION
                        dupped_selection.is_a?(Array) ? dupped_selection : []
                      else
                        []
                      end
                    end

                  ids.each { |subject_id| hash[subject_id] = [hash[subject_id].to_i, granted_action].max }
                end
              else
                []
              end

            # https://sorbet.org/docs/error-reference#7019
            T.unsafe(granted_ids_and_actions).slice(*subject_ids).to_a
          end

          sig do
            override.params(
              permissions: T::Hash[String, Symbol],
              selection: T.any(Selection, SubjectIds)
            ).void
          end
          def add_permissions_selection(permissions:, selection:)
            subject_ids = T.cast(selection, SubjectIds)

            permissions.each do |name, action|
              self.permissions[name] = build_permission_value(name, action, subject_ids)
            end
          end

          sig { params(subject_ids: SubjectIds).returns(SubjectIds) }
          def custom_selected(subject_ids)
            return subject_ids if self.selection == Selection::All

            subject_ids - T.cast(self.selection, SubjectIds)
          end

          private

          sig do
            params(
              name: String,
              action: Symbol,
              subject_ids: SubjectIds
            ).returns(T.any(Permission::Action, AccessHash))
          end
          def build_permission_value(name, action, subject_ids)
            if self.permissions[name].blank?
              new_permission_value(action, subject_ids)
            else
              changed_existent_permission(name, action, subject_ids)
            end
          end

          sig do
            params(
              action: Symbol,
              subject_ids: SubjectIds
            ).returns(T.any(Permission::Action, AccessHash))
          end
          def new_permission_value(action, subject_ids)
            action_str = Permission::ActionString.deserialize(action.to_s)
            custom_subject_ids = custom_selected(subject_ids)

            if custom_subject_ids.size == 0 # Fully inherited
              Permission::Action.from(action)
            elsif custom_subject_ids.size < subject_ids.size # Partially inherited
              { action_str => InheritSelectionWithIds.new(ids: custom_subject_ids) }
            else # Fully custom
              { action_str => custom_subject_ids }
            end
          end

          sig do
            params(
              name: String,
              action: Symbol,
              subject_ids: SubjectIds
            ).returns(T.any(Permission::Action, AccessHash))
          end
          def changed_existent_permission(name, action, subject_ids)
            existent_value = self.permissions[name]
            action_str = Permission::ActionString.deserialize(action.to_s)
            custom_subject_ids = custom_selected(subject_ids)

            if existent_value.is_a?(Hash)
              update_permission_hash(existent_value, action_str, custom_subject_ids)
            elsif existent_value.is_a?(Permission::Action) && action == existent_value.to_sym
              { action_str => InheritSelectionWithIds.new(ids: custom_subject_ids) }
            elsif existent_value.is_a?(Permission::Action)
              current_action_str = Permission::ActionString.deserialize(existent_value.to_sym.to_s)

              {
                action_str => subject_ids,
                current_action_str => "inherit_selection"
              }
            else
              T.must(existent_value)
            end
          end

          sig do
            params(
              existent_value: AccessHash,
              action_str: Permission::ActionString,
              custom_subject_ids: SubjectIds
            ).returns(AccessHash)
          end
          def update_permission_hash(existent_value, action_str, custom_subject_ids)
            current_hash = existent_value

            updated_hash_for_action =
              case existent_value[action_str]
              when InheritSelectionWithIds
                inherit_selection = T.cast(existent_value[action_str], InheritSelectionWithIds)
                inherit_selection = InheritSelectionWithIds.new(ids: custom_subject_ids | inherit_selection.ids)
                { action_str => inherit_selection }
              when Array
                action_value = T.cast(existent_value[action_str], SubjectIds) | custom_subject_ids
                { action_str => action_value }
              when "inherit_selection"
                { action_str => InheritSelectionWithIds.new(ids: custom_subject_ids) }
              end

            if updated_hash_for_action.blank?
              existent_value
            else
              current_hash.merge(updated_hash_for_action)
            end
          end

        end
      end
    end
  end
end
