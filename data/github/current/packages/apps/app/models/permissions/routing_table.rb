# typed: true
# frozen_string_literal: true

module Permissions
  # Simple wrapper around the `abilities_permissions_routing` table, which is
  # located in the Collab cluster. This class should be used to query and
  # update the routing table from inside the monolith.
  class RoutingTable
    def self.migrated
      subject_types_in_cluster(cluster: :collab)
    end

    def self.in_progress
      subject_types_in_cluster(cluster: :moving)
    end

    def self.failed
      subject_types_in_cluster(cluster: :mysql1)
    end

    def self.subject_types_in_cluster(cluster:)
      AbilitiesPermissionsRouting.where(cluster: cluster).pluck(:subject_type)
    end

    def self.mark_as_in_progress!(subject_type:)
      mark_subject_type_in(subject_type: subject_type, cluster: :moving)
    end

    def self.mark_as_migrated!(subject_type:)
      mark_subject_type_in(subject_type: subject_type, cluster: :collab)
    end

    def self.mark_as_failed!(subject_type:)
      mark_subject_type_in(subject_type: subject_type, cluster: :mysql1)
    end

    def self.mark_subject_type_in(subject_type:, cluster:)
      return false unless subject_type.present?

      if (record = AbilitiesPermissionsRouting.find_by(subject_type: subject_type))
        record.update(cluster: cluster)
      else
        AbilitiesPermissionsRouting.create(subject_type: subject_type, cluster: cluster)
      end
    end
  end
end
