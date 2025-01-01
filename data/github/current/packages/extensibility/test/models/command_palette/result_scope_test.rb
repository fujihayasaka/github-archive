# typed: true
# frozen_string_literal: true

require "test_helper"

module CommandPalette
  class ResultScopeTest < GitHub::TestCase
    include GitHub::CommandPaletteTestHelpers

    test "supports all command palette scopes" do
      CommandPaletteHelper::SUPPORTED_SCOPE_CLASS_NAMES.each do |scope_klass_name|
        assert_includes ResultScope::CLASS_TO_TYPE.keys, scope_klass_name
      end
    end

    test "build tokens for each class" do
      CommandPalette::ResultScope::CLASS_TO_TYPE.keys.each do |scope_klass|
        scope_object = build(scope_klass.underscore.to_sym)
        scope_object.stubs(:global_relay_id).returns("1234")
        result_scope = CommandPalette::ResultScope.new(scope_object)
        assert result_scope.tokens
      end
    end

    test "creates scope for User" do
      user = create(:user)
      scope = ResultScope.new(user)
      expected_tokens = [ResultToken.new(id: user.global_relay_id, type: "owner", text: user.login)]
      assert_scope(scope, expected_tokens)
    end

    test "creates scope for a MemexProject" do
      user = create(:user)
      memex_project = create(:memex_project, owner: user)
      scope = ResultScope.new(memex_project)
      expected_tokens = [
        ResultToken.new(id: user.global_relay_id, type: "owner", text: user.login),
        ResultToken.new(id: memex_project.global_relay_id, type: "memex_project", text: "Project ##{memex_project.number}"),
      ]
      assert_scope(scope, expected_tokens)
    end

    test "creates scope for Organization" do
      org = create(:organization)
      scope = ResultScope.new(org)
      expected_tokens = [ResultToken.new(id: org.global_relay_id, type: "owner", text: org.login)]
      assert_scope(scope, expected_tokens)
    end

    test "creates scope for Repository" do
      repo = create(:repository)
      scope = ResultScope.new(repo)
      expected_tokens = [
        ResultToken.new(id: repo.owner.global_relay_id, type: "owner", text: repo.owner.login),
        ResultToken.new(id: repo.global_relay_id, type: "repository", text: "#{repo.name}", value: repo.name)
      ]
      assert_scope(scope, expected_tokens)
    end

    test "creates scope for Pull Request" do
      repo = create(:repository)
      pull_request = create :pull_request, :disable_disk_access, repository: repo
      scope = ResultScope.new(pull_request)
      expected_tokens = [
        ResultToken.new(id: repo.owner.global_relay_id, type: "owner", text: repo.owner.login),
        ResultToken.new(id: repo.global_relay_id, type: "repository", text: "#{repo.name}", value: repo.name),
        ResultToken.new(id: pull_request.global_relay_id, type: "pull_request", text: "Pull requests ##{pull_request.number}", value: "Pull requests ##{pull_request.number}")
      ]
      assert_scope(scope, expected_tokens)
    end

    def assert_scope(scope, expected_tokens)
      assert scope.respond_to?(:as_json), "doesn't respond to #as_json"
      assert scope.as_json.is_a?(Hash), "#as_json doesn't return Hash"

      parsed_scope = JSON.parse(scope.to_json)
      parsed_tokens = JSON.parse(expected_tokens.to_json)

      assert_expected_type("[tokens]", parsed_scope["tokens"], Array)
      assert_same_elements parsed_scope["tokens"], parsed_tokens
    end
  end
end
