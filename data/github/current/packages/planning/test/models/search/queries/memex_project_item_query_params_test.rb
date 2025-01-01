# typed: true
# frozen_string_literal: true

require "test_helper"

class MemexProjectItemQueryParamsTest < GitHub::TestCase

  fixtures do
    @user = create(:verified_user, login: "project-admin")
    @memex = create(:memex_project, owner: @user)
  end

  def mock_search
    Elastomer::Indexes::MemexProjectItems.any_instance
      .expects(:search).with { |query, params| yield query, params }
      .returns({ "hits" => { "total" => 0, "hits" => [] } })

    Search::Queries::MemexProjectItemQuery.new(
      project: @memex,
      viewer: @user,
    ).execute
  end

  test "includes project id as routing value" do
    mock_search do |_, params|
      assert_equal @memex.id, params[:routing]
    end
  end

  test "includes custom timeout value when flag is set" do
    enable_feature_flag(:mwl_increased_query_timeout, @user)
    mock_search do |_, params|
      assert_equal "500ms", params[:timeout]
    end
  end

  test "reverts to default timeout value when flag is not set" do
    disable_feature_flag(:mwl_increased_query_timeout, @user)
    mock_search do |_, params|
      assert_equal GitHub.es_query_timeout, params[:timeout]
    end
  end
end
