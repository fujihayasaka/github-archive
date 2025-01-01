# typed: true
# frozen_string_literal: true

require "test_helper"

class PhotoDnaHitTest < GitHub::TestCase
  fixtures do
    @user = create(:user)
    @content = create(:user_asset, uploader: @user)
  end

  context "validations" do
    test "content cannot be nil" do
      hit = PhotoDnaHit.new(uploader: @user, content: nil)
      refute_predicate hit, :valid?
    end
  end

  test "if uploader account has been deleted, sets uploader as Ghost" do
    hit = PhotoDnaHit.new(uploader: nil, content: @content)
    hit.save
    assert_equal User.ghost, hit.uploader
  end

  context "for_user_asset" do
    test "returns nil if there is not a hit for this asset" do
      assert_empty PhotoDnaHit.for_user_asset(@content)
    end

    test "returns the hit if there is one for this asset" do
      hit = create(:photo_dna_hit, content: @content)

      assert_equal [hit], PhotoDnaHit.for_user_asset(@content)
    end
  end

  test "#purgeable returns only unpurged records older than 90 days" do
    old_enough = create(:photo_dna_hit, created_at: 100.days.ago)
    create(:photo_dna_hit, purged: true, created_at: 100.days.ago) # already purged
    create(:photo_dna_hit, created_at: 10.days.ago) # too new

    assert_equal [old_enough], PhotoDnaHit.purgeable
  end

  context ".purge_content" do
    test "marks as purged if content has previously been deleted" do
      hit = create(:photo_dna_hit, content: @content, uploader: @user)
      @content.destroy!
      hit.reload
      assert_nil hit.content

      hit.purge_content!
      assert hit.purged?
    end

    test "does not mark as purged and logs Failbot report if .purge call fails" do
      @content.stubs(:purge).returns(false)
      hit = create(:photo_dna_hit, content: @content, uploader: @user)

      message = "Purge failed for flagged content with class UserAsset and id #{@content.id}"
      Failbot.expects(:report).with(message)

      hit.purge_content!
      refute_predicate hit, :purged?
    end

    test "calls .purge on content otherwise" do
      hit = create(:photo_dna_hit, content: @content, uploader: @user)
      @content.expects(:purge).returns(true)
      hit.purge_content!
      assert_predicate hit, :purged?
    end
  end
end
