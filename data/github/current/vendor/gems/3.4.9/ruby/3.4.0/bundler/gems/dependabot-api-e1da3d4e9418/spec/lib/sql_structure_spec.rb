# frozen_string_literal: true

require "spec_helper"

RSpec.describe "db/enterprise_structure.sql" do # rubocop:disable RSpec/DescribeClass
  def detect_tables_from(path)
    regexes = [
      /CREATE TABLE `(?<table>.+)` \(/,
      /DROP TABLE IF EXISTS `(?<table>.+)`;/,
    ]
    File.readlines(path).map do |line|
      regexes.map do |regex|
        matches = line.match(regex)
        matches ? matches["table"] : nil
      end
    end.flatten.compact.uniq
  end

  it "keeps the enterprise schema up to date" do
    # use ./script/migrate to update the schema, it runs a custom rake task
    # (enterprise:sync_db_structure) to keep the enterprise schema up to date
    source_tables = detect_tables_from("db/structure.sql").map { |x| "dependabot_#{x}" }
    destintation_tables = detect_tables_from("db/enterprise_structure.sql")

    expect(destintation_tables).to match_array(source_tables)
  end

  it "inserts the versions into the correct schema_migrations table" do
    content = IO.read("db/enterprise_structure.sql")

    expect(content).not_to include("`schema_migrations`")
    expect(content).to include("`dependabot_schema_migrations`")
  end
end
