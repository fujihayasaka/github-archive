# typed: true
# frozen_string_literal: true

require "test_helper"

class UserDashboardPinDomainTest < GitHub::TestCase
  include GitHub::DatabaseQueryWarningsTestHelpers

  def initialize(*args)
    @domain = T.let(Dashboard::Domain.new, Dashboard::Domain)
    super
  end

  fixtures do
    @user = create(:user)
    @repo = create(:repository, owner: @user)
  end

  setup do
    @domain = Dashboard::Domain.new
  end

  context "#repo_pinned_by_user" do
    test "finds true for pinned" do
      create(:user_dashboard_pin, pinned_item: @repo, user: @user)

      assert_no_query_warnings do
        assert @domain.repo_pinned_by_user(@repo.id, @user.id)
      end
    end

    test "returns false for non-pinned" do
      refute @domain.repo_pinned_by_user(@repo.id, @user.id)
    end
  end
end
