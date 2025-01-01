# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/gist_controller_helpers"

class GistsControllerEditGistHttpTest < GitHub::IntegrationTestCase
  include GistsControllerTestHelpers
  extend GistsControllerTestSetup

  skip_with_all_emus

  fixtures(&fixtures_block)
  setup(&global_setup_block)

  if GitHub.anonymized_private_repo_analytics?
    test "masks the location for google analytics" do
      as @pub_user
      get gist_url_for(@pub_gist, path_segment: "edit")

      assert_select "meta[name=\"analytics-location\"][content=\"/gist/<user-name>/<gist-id>/edit\"]"
    end
  end
end
