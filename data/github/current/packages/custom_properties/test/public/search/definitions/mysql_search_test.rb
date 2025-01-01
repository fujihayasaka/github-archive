# typed: true
# frozen_string_literal: true

require "test_helper"

class DefinitionsMysqlSearchTest < GitHub::TestCase
  setup do
    @acme = create :enterprise_linked_organization, name: "acme"

    create :custom_property_definition, :string, source: @acme, property_name: "team"
    create :custom_property_definition, :string, source: @acme, property_name: "account"

    @biz = @acme.business
    create :custom_property_definition, :string, source: @biz, property_name: "enter"

    @secondo_org = create :enterprise_linked_organization, business: @biz, name: "secondo"
    create :custom_property_definition, :string, source: @secondo_org, property_name: "team"
    create :custom_property_definition, :string, source: @secondo_org, property_name: "env"
  end

  [
    ["", %w(account enter env team team)],
    ["te", %w(enter team team)],
    ["eNTEr", %w(enter)],
    ["team", %w(team team)],
    ["org:acme", %w(account enter team)],
    ["org:ACME", %w(account enter team)],
    ["org:acme team", %w(team)],
    ["org:acme,secondo team", %w(team team)],
    ["org:acme managed-by:organization", %w(account team)],
    ["org:acme,secondo managed-by:organization", %w(account env team team)],
    ["org:acme,secondo managed-by:enterprise", %w(enter)],
    ["-org:acme", %w(enter env team)],
    ["-org:acme,secondo", %w(enter)],
    ["managed-by:enterprise", %w(enter)],
    ["managed-by:organization", %w(account env team team)],
    ["-managed-by:enterprise", %w(account env team team)],
    ["-managed-by:organization", %w(enter)],
    ["managed-by:enterprise managed-by:enterprise", %w(enter)],
  ].each do |query, expected|
    test "search definitions works for query '#{query}'" do
      results = Search::Definitions::MysqlSearch.search(@biz, query, 1, per_page: 10)
      assert_equal expected, results[:items].map(&:property_name)
    end
  end
end
