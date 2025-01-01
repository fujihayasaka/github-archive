# typed: true
# frozen_string_literal: true

require "test_helper"

class PermissionsRoutingTableTest < GitHub::TestCase

  context ".mark_as_failed" do
    test "always works" do
      assert Permissions::RoutingTable.mark_as_in_progress!(subject_type: "Collab/type")
      assert Permissions::RoutingTable.mark_as_failed!(subject_type: "Collab/type")

      results = Permissions::RoutingTable.failed
      assert_equal ["Collab/type"], results
    end
  end

  context ".mark_as_in_progress!" do
    test "works for migrated subject types" do
      assert Permissions::RoutingTable.mark_as_migrated!(subject_type: "Collab/type")
      assert Permissions::RoutingTable.mark_as_in_progress!(subject_type: "Collab/type")

      results = Permissions::RoutingTable.in_progress
      assert_equal ["Collab/type"], results
    end
  end

  context ".mark_as_migrated!" do
    test "works for in progress subject types" do
      assert Permissions::RoutingTable.mark_as_in_progress!(subject_type: "Collab/type")
      assert Permissions::RoutingTable.mark_as_migrated!(subject_type: "Collab/type")

      results = Permissions::RoutingTable.migrated
      assert_equal ["Collab/type"], results
    end
  end

  context ".migrated" do
    test "returns nothing when there are no subject types routed to collab" do
      results = Permissions::RoutingTable.migrated
      assert_empty results
    end

    test "returns nothing when requested subject types have been marked as in progress" do
      assert Permissions::RoutingTable.mark_as_in_progress!(subject_type: "Collab/type")

      results = Permissions::RoutingTable.migrated
      assert_empty results
    end

    test "returns subject types that have been fully migrated" do
      assert Permissions::RoutingTable.mark_as_migrated!(subject_type: "Collab/type")

      results = Permissions::RoutingTable.migrated
      assert_equal ["Collab/type"], results
    end
  end

  context ".in progress" do
    test "returns nothing when there are no subject types in progress" do
      results = Permissions::RoutingTable.in_progress
      assert_empty results
    end

    test "returns nothing when requested subject types have been marked as migrated" do
      assert Permissions::RoutingTable.mark_as_migrated!(subject_type: "Collab/type")

      results = Permissions::RoutingTable.in_progress
      assert_empty results
    end

    test "returns subject types that are in progress" do
      assert Permissions::RoutingTable.mark_as_in_progress!(subject_type: "Collab/type")

      results = Permissions::RoutingTable.in_progress
      assert_equal ["Collab/type"], results
    end
  end

  context ".mark_subject_type_in" do
    test "writes to all expected columns" do
      subject_type = "Collab/type"
      cluster      = 1

      Permissions::RoutingTable.mark_subject_type_in(subject_type: subject_type, cluster: cluster)

      # Because there is a unique index on a subject_type/cluster we can
      # only ever have one record.
      sql = Arel.sql(<<-SQL, subject_type: subject_type, cluster: cluster)
        SELECT id,
               cluster,
               subject_type,
               created_at,
               updated_at
        FROM abilities_permissions_routing
        WHERE subject_type = :subject_type
        AND cluster = :cluster
      SQL

      record = ApplicationRecord::Iam.connection.select_rows(sql).first
      id, actual_cluster, actual_subject_type, created_at, updated_at = record

      refute_nil id

      assert_equal cluster,      actual_cluster
      assert_equal subject_type, actual_subject_type

      refute_nil created_at, "expected created_at to not be nil"
      refute_nil updated_at, "expected updated_at to not be nil"
    end

    test "does not create two records with the same subject_type" do
      subject_type = "Collab/type"
      cluster      = :moving

      Permissions::RoutingTable.mark_subject_type_in(subject_type: subject_type, cluster: cluster)

      # Because there is a unique index on a subject_type/cluster we can
      # only ever have one record.
      records = AbilitiesPermissionsRouting.where(subject_type: subject_type)
      assert_equal 1, records.count

      permission_that_is_moving = records.first

      Permissions::RoutingTable.mark_subject_type_in(subject_type: subject_type, cluster: :collab)

      # Because there is a unique index on a subject_type/cluster we can
      # only ever have one record.
      records = AbilitiesPermissionsRouting.where(subject_type: subject_type)
      assert_equal 1, records.count

      permission_that_has_been_migrated = records.first
      assert_equal permission_that_is_moving, permission_that_has_been_migrated
    end
  end
end
