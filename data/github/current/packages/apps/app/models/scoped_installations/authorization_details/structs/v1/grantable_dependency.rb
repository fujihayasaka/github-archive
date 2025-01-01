# typed: strict
# frozen_string_literal: true

module ScopedInstallations
  module AuthorizationDetails
    module Structs
      module V1::GrantableDependency
        extend T::Sig
        extend T::Helpers

        requires_ancestor { V1 }

        sig { params(resource_type: ResourceType, name: String).returns(T.nilable(Integer)) }
        def granted_access_on_all_subjects(resource_type, name)
          case selection_for(resource_type)
          when Selection::All, Selection::Global, Selection::Parent
            subject_types_and_actions_for(resource_type)[name]&.serialize
          end
        end

        sig do
          params(
            resource_type: ResourceType,
            name: String,
            subject_ids: T::Array[Integer]
          )
          .returns(PublicMethods::SubjectIdActionPairs)
        end
        def granted_subject_ids_with_actions_for(resource_type, name, subject_ids)
          return [] if subject_ids.empty?

          case selection_for(resource_type)
          when Selection::Global, Selection::Parent, Selection::Subset
            subset_subject_ids_and_actions_for(resource_type, name, subject_ids)
          when Selection::All, Selection::None
            asymmetric_subject_ids_and_actions_for(resource_type, name, subject_ids)
          end
        end

        private

        sig do
          params(
            resource_type: ResourceType,
            name: String,
            subject_ids: T::Array[Integer]
          ).returns(PublicMethods::SubjectIdActionPairs)
        end
        def asymmetric_subject_ids_and_actions_for(resource_type, name, subject_ids)
          subject_ids_and_actions = T.let({}, T::Hash[Integer, Integer])

          if (asymmetric = self.asymmetric_for(resource_type)[name])
            asymmetric.each do |action, ids|
              action_int = Permission.actions[action]

              filtered_ids = ids & subject_ids
              ids_and_action = Hash[filtered_ids.map { |id| [id, action_int] }]

              # Take the highest level of access if there is a conflicting subject id.
              subject_ids_and_actions.merge!(ids_and_action) do |_subject_id, old_action, new_action|
                [old_action, new_action].max
              end
            end
          end

          subject_ids_and_actions.to_a
        end

        sig do
          params(
            resource_type: ResourceType,
            name: String,
            subject_ids: V1::SubjectIds
          ).returns(PublicMethods::SubjectIdActionPairs)
        end
        def subset_subject_ids_and_actions_for(resource_type, name, subject_ids)
          subject_ids_and_actions = T.let({}, T::Hash[Integer, Integer])

          if (action = subject_types_and_actions_for(resource_type)[name])
            action = action.serialize

            filtered_subject_ids =
              case selection_for(resource_type)
              when Selection::Global, Selection::Parent
                subject_ids
              else
                subject_ids_for(resource_type) & subject_ids
              end

            subject_ids_and_actions = filtered_subject_ids.each_with_object({}) do |subject_id, hash|
              hash[subject_id] = action
            end
          end

          asymmetric_access = asymmetric_subject_ids_and_actions_for(resource_type, name, subject_ids).to_h

          subject_ids_and_actions.merge!(asymmetric_access) do |_, old_action, new_action|
            [old_action, new_action].max
          end

          subject_ids_and_actions.to_a
        end
      end
    end
  end
end
