# frozen_string_literal: true

require "test_helper"
require "configs"

class ConfigsEntryTest < Minitest::Test
  def test_from_twirp_config
    created_time = Time.now
    updated_time = Time.now + 1

    twirp_config = Configs::Twirp::Config.new(
      name: "config_from_twirp",
      value: "value_from_twirp",
      final: false,
      target: Configs::Twirp::ConfigTarget.new(type: :Business, id: 456),
      created_at: created_time,
      updated_at: updated_time
    )

    entry = Configs::Entry.from_twirp_config(twirp_config)

    assert_equal "config_from_twirp", entry.name
    assert_equal "value_from_twirp", entry.value
    assert_equal false, entry.final
    assert_equal "Business", entry.target_type
    assert_equal 456, entry.target_id
    assert_equal created_time, entry.created_at
    assert_equal updated_time, entry.updated_at
  end

  def test_legacy_target_type_from_proto
    assert_equal "Repository", Configs::Entry.legacy_target_type_from_proto(:Repository)
    assert_equal "User", Configs::Entry.legacy_target_type_from_proto(:User)
    assert_equal "Business", Configs::Entry.legacy_target_type_from_proto(:Business)
    assert_equal "global", Configs::Entry.legacy_target_type_from_proto(:Global)
  end

  def test_immutability
    entry = Configs::Entry.new(
      name: "immutable_test",
      value: "original_value",
      final: false,
      target_type: "Business",
      target_id: 100,
      created_at: Time.now,
      updated_at: Time.now
    )

    assert entry.frozen?
  end

  def test_to_h_conversion
    entry = Configs::Entry.new(
      name: "test_config",
      value: "test_value",
      final: true,
      target_type: "Business",
      target_id: 123,
      created_at: Time.now,
      updated_at: Time.now
    )

    assert_equal entry, Configs::Entry.new(**entry.to_h)
  end
end
