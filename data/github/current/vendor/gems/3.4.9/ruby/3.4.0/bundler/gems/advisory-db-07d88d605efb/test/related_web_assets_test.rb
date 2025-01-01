# frozen_string_literal: true

require "test_helper"
require "json"

module AdvisoryDB
  class RelatedWebAssetsTest < ActionDispatch::IntegrationTest
    test "rails modules in package.json match versions with current rails version" do
      # If you see this test fail, don't fret! This is just making sure that if someone upgrades our rails version, they *also* upgrade our NPM package.json rails packages too.
      # Also make sure to update yarn.lock so people don't see the file edited locally! (run script/bootstrap).
      # There is no test for yarn.lock because it uses a strangely formatted yaml format that fails to parse.
      # If we update to yarn v2 this will not be a problem (https://github.com/yarnpkg/yarn/issues/5629)
      current_rails_version = Gem.loaded_specs["rails"].version.to_s
      packages = get_packages_from_package_json(%r{@rails/.*})
      assert packages.count > 0
      packages.each_value do |version|
        assert_match(/#{current_rails_version}/, version)
      end
    end

    test "primer view components versions line up with package.json" do
      # If you see this test fail, don't fret! This is just making sure that if someone upgrades primer-view-components, they *also* upgrade related files.
      current_pvc_version = Gem.loaded_specs["primer_view_components"].version.to_s
      assert_equal current_pvc_version, get_version_from_package_json("@primer/view-components")
    end

    test "primer view components versions line up with app/views/layouts/application.html.erb" do
      # If you see this test fail, don't fret! This is just making sure that if someone upgrades primer-view-components, they *also* upgrade related files.
      user = create(:user)
      # We are using advisory_reviews just to get at the app shell
      get "/advisory_reviews", headers: { "X-Okta-Username" => user.email }
      assert_response :ok
      app_erb = response.body
      current_pvc_version = Gem.loaded_specs["primer_view_components"].version.to_s
      assert app_erb.match?(%r{<link\s+(?:[^>]*?\s+)?href=(["'])https://unpkg.com/@primer/view-components@#{current_pvc_version}(.*?)\1})
    end

    test "primer css versions line up with package.json" do
      # If you see this test fail, don't fret! This is just making sure that if someone upgrades primer-view-components, they *also* upgrade related files.
      user = create(:user)
      # We are using advisory_reviews just to get at the app shell
      get "/advisory_reviews", headers: { "X-Okta-Username" => user.email }
      assert_response :ok
      app_erb = response.body
      primer_version = get_version_from_package_json("@primer/css")
      assert app_erb.match?(%r{<link\s+(?:[^>]*?\s+)?href=(["'])https://unpkg.com/@primer/css@#{primer_version}(.*?)\1})
    end

    def get_version_from_package_json(package_name)
      file = File.read "package.json"
      data = JSON.parse file
      data["dependencies"][package_name]
    end

    def get_packages_from_package_json(package_matcher)
      file = File.read "package.json"
      data = JSON.parse file
      # UJS is archived and we need to figure out what to do with it
      package_names_that_arent_tested = ["@rails/ujs"]
      data["dependencies"].select do |package_name, _version|
        (package_names_that_arent_tested.exclude? package_name) && package_name.match?(package_matcher)
      end
    end
  end
end
