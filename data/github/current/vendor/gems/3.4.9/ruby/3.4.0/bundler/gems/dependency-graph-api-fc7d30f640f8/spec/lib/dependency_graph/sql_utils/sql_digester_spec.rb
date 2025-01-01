# frozen_string_literal: true

# Adapted from:
# https://github.com/github/github/blob/master/test/lib/github/sql/digester_test.rb

require "rails_helper"
require "dependency_graph/sql_utils/sql_digester"

describe DependencyGraph::SqlUtils::SqlDigester do
  def digest(sql)
    described_class.digest_sql(sql)
  end

  it "digests 'selects'" do
    expect(digest("SELECT 1")).to eq("SELECT ?")
    expect(digest("    SELECT   12345   ")).to eq("SELECT ?")
    expect(digest("SELECT * FROM users WHERE `users`.`id` = 123")).to eq("SELECT * FROM users WHERE users.id = ?")
  end

  it "digests 'strings'" do
    expect(digest("SELECT * FROM users WHERE `users`.`name` = 'jhawthorn'")).to eq("SELECT * FROM users WHERE users.name = ?")
    expect(digest("SELECT * FROM users WHERE `users`.`name` = \"jhawthorn\"")).to eq("SELECT * FROM users WHERE users.name = ?")

    expect(digest("SELECT * FROM airports WHERE `airports`.`name` = \"O'Hare\"")).to eq("SELECT * FROM airports WHERE airports.name = ?")
    expect(digest("SELECT * FROM airports WHERE `airports`.`name` = 'O\\'Hare'")).to eq("SELECT * FROM airports WHERE airports.name = ?")
    expect(digest("SELECT * FROM airports WHERE `airports`.`name` = \"O\\\"Hare\"")).to eq("SELECT * FROM airports WHERE airports.name = ?")
  end

  it "digests 'in'" do
    expect(digest("SELECT * FROM users WHERE id IN (1,2)")).to eq("SELECT * FROM users WHERE id IN ?")
    expect(digest("SELECT * FROM users WHERE id IN (1,2)")).to eq("SELECT * FROM users WHERE id IN ?")
    expect(digest("SELECT * FROM users WHERE name IN ('hawthorn','jhawthorn')")).to eq("SELECT * FROM users WHERE name IN ?")
  end

  it "digests true and false" do
    expect(digest("SELECT true")).to eq("SELECT ?")
    expect(digest("SELECT false")).to eq("SELECT ?")

    expect(digest("SELECT 1 FROM misconstrued")).to eq("SELECT ? FROM misconstrued")
    expect(digest("SELECT 1 FROM falsehoods")).to eq("SELECT ? FROM falsehoods")
  end

  it "removes comments" do
    expect(digest("SELECT 1")).to eq("SELECT ?")
    expect(digest("/* comment */ SELECT 1")).to eq("SELECT ?")
    expect(digest("SELECT /* comment */ 1")).to eq("SELECT ?")
    expect(digest("SELECT 1 /* comment */")).to eq("SELECT ?")
    expect(digest("SELECT /* comment */ 1 /* comment */")).to eq("SELECT ?")
    expect(digest("SELECT 1 /* comment */ FROM table where thing = 123 /* comment */")).to eq("SELECT ? FROM table where thing = ?")
  end
end
