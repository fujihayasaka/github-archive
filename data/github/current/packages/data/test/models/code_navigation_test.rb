# typed: true
# frozen_string_literal: true

require "test_helper"

class CodeNavigationTest < GitHub::TestCase
  include HydroTestHelpers
  include AlephTestHelpers

  self.strict_fixtures = false # rubocop:todo GitHub/StrictFixtures
  fixtures do
    @repo = create(:private_repository, from_example: :tagsearch)
    @owner = @repo.owner
    @repo.analyze_languages
    @ref = @repo.refs.find("master")
    @message = {
      request_context: Hydro::EntitySerializer.request_context(GitHub.context.to_hash),
      actor: Hydro::EntitySerializer.user(@owner),
      owner: Hydro::EntitySerializer.user(@owner),
      repository: Hydro::EntitySerializer.repository(@repo),
      after: @ref.target_oid,
      ref: @ref.qualified_name,
      feature_flags: [],
    }

    GitHub.flipper[:aleph_reindex_language_go].disable
    GitHub.flipper[:aleph_language_ruby].enable
  end

  test "queries aleph for symbols" do
    stub_aleph_find_symbols_for_path

    code_nav = CodeNavigation.load(
      current_repository: @repo,
      current_user: @owner,
      tree_name: @ref.name,
      commit_oid: @ref.target_oid,
      path: "test.go",
      language: "Go",
    )

    assert_equal :ok, code_nav.state
    assert code_nav.has_code_symbols?
    assert_equal 1, code_nav.code_symbols.size
  end

  test "queries aleph for symbols passing various tree names" do
    [nil, "", @ref.name, @ref.qualified_name, "not-a-ref", @ref.target_oid].each do |tree_name|
      stub_aleph_find_symbols_for_path

      code_nav = CodeNavigation.load(
        current_repository: @repo,
        current_user: @owner,
        tree_name: tree_name,
        commit_oid: @ref.target_oid,
        path: "test.go",
        language: "Go"
      )

      assert_equal :ok, code_nav.state
      assert code_nav.has_code_symbols?
      assert_equal 1, code_nav.code_symbols.size
    end
  end
end unless GitHub.enterprise?
