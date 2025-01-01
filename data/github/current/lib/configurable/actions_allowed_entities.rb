# typed: false
# frozen_string_literal: true

module Configurable
  module ActionsAllowedEntities
    KEY = Configurable::ActionsAllowedByOwner::KEY

    # returns a list of ids of children entities who are allowed to run actions
    # for an enterprise this will be a list of orgs where actions_allowed_by_owner is true
    def actions_allowed_entities
      entries = []
      target_ids = []
      target_type = ""
      if self.is_a?(Business)
        target_ids = self.organization_ids
        target_type = "User"
      end
      if self.is_a?(Organization)
        target_ids = self.repository_ids
        target_type = "Repository"
      end

      if target_ids.present? && target_type.present?
        target_ids.each_slice(500) do |slice|
          entries.concat ::Configuration::Entry
            .targeting_type(target_type)
            .named(KEY)
            .with_true_value
            .for_target_id(slice)
            .pluck(:target_id)
        end
      end

      entries
    end
  end
end
