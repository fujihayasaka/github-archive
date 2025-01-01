# typed: true
# frozen_string_literal: true

require "test_helper"

class OrganizationAccessorTest < GitHub::TestCase
  fixtures do
    @user = create(:user)
    @pull = create(:pull_request, :disable_disk_access)
  end

  def setup
    @accessor = Orgs::OrganizationAccessor.new
  end

  context "#by_id" do
    test "loads the organization for the given id" do
      org = create(:organization)
      result = @accessor.by_id(org.id)

      assert_equal org, result
    end

    test "executes no queries for invalid ids" do
      assert_query_count(0) { @accessor.by_id(0) }
    end
  end

  context "#by_name" do
    test "loads the organization for the given name" do
      org = create(:organization)
      result = @accessor.by_name(org.name)

      assert_equal org, result
    end

    test "executes no queries for invalid names" do
      assert_query_count(0) { @accessor.by_name("") }
    end
  end
end
