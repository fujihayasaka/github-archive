# typed: true
# frozen_string_literal: true

require "test_helper"

class CodespacesVscsApiUrlTest < GitHub::TestCase

  context "#url" do
    test "given a known location" do
      api_url = Codespaces::VscsApiUrl.new(location: "WestUs2", vscs_target: :production)
      assert_equal "https://westus2.online.visualstudio.com", api_url.url
    end

    test "given an unknown location" do
      api_url = Codespaces::VscsApiUrl.new(location: "Narnia4",  vscs_target: :production)
      assert_equal "https://online.visualstudio.com", api_url.url
    end

    test "given a development target" do
      api_url = Codespaces::VscsApiUrl.new(location: "WestUs2", vscs_target: :development)
      assert_equal "https://westus2-ci-online.dev.core.vsengsaas.visualstudio.com", api_url.url
    end

    test "ignores vscs_target_url when not targeting :local" do
      codespace = build(:codespace, vscs_target_url: "https://vscstest.ngrok.io", location: "WestUs2")
      api_url = Codespaces::VscsApiUrl.for_codespace(codespace)
      assert_equal "https://westus2.online.visualstudio.com", api_url
    end

    test "uses the vscs_target_url from the codespace when the target is local" do
      codespace = build(:codespace, vscs_target_url: "https://vscstest.ngrok.io", vscs_target: :local)
      api_url = Codespaces::VscsApiUrl.for_codespace(codespace)
      assert_equal "https://vscstest.ngrok.io", api_url
    end

    test "uses the default url when the target is local and codespace vscs_target_url is blank" do
      codespace = build(:codespace, location: "WestUs2", vscs_target_url: "", vscs_target: :local)
      api_url = Codespaces::VscsApiUrl.for_codespace(codespace)
      assert_equal "https://westus2-ci-online.dev.core.vsengsaas.visualstudio.com", api_url
    end
  end
end
