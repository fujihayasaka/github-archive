# typed: true
# frozen_string_literal: true

require "test_helper"

class RoleFgpsTest < GitHub::TestCase
  fixtures do
    @org = create(:organization)
  end

  setup do
    @read_fgps = RoleFgps.for(base_role: :read, org: @org)
    @triage_fgps = RoleFgps.for(base_role: :triage, org: @org)
    @maintain_fgps = RoleFgps.for(base_role: :maintain, org: @org)
  end

  context "Dependabot alerts FGPs" do
    test "are included" do
      read_fgps = RoleFgps.for(base_role: :read, org: @org)

      view_dependabot_alerts = read_fgps.available_fgps(@org).find { |fgp| fgp.label == :view_dependabot_alerts }
      resolve_dependabot_alerts = read_fgps.available_fgps(@org).find { |fgp| fgp.label == :resolve_dependabot_alerts }

      assert view_dependabot_alerts
      assert resolve_dependabot_alerts
    end
  end

  test "RoleFgps.for takes a string" do
    new_read = RoleFgps.for(base_role: "read", org: @org)

    assert new_read
    # comparing labels as the objects themselves are not equal
    assert_same_elements @read_fgps.implicit_fgps.map(&:label), new_read.implicit_fgps.map(&:label)
    assert_same_elements @read_fgps.available_fgps(@org).map(&:label), new_read.available_fgps(@org).map(&:label)
  end

  test "has valid edge cases for implicit and available roles" do
    # read has no implicit FPGs, all of them area available to choose
    assert_empty @read_fgps.implicit_fgps
    assert_same_elements RoleFgps.custom_role_fgps(@org), @read_fgps.available_fgps(@org).map(&:label)
  end

  test "#implicit_fgps generates appropriate FGP metadata" do
    add_label = @triage_fgps.implicit_fgps.find { |fgp| fgp.label == :add_label }

    assert add_label
    assert_equal :issues_prs, add_label.category
    assert_equal "Add or remove a label", add_label.description
  end

  test "#available_fgps generates appropriate FGP metadata" do
    edit_repo_metadata = @triage_fgps.available_fgps(@org).find { |fgp| fgp.label == :edit_repo_metadata }

    assert edit_repo_metadata
    assert_equal :repository, edit_repo_metadata.category
    assert_equal "Edit repository metadata", edit_repo_metadata.description
  end

  context "quickfix for staff shipping" do
    test "does not show unavailable fgps in implicit" do
      unavailable_fgps = RoleFgps::UNAVAILABLE_FGPS

      unavailable_fgps.each do |fgp|
        refute_includes @maintain_fgps.implicit_fgps.map(&:label), fgp
      end
    end

    test "does not show unavailable_fgps in available_fgps" do
      unavailable_fgps = RoleFgps::UNAVAILABLE_FGPS

      unavailable_fgps.each do |fgp|
        refute_includes @read_fgps.available_fgps(@org).map(&:label), fgp
      end
    end
  end

  context "fgps_payload" do
    test "returns a hash of fgps with their metadata" do
      payload = RoleFgps.fgps_payload(@org)

      assert_instance_of Hash, payload
      refute_empty payload

      payload.each do |label, fgp|
        assert_instance_of Hash, fgp
        assert_equal fgp[:label], label
        assert fgp[:category]
        assert fgp[:description]
        assert fgp.key?(:base_role)
      end
    end
  end
end
