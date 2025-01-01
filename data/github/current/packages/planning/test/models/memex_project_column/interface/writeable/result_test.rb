# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/planning"

class MemexProjectColumnWriteableResultTest < GitHub::TestCase
  include DogstatsTestHelpers

  Writeable = MemexProjectColumn::Interface::Writeable

  context "#initialize" do
    test "increments a stat that denotes a successful MySQL write and an omitted Elasticsearch write" do
      Writeable::Result.new(mysql: Writeable::PartialResult.success)
      assert_dogstats_increment(1, Writeable::Result::STAT, tags: ["mysql_success:true", "elasticsearch_success:n/a"])
    end

    test "increments a stat that denotes a successful MySQL write and a failed Elasticsearch write" do
      Writeable::Result.new(
        mysql: Writeable::PartialResult.success,
        elasticsearch: Writeable::PartialResult.failure("boom")
      )
      assert_dogstats_increment(1, Writeable::Result::STAT, tags: ["mysql_success:true", "elasticsearch_success:false"])
    end

    test "increments a stat that denotes both a successful MySQL write and a successful Elasticsearch write" do
      Writeable::Result.success
      assert_dogstats_increment(1, Writeable::Result::STAT, tags: ["mysql_success:true", "elasticsearch_success:true"])
    end
  end
end
