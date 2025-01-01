# typed: true
# frozen_string_literal: true

require "test_helper"

class DefinitionsMysqlSearchTest < GitHub::TestCase
  setup do
    @acme = create :enterprise_linked_organization, name: "acme"

    create :custom_property_definition, :single_select, source: @acme, property_name: "team"
    create :custom_property_definition, :string, source: @acme, property_name: "account-no"

    @biz = @acme.business
    create :custom_property_definition, :string, source: @biz, property_name: "enter"

    @secondo_org = create :enterprise_linked_organization, business: @biz, name: "secondo"
    create :custom_property_definition, :multi_select, source: @secondo_org, property_name: "team"
    create :custom_property_definition, :string, source: @secondo_org, property_name: "build_env"
  end

  [
    ["", %w(account-no build_env enter team team)],
    ["te", %w(enter team team)],
    ["eNTEr", %w(enter)],
    ["bui en", %w(build_env)],
    ["\"ente\"", []], # Quotes are just regular characters, so can only match if they were also on the property name
    ["build_env", %w(build_env)],
    ["nt-no", %w(account-no)],
    ["team", %w(team team)],
  ].each do |query, expected|
    test "search text at business-level for query '#{query}'" do
      run_test @biz, query, expected
    end
  end

  [
    ["org:acme", %w(account-no enter team)],
    ["org:ACME", %w(account-no enter team)],
    ["org:acme team", %w(team)],
    ["org:acme,secondo team", %w(team team)],
    ["org:acme managed-by:organization", %w(account-no team)],
    ["org:acme,secondo managed-by:organization", %w(account-no build_env team team)],
    ["org:acme,secondo managed-by:enterprise", %w(enter)],
    ["-org:acme", %w(build_env enter team)],
    ["-org:acme,secondo", %w(enter)],
  ].each do |query, expected|
    test "search by org at business-level for query '#{query}'" do
      run_test @biz, query, expected
    end
  end

  [
    ["managed-by:enterprise", %w(enter)],
    ["managed-by:ENTERPRISE", %w(enter)],
    ["managed-by:organization", %w(account-no build_env team team)],
    ["-managed-by:enterprise", %w(account-no build_env team team)],
    ["-managed-by:organization", %w(enter)],
    ["managed-by:enterprise managed-by:enterprise", %w(enter)],
  ].each do |query, expected|
    test "search by managed-by at business-level for query '#{query}'" do
      run_test @biz, query, expected
    end
  end

  [
    ["value-type:single_select", %w(team)],
    ["value-type:Single_SELECT", %w(team)],
    ["value-type:text", %w(account-no build_env enter)],
    ["value-type:string", %w(account-no build_env enter)],
    ["value-type:text,string,TEXT,STRING", %w(account-no build_env enter)],
    ["value-type:single_select,text", %w(account-no build_env enter team)],
    ["-value-type:single_select,multi_select", %w(account-no build_env enter)],
    ["value-type:true_false", []],
    ["value-type:invalid", %w(account-no build_env enter team team)],
  ].each do |query, expected|
    test "search by value-type at business-level for query '#{query}'" do
      run_test @biz, query, expected
    end
  end

  [
    ["", %w(account-no enter team)],
    ["te", %w(enter team)],
    ["eNTEr", %w(enter)],
    ["team", %w(team)],
  ].each do |query, expected|
    test "search by text at org-level for query '#{query}'" do
      run_test @acme, query, expected
    end
  end

  [
    ["org:acme", %w(account-no enter team)],
    ["org:secondo team", %w(team)],
    ["-org:acme", %w(account-no enter team)],
  ].each do |query, expected|
    test "org qualifier is ignored at org-level for query '#{query}'" do
      run_test @acme, query, expected
    end
  end

  [
    ["managed-by:enterprise", %w(enter)],
    ["managed-by:organization", %w(account-no team)],
    ["-managed-by:enterprise", %w(account-no team)],
    ["-managed-by:organization", %w(enter)],
  ].each do |query, expected|
    test "search by managed-by at org-level for query '#{query}'" do
      run_test @acme, query, expected
    end
  end

  [
    ["value-type:single_select", %w(team)],
    ["value-type:single_select,text", %w(account-no enter team)],
    ["-value-type:single_select,multi_select", %w(account-no enter)],
    ["value-type:true_false", []],
    ["value-type:invalid", %w(account-no enter team)],
  ].each do |query, expected|
    test "search by value-type at org-level for query '#{query}'" do
      run_test @acme, query, expected
    end
  end

  def run_test(source, query, expected)
    engine = Search::Definitions::MysqlSearch.new(source)
    results = engine.search(query, 1, per_page: 10)
    assert_equal expected, results[:items].map(&:property_name)
  end
end
