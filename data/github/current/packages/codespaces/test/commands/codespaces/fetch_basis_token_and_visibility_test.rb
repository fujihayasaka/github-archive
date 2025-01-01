# typed: true
# frozen_string_literal: true

require "test_helper"

class Codespaces::FetchBasisTokenAndVisibilityTest < GitHub::TestCase
  include CodespacesPlanFixtures
  include GitHub::LoggerHelper

  test "logs error on vscs request failure" do
    error = Faraday::TimeoutError.new("Boom!")
    Codespaces::FetchBasisTokenAndVisibility.any_instance.stubs(:fetch_tunnel_access_token_and_visibility).raises(error)

    codespace = create(:codespace)

    Failbot.expects(:report).with(
      error,
      equals({
        "catalog_service" => "github/codespaces",
        "gh.codespaces.guid" => codespace.guid,
        "gh.codespaces.vscs_target" => codespace.vscs_target,
        "gh.codespaces.region" => codespace.location,
      }),
    )

    Codespaces::FetchBasisTokenAndVisibility.new(codespace: codespace, port: 80).call
  end

  test "returns token and visibility on success" do
    codespace = create(:codespace)
    token, visibility = Codespaces::FetchBasisTokenAndVisibility.new(codespace: codespace, port: 80).call

    refute_nil token
    refute_nil visibility
  end
end
