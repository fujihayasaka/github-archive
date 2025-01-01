# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/gist_controller_helpers"

class GistsCommentsControllerEnterpriseManagedUserTest < GitHub::IntegrationTestCase
  skip_enterprise

  include GistsControllerTestHelpers

  fixtures do
    @description = "Peanut Butter!"
    @contents = [{ name: "hello.rb", value: "def hello; puts 'Hello!'; end" }]
    @emu = create(:emu)
    @biz = @emu.enterprise_managed_business
  end

  test "cannot comment on their own gist" do
    # EMUs can't create Gists but we still want to make sure this is not possible
    gist = GistHelpers.generate(user: @emu, contents: @contents, description: @description)

    as @emu
    assert_no_difference "GistComment.count" do
      post "/gist/#{gist.name_with_display_owner}/comments", params: { comment: { body: "I'm an EMU" } }
    end
    assert_response :not_found
  end

  test "cannot comment on another EMUs gist" do
    another_emu = create(:emu, business: @biz)
    @biz.add_owner(another_emu, actor: @biz.owners.first)

    gist = GistHelpers.generate(user: another_emu, contents: @contents, description: @description)

    as @emu
    assert_no_difference "GistComment.count" do
      post "/gist/#{gist.name_with_display_owner}/comments", params: { comment: { body: "I'm an EMU" } }
    end
    assert_response :not_found
  end

  test "cannot comment on regular user's gist" do
    gist = GistHelpers.generate(user: create(:user), contents: @contents, description: @description)

    as @emu
    assert_no_difference "GistComment.count" do
      post "/gist/#{gist.name_with_display_owner}/comments", params: { comment: { body: "I'm an EMU" } }
    end
    assert_response :not_found
  end
end
