# typed: true
# frozen_string_literal: true

require "test_helper"

class RepositoryActionsOIDCConfigTest < GitHub::TestCase
  include DogstatsTestHelpers

  fixtures do
    # @org = create(:organization, admin: @admin)
    @entity = RepositoryActionsOIDCConfig.create(repository_id: 1, configuration: { test_key: "test_value" })
    @entity_bool = RepositoryActionsOIDCConfig.create(repository_id: 100, configuration: {
      k1: true,
      k2: false,
      })

  end

  context "db" do

    # Test if we have three seeded templates
    test "Sanity" do
      # Ensuring we have the record(s) to start with
      assert(!@entity.new_record?, "template1 is not saved")
    end

    # Test the fetched entity
    test "Record fetch" do
      sut = RepositoryActionsOIDCConfig.get_configurations(1)
      assert_equal({ "test_key" => "test_value" }, sut)
    end

    # Test record append
    test "Record append" do
      # since the record already exists, it should not be created again but updated
      RepositoryActionsOIDCConfig.update_configurations(1, { "test_key2" => "test_value2" })
      # fetch the updates
      sut = RepositoryActionsOIDCConfig.get_configurations(1)
      assert_equal({ "test_key" => "test_value", "test_key2" => "test_value2" }, sut)
    end

    # Test record update
    test "Record update" do
      # since the record already exists, it should not be created again but updated
      RepositoryActionsOIDCConfig.update_configurations(1, { "test_key2" => "test_value_new" })
      # fetch the updates
      sut = RepositoryActionsOIDCConfig.get_configurations(1)
      assert_equal({ "test_key" => "test_value", "test_key2" => "test_value_new" }, sut)
    end

    # Test new record
    test "New Record" do
      # If record does not exist, it should be created
      RepositoryActionsOIDCConfig.update_configurations(2, { "new_key" => "new_value" })
      # fetch the updates
      sut = RepositoryActionsOIDCConfig.get_configurations(2)
      assert_equal({ "new_key" => "new_value" }, sut)
    end

    # Test missing record
    test "No record" do
      sut = RepositoryActionsOIDCConfig.get_configurations(1000)
      assert_equal({}, sut)
    end

    # Test value fetch
    test "Value fetch when given a key" do
      sut = RepositoryActionsOIDCConfig.get_configuration(1, "test_key")
      assert_equal("test_value", sut)
    end

    # Test boolean value fetch
    test "Test boolean fetch" do
      sut = RepositoryActionsOIDCConfig.get_configuration(100, "k1")
      assert sut, "Value must be true"

      sut = RepositoryActionsOIDCConfig.get_configuration(100, "k2")
      assert !sut, "Value must be false"

      sut = RepositoryActionsOIDCConfig.get_configuration(100, "k3")
      assert sut.nil?, "Value must be nil, when not present"
      assert !sut, "Value must be false, when not present"
    end

    # Test boolean value fetch with default
    test "Test boolean fetch with default" do
      sut = RepositoryActionsOIDCConfig.get_configuration(100, "k3", true)
      assert sut.present?, "the returned value must default value, when not present"
      assert sut, "the returned value must default value, when not present"
    end

  end
end
