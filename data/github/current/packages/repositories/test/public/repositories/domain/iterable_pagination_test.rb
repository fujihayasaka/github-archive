# typed: true
# frozen_string_literal: true

require "test_helper"

class IterablePaginationRepositoriesDomainTest < GitHub::TestCase
  fixtures do
    @user = create(:user)
    @other_user = create(:user)

    @repo = create(:repository, owner: @user)
    @repo.redirect_from_previous_location("#{@other_user.login}/old-repo")
  end

  context "#by_org_excluding" do
    test "cursor pagination" do
      user = create(:user)
      organization = create(:organization, admin: user)
      3.times { create(:repository, owner: organization) }
      expected_repos = organization.repositories.order(:id).to_a

      pagination = GH::Pagination::Cursor.new(first: 1, disable_auth: true)
      collection = T.cast(
        Repositories.domain.by_org_excluding(
          organization_id: organization.id,
          excluded_repo_ids: [],
          pagination:,
          max_pages: 3
          ),
        GH::Domain::CursorCollection[Repositories::IRepository]
      )

      page_count = 0
      last_page = T.let(nil, T.nilable(GH::Domain::Collection[Repositories::IRepository]))

      collection.each_page do |page|
        expected_repo_id = expected_repos.map(&:id).drop(page_count).first
        this_page_repo_id = page.map(&:id).first

        assert_equal expected_repo_id, this_page_repo_id
        refute_equal last_page&.map(&:id)&.first, expected_repo_id

        page_count += 1
        last_page = page
      end

      assert_equal 3, page_count
    end

    test "offset pagination" do
      user = create(:user)
      organization = create(:organization, admin: user)
      3.times { create(:repository, owner: organization) }
      expected_repos = organization.repositories.order(:id).to_a

      pagination = GH::Pagination::Offset.new(page: 1, per_page: 1)
      collection = T.cast(
        Repositories.domain.by_org_excluding(
          organization_id: organization.id,
          excluded_repo_ids: [],
          pagination:,
          max_pages: 3
          ),
        GH::Domain::OffsetCollection[Repositories::IRepository]
      )

      page_count = 0
      last_page = T.let(nil, T.nilable(GH::Domain::Collection[Repositories::IRepository]))

      collection.each_page do |page|
        expected_repo_id = expected_repos.map(&:id).drop(page_count).first
        this_page_repo_id = page.map(&:id).first

        assert_equal expected_repo_id, this_page_repo_id
        refute_equal last_page&.map(&:id)&.first, expected_repo_id

        page_count += 1
        last_page = page
      end

      assert_equal 3, page_count
    end
  end
end
