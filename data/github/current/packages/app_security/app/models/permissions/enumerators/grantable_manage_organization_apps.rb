# typed: true
# frozen_string_literal: true

module Permissions
  module Enumerators
    class GrantableManageOrganizationApps < Permissions::Enumerator
      def actor_ids
        all_members = Enumerators::BelongToOrganization.new(subject_id: subject_id).actor_ids
        already_granted = Enumerators::ManageAllApps.new(subject_id: subject_id).actor_ids
        owners = Enumerators::OwnOrganization.new(subject_id: subject_id).actor_ids

        (all_members - already_granted) - owners
      end
    end
  end
end
