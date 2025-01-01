# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/gist_controller_helpers"

class GistsControllerEnterpriseManagedUserTest < GitHub::IntegrationTestCase
  skip_enterprise

  include GistsControllerTestHelpers

  fixtures do
    @description = "Peanut Butter!"
    @contents = [{ name: "hello.rb", value: "def hello; puts 'Hello!'; end" }]
    @emu = create(:emu)
    @biz = @emu.enterprise_managed_business
  end

  context "star" do
    test "can't star a regular user's gist" do
      gist = GistHelpers.generate(user: create(:user), contents: @contents, description: @description)

      as @emu
      assert_no_difference "@emu.starred_gists.count" do
        post gist_url_for(gist, path_segment: "star")
      end
      assert_response :not_found
    end

    test "can't star another EMUs gist" do
      another_emu = create :emu, business: @biz
      @biz.add_owner(another_emu, actor: @biz.owners.first)

      gist = GistHelpers.generate(user: another_emu, contents: @contents, description: @description)

      as @emu
      assert_no_difference "@emu.starred_gists.count" do
        post gist_url_for(gist, path_segment: "star")
      end
      assert_response :not_found
    end

    test "can't star its own gist gist" do
      # EMUs can't create Gists but we still want to make sure this is not possible
      gist = GistHelpers.generate(user: @emu, contents: @contents, description: @description)

      as @emu
      assert_no_difference "@emu.starred_gists.count" do
        post gist_url_for(gist, path_segment: "star")
      end
      assert_response :not_found
    end
  end

  context "create" do
    test "can't create public gists" do
      as @emu
      assert_no_difference "Gist.count" do
        post "gist", params: { gist: { "contents" => @contents, "public" => "1" } }
      end
      assert_response :not_found
    end

    test "can't create private gists" do
      as @emu
      assert_no_difference "Gist.count" do
        post "gist", params: { gist: { "contents" => @contents, "public" => "0" } }
      end
      assert_response :not_found
    end

    test "EMU ownership policy is overridden by controller when EMU creates a gist" do
      as @emu
      post "gist", params: { gist: { "contents" => @contents, "public" => "0" } }
      assert_response :not_found
    end

    test "EMU ownership policy is not applicable when regular user creates a gist" do
      as create(:user)
      post "gist", params: { gist: { "contents" => @contents, "public" => "0" } }
    end
  end

  context "fork" do
    test "doesn't create a fork for gist belonging to user outside of the enterprise" do
      gist = GistHelpers.generate(user: create(:user), contents: @contents, description: @description)

      as @emu
      assert_no_difference "gist.forks.count" do
        post gist_url_for(gist, path_segment: "fork")
      end

      assert_response :not_found
    end

    test "doesn't create a fork for gist belonging to EMU within the enterprise" do
      another_emu = create :emu, business: @biz
      @biz.add_owner(another_emu, actor: @biz.owners.first)

      gist = GistHelpers.generate(user: another_emu, contents: @contents, description: @description)

      as @emu
      assert_no_difference "gist.forks.count" do
        post gist_url_for(gist, path_segment: "fork")
      end

      assert_response :not_found
    end
  end
end
