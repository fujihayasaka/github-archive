# typed: true
# frozen_string_literal: true

require "test_helper"

class AbilitiesPermissionsRoutingTest < GitHub::TestCase
  fixtures do
    @subject = AbilitiesPermissionsRouting.create(
      subject_type: "Collab/type",
      cluster:      :moving,
    )

    assert_predicate @subject, :valid?
  end

  test "uses the abilities_permissions_routing table" do
    assert_equal "abilities_permissions_routing", AbilitiesPermissionsRouting.table_name
  end

  test "must have a subject_type" do
    @subject.update(subject_type: nil)
    refute_predicate @subject, :valid?
  end

  test "must have a cluster" do
    @subject.update(cluster: nil)
    refute_predicate @subject, :valid?
  end

  test "each subject_type can only be in one cluster at a time" do
    duplicate = AbilitiesPermissionsRouting.create(
      subject_type: "Collab/type",
      cluster:      :moving,
    )

    refute_predicate duplicate, :valid?
  end
end
