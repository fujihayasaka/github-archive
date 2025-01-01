# typed: strict
# frozen_string_literal: true

module ScopedInstallations
  module AuthorizationDetails
    module Structs
      class V1 < T::Struct
        include PublicMethods

        extend T::Sig

        include PublicMethods
        include GrantableDependency

        VERSION = 1

        VALID_SELECTION_RESOURCE_TYPES = T.let([
          ResourceType::Codespace,
          ResourceType::Organization,
          ResourceType::Repository,
        ], T::Array[ResourceType])

        # "contents" => { "read" => [1, 2] }
        AsymmetricAccessForResourceType = T.type_alias do
          T::Hash[String, T::Hash[String, T::Array[Integer]]]
        end

        SubjectIds = T.type_alias { T::Array[Integer] }

        prop :version, Integer, default: VERSION

        prop :selections, T.nilable(T::Hash[ResourceType, Selection])
        prop :subject_ids, T.nilable(T::Hash[ResourceType, SubjectIds])
        prop :subject_types_and_actions, T.nilable(T::Hash[ResourceType, T::Hash[String, Permission::Action]])

        prop :asymmetric, T.nilable(T::Hash[ResourceType, AsymmetricAccessForResourceType])

        sig { override.returns(T::Hash[String, Symbol]) }
        def all_permissions
          ap = {}

          if self.subject_types_and_actions.present?
            T.must(subject_types_and_actions).each_pair do |_, permissions|
              ap.merge!(permissions) do |_, old_action, new_action|
                # Pick the highest level of access.
                [old_action, new_action].max.to_sym
              end
            end
          end

          if self.asymmetric.present?
            T.must(self.asymmetric).each_pair do |_, astaa|
              astaa.each_pair do |resource, actions_and_subject_ids|
                highest_action = actions_and_subject_ids.keys.map do |action|
                  Permission::Action.from(action)
                end.max

                # Set the highest action for this resource.
                if !ap.key?(resource)
                  ap[resource] = highest_action
                else
                  ap[resource] = [ap[resource], highest_action].max
                end
              end
            end
          end

          ap.transform_values(&:to_sym)
        end

        sig { override.params(resource_type: ResourceType).returns(Selection) }
        def selection_for(resource_type)
          return Selection::None if self.selections.nil?
          return Selection::None if T.must(self.selections)[resource_type].nil?

          T.must(T.must(self.selections)[resource_type])
        end

        sig { params(resource_type: ResourceType, selection: Selection).returns(Selection) }
        def set_selection_for(resource_type, selection)
          self.selections ||= {}
          T.must(self.selections)[resource_type] = selection

          selection
        end

        sig { params(resource_type: ResourceType).returns(SubjectIds) }
        def subject_ids_for(resource_type)
          return [] if self.subject_ids.nil?
          return [] if T.must(self.subject_ids)[resource_type].nil?

          T.must(T.must(self.subject_ids)[resource_type])
        end

        sig { params(resource_type: ResourceType, subject_ids: SubjectIds).returns(SubjectIds) }
        def set_subject_ids_for(resource_type, subject_ids)
          self.subject_ids ||= {}
          T.must(self.subject_ids)[resource_type] = subject_ids

          subject_ids
        end

        sig { params(resource_type: ResourceType).returns(T::Hash[String, Permission::Action]) }
        def subject_types_and_actions_for(resource_type)
          return {} if self.subject_types_and_actions.nil?
          return {} if T.must(self.subject_types_and_actions)[resource_type].nil?

          T.must(T.must(self.subject_types_and_actions)[resource_type])
        end

        sig { override.params(resource_type: ResourceType).returns(T::Array[String]) }
        def subject_types(resource_type)
          subject_types_and_actions_for(resource_type).keys
        end

        sig do
          params(
            resource_type: ResourceType,
            permissions: T::Hash[String, Symbol]
          ).returns(T::Hash[String, Permission::Action])
        end
        def set_subject_types_and_actions_for(resource_type, permissions)
          self.subject_types_and_actions ||= {}

          permissions = permissions.transform_values do |action|
            Permission::Action.from(action)
          end

          T.must(self.subject_types_and_actions)[resource_type] = permissions
        end

        sig do
          params(
            resource_type: ResourceType,
            permissions: T::Hash[String, Symbol]
          ).returns(T::Hash[String, Permission::Action])
        end
        def merge_subject_types_and_actions_for(resource_type, permissions)
          if subject_types_and_actions_for(resource_type).blank?
            return set_subject_types_and_actions_for(resource_type, permissions)
          end

          permissions = permissions.transform_values do |action|
            Permission::Action.from(action)
          end

          T.must(T.must(self.subject_types_and_actions)[resource_type]).merge!(permissions)
        end

        sig { params(resource_type: ResourceType).returns(AsymmetricAccessForResourceType) }
        def asymmetric_for(resource_type)
          return {} if self.asymmetric.nil?
          return {} if T.must(self.asymmetric)[resource_type].nil?

          T.must(T.must(self.asymmetric)[resource_type])
        end

        sig do
          params(
            resource_type: ResourceType,
            permission: String,
            action: T.any(String, Symbol),
            subject_ids: SubjectIds
          ).returns(SubjectIds)
        end
        def set_asymmetric_for(resource_type, permission, action, subject_ids)
          action = action.to_s

          self.asymmetric ||= {}

          # This is the true pain of Sorbet...
          T.must(self.asymmetric)[resource_type] ||= {}
          T.must(T.must(self.asymmetric)[resource_type])[permission] ||= {}
          T.must(T.must(T.must(self.asymmetric)[resource_type])[permission])[action] ||= []
          T.must(T.must(T.must(T.must(self.asymmetric)[resource_type])[permission])[action]).concat(subject_ids).uniq.sort!

          T.must(T.must(T.must(T.must(self.asymmetric)[resource_type])[permission])[action])
        end

        sig do
          override.
          params(
            resource_type: ResourceType,
            permissions: T::Hash[String, Symbol],
            selection: T.any(Selection, T::Array[Integer])
          ).void
        end
        def add_permissions_selection(resource_type:, permissions:, selection:)
          return if permissions.empty?

          resource_type = ResourceType.for(resource_type)
          selection_type = selection.is_a?(Selection) ? selection : Selection::Subset

          subject_ids = T.let([], T::Array[Integer])
          if selection_type == Selection::Subset
            subject_ids = T.cast(selection, T::Array[Integer])
          end

          existent_selection_type = selection_for(resource_type)
          same_selection = existent_selection_type == selection_type &&
            (selection == Selection::All || same_subset?(self.subject_ids_for(resource_type), subject_ids))

          if existent_selection_type == Selection::None && selection_resource_type?(resource_type)
            set_selection_for(resource_type, selection_type)
            set_subject_ids_for(resource_type, subject_ids) if selection_type.subset?
            set_subject_types_and_actions_for(resource_type, permissions)
          elsif same_selection
            merge_subject_types_and_actions_for(resource_type, permissions)
          elsif selection_type.subset?
            permissions.each do |permission, action|
              set_asymmetric_for(resource_type, permission, action, subject_ids)
            end
          end
        end

        sig do
          override.params(
            resource_type: ResourceType,
            selection: T.any(Selection, T::Array[Integer]),
            resource: String,
            action: T.any(Symbol, Permission::Action)
          ).returns(T::Boolean)
        end
        def explicitly_grants_permission?(resource_type:, selection:, resource:, action: :read)
          return false if resource_type.nil?

          current_selection_type = selection_for(resource_type)
          action = Permission::Action.from(action) unless action.is_a?(Permission::Action)

          case selection
          when Selection::All
            return false unless selection == current_selection_type

            actions = subject_types_and_actions_for(resource_type)
            return false unless actions[resource].present?

            T.must(actions[resource]) == action
          when Array
            return false if selection.blank?

            asymmetric_subjects_for_resource = asymmetric_for(resource_type)
              .fetch(resource, {})
              .fetch(action.to_sym.to_s, [])

            return true if every_subject_id_included?(selection, into: asymmetric_subjects_for_resource)

            return false if current_selection_type != Selection::Subset
            return false unless every_subject_id_included?(selection, into: subject_ids_for(resource_type))

            actions = subject_types_and_actions_for(resource_type)
            return false unless actions[resource].present?

            T.must(actions[resource]) == action
          else
            false
          end
        end

        sig { params(subset: SubjectIds, into: SubjectIds).returns(T::Boolean) }
        def every_subject_id_included?(subset, into:)
          (subset - into).empty?
        end

        sig { params(a: SubjectIds, b: SubjectIds).returns(T::Boolean) }
        def same_subset?(a, b)
          a.sort == b.sort
        end

        sig { params(resource_type: ResourceType).returns(T::Boolean) }
        def selection_resource_type?(resource_type)
          VALID_SELECTION_RESOURCE_TYPES.include?(resource_type)
        end
      end
    end
  end
end
