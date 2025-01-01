# typed: true
# frozen_string_literal: true

require "test_helper"

class ImportItemTest < GitHub::TestCase
  include StringFromBinaryTestHelper

  fixtures do
    @owner = create :user, login: "owner"
    @repo = create :repository, owner: @owner, name: "public"
    @issue = create :issue, repository: @repo
  end

  test "supports emoji for json_data" do
    encoded_value = "{:\"hello 👋\"=>\"world 🌎\"}"
    encoded_value2 = "{:\"hello \xF0\x9F\x91\x8B\"=>\"world \xF0\x9F\x8C\x8E\"}"
    item = create :import_item, user: @owner, repository: @repo, status: "imported", model_type: "issue", model_id: @issue.id, json_data: encoded_value

    assert_multibyte_tracked_changes(item, :json_data, encoded_value, encoded_value2)
  end
end
