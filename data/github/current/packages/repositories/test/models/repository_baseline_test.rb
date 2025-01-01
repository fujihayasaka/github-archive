# typed: strict
# frozen_string_literal: true

require "test_helper"

require "test_helpers/dgit"

class RepositoryBaselineTest < GitHub::TestCase
  test "is :write for public repo" do
    repo = Repository.new public: true
    assert_equal :write, repo.baseline
  end

  test "is :read for a private repo" do
    repo = Repository.new public: false
    assert_equal :read, repo.baseline
  end
end
