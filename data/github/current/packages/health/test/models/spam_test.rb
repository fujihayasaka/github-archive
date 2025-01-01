# typed: true
# frozen_string_literal: true

require "test_helper"

class SpamTest < GitHub::TestCase
  def gist_test_content_array
    [{ name: "1", value: "random content" }]
  end

  fixtures do
    @owner          = create(:user)
    @public_repo    = create(:public_repository, owner: @owner)

    @gist = GistHelpers.generate(contents: gist_test_content_array,
                           user: @owner,
                           created_at: 5.minutes.ago,
                           updated_at: 5.minutes.ago,
                         )
  end

  context "Spam.normalize" do
    test "raises Spam::ErrorsDependency::BadLabel when passed a bogus label" do
      assert_raises(Spam::ErrorsDependency::BadLabel) do
        Spam.normalize("I am not a proper label, not at all")
      end
    end

    test "returns the normalized form of a valid label" do
      assert_equal 0, Spam.normalize("HAM")
    end
  end
end

class SpamIpBlacklistingTest < GitHub::TestCase
  test "IP is not blacklisted by default" do
    refute Spam.ip_is_denylisted?("8.8.8.8")
  end

  test "IP can be blackisted" do
    Spam.ip_denylist("8.8.8.8")
    assert Spam.ip_is_denylisted?("8.8.8.8")
  end

  test "assumes IP is not blacklisted if GitHub::KV is down" do
    Spam.ip_denylist("8.8.8.8")
    assert Spam.ip_is_denylisted?("8.8.8.8")

    result = GitHub::Result.new { raise "Some GitHub::KV Failure" }
    Spam::Kv.store.stubs(:get).returns(result)

    refute Spam.ip_is_denylisted?("8.8.8.8")
  end

  test "IP can be removed from blacklist" do
    Spam.ip_denylist("8.8.8.8")
    assert Spam.ip_is_denylisted?("8.8.8.8")

    Spam.ip_undenylist("8.8.8.8")
    refute Spam.ip_is_denylisted?("8.8.8.8")
  end

  test "IP can be added to and removed from safelist" do
    refute Spam.ip_safelisted?("1.2.3.4"), "IP is not in safelist"

    Spam.ip_add_to_safelist("1.2.3.4")
    assert Spam.ip_safelisted?("1.2.3.4"), "IP is in safelist"

    Spam.ip_remove_from_safelist("1.2.3.4")
    refute Spam.ip_safelisted?("1.2.3.4"), "IP is not in safelist"
  end
end
