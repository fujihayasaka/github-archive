# typed: strict
# frozen_string_literal: true

# Internal: This struct represents the most common patterns for granting access
# on a collection of subjects. It either uses a 'Selection' enum to signify
# the group of subjects we are granting to or explicity lists
# of the subjects by their ability id.
#
# Examples:
#
#  SelectionWithPermissions.new(
#    selection: Selection::All
#    permissions: { "metadata" => Permission::Action::Read }
#  )
#
#  SelectionWithPermissions.new(
#    selection: [3]
#    permissions: { "metadata" => Permission::Action::Read }
#  )
module ScopedInstallations
  module AuthorizationDetails
    module Structs
      class V2
        class SelectionWithPermissions < T::Struct
          extend T::Sig
          include ResourceSelection
          extend ResourceSelectionDefaultable

          SubjectIds = T.type_alias { T::Array[Integer] }
          ValidSelection = T.type_alias do
            T.any(
              Selection::None,
              Selection::All,
              Selection::Global,
              Selection::Parent,
              SubjectIds
            )
          end


          prop :selection, ValidSelection
          prop :permissions, T::Hash[String, Permission::Action]

          sig { override.returns(V2::SelectionWithPermissions) }
          def self.default_value
            new(selection: Selection::None, permissions: {})
          end

          sig { override.params(name: String).returns(T.nilable(Permission::Action)) }
          def granted_access_on_all_subjects(name)
            case selection
            when Selection::All, Selection::Global, Selection::Parent
              permissions[name]
            end
          end

          sig { override.params(name: String, subject_ids: SubjectIds).returns(PublicMethods::SubjectIdActionPairs) }
          def granted_subject_ids_with_actions_for(name, subject_ids)
            action = permissions[name]
            return [] if action.nil?

            # Sorbet doesn't like unions in case statements.
            dupped_selection = selection

            ids =
              case dupped_selection
              when Selection::Global, Selection::Parent
                subject_ids
              when Array
                dupped_selection & subject_ids
              else
                []
              end

            # Permission::Action => Integer
            action = action.serialize

            ids.map { |subject_id| [subject_id, action] }
          end

          sig do
            override.params(
              permissions: T::Hash[String, Symbol],
              selection: T.any(Selection, SubjectIds)
            ).void
          end
          def add_permissions_selection(permissions:, selection:)
            return if selection == Selection::Subset

            incoming_permissions = permissions.transform_values { |v| Permission::Action.from(v) }

            if self.selection == Selection::None # Initialize permissions
              self.selection = selection
              self.permissions = incoming_permissions
            elsif same_selection?(selection) # Merge permissions
              self.permissions.merge!(incoming_permissions) do |_, existent_action, new_action|
                [existent_action, new_action].max
              end
            end
          end

          sig { params(selection: T.any(Selection, SubjectIds)).returns(T::Boolean) }
          def same_selection?(selection)
            return false if selection.class != self.selection.class

            case selection
            when Array
              T.cast(self.selection, SubjectIds).sort == selection.sort
            else
              self.selection == selection
            end
          end
        end
      end
    end
  end
end
