# typed: true
# frozen_string_literal: true

require "test_helper"

class Codespaces::FetchCascadeTokenTest < GitHub::TestCase
  test "caches tokens by default" do
    GitHub.flipper[:codespaces_force_no_cache_cascade_token].disable
    codespace_1 = create(:codespace)
    default_token = Codespaces::FetchCascadeToken.new(codespace: codespace_1, scope: "test-scope", ports: [80]).call
    same_token = Codespaces::FetchCascadeToken.new(codespace: codespace_1, scope: "test-scope", ports: [80]).call
    assert_equal default_token, same_token

    token_different_scope = Codespaces::FetchCascadeToken.new(codespace: codespace_1, scope: "test-scope-2", ports: [8080]).call
    refute_equal default_token, token_different_scope

    token_different_ports = Codespaces::FetchCascadeToken.new(codespace: codespace_1, scope: "test-scope", ports: [8080]).call
    refute_equal default_token, token_different_ports

    codespace_2 = create(:codespace)
    token_different_codespace = Codespaces::FetchCascadeToken.new(codespace: codespace_2, scope: "test-scope", ports: [80]).call
    refute_equal default_token, token_different_ports
  end

  test "does not cache tokens if `ignore_cache`" do
    codespace = create(:codespace)
    token_1 = Codespaces::FetchCascadeToken.new(codespace: codespace, ignore_cache: true).call
    token_2 = Codespaces::FetchCascadeToken.new(codespace: codespace, ignore_cache: true).call
    refute_equal token_1, token_2
  end
end
