# typed: true
# frozen_string_literal: true

require "test_helper"

class StafftoolsBulkDmcaTakedownNoticeTest < GitHub::TestCase
  fixtures do
    @repos = create_list :repository, 3
    @staff = create :staff_admin_user
    @url = "https://github.com/github/dmca/blob/master/2011/2011-01-27-sony.markdown"
    @valid_takedown = Stafftools::BulkDmcaTakedown.create({ repositories: @repos, disabling_user: @staff, notice_public_url: @url })
    @text =
      <<~HEREDOC
        Please remove these repos they are bad:

        #{@repos[0].http_url.chomp('.git')}/blob/xxx/README.md
        #{@repos[1].http_url.chomp('.git')}/blob/xxx/SECRET.md
        #{@repos[2].http_url.chomp('.git')}/blob/xxx/README.md
      HEREDOC
  end

  setup do
    @notice = Stafftools::BulkDmcaTakedown::Notice.new({ notice_text: @text, public_url: @url })
  end

  test "validates the presence of a takedown url" do
    @notice.public_url = nil
    refute @notice.valid?
    refute_nil @notice.errors[:public_url]
  end

  test "validates for the presence of takedown text" do
    @notice.notice_text = nil
    refute @notice.valid?
    refute_nil @notice.errors[:notice_text]
  end

  test "parses text and creates a list of grouped repos" do
    assert_equal @notice.grouped_urls.keys, @repos
  end

  test "validates the format of the public url" do
    @notice.public_url = "http://github.localhost/mona/take_down/blob/master/README.md"
    refute @notice.valid?
    refute_nil @notice.errors[:public_url]
  end

  test "validates the number of repos" do
    Stafftools::BulkDmcaTakedown.stub_const(:MAX_REPOS, 1) do
      notice = Stafftools::BulkDmcaTakedown::Notice.new({ notice_text: @text, public_url: @url })

      refute notice.valid?
      assert_equal notice.errors[:notice_text][0], "can contain at most 1 repositories"
    end
  end
end
