# typed: true
# frozen_string_literal: true

require "test_helper"

require "test_helpers/dgit"

class RepositoryDormantTest < GitHub::TestCase
  fixtures do
    @long_ago = (Time.now - (GitHub.dormancy_threshold + 1.month)).freeze
    @recently = (Time.now - (GitHub.dormancy_threshold - 15.days)).freeze
    @repo = create(:repository, created_at: @long_ago)
  end

  test "is dormant if never pushed to" do
    @repo.update_attribute(:pushed_at, nil)
    assert @repo.reload.dormant?
  end

  test "is dormant if not touched within the dormancy threshold" do
    @repo.update_attribute(:pushed_at, @long_ago)
    assert @repo.reload.dormant?
  end

  test "not dormant if created within the dormancy threshold" do
    @repo.update_attribute(:created_at, @recently)
    @repo.update_attribute(:pushed_at, nil)
    assert !@repo.reload.dormant?
  end

  test "not dormant if pushed to within the dormancy threshold" do
    @repo.update_attribute(:pushed_at, @recently)
    assert !@repo.reload.dormant?
  end
end
