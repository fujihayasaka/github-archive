# typed: true
# frozen_string_literal: true

require "test_helper"

class RestorableVisibilityChangedRepositoryTest < GitHub::TestCase
  fixtures do
    @repo = create(:repository)
  end

  context ".ensure_started" do
    test "returns a new instance if no existing instance is found" do
      instance = assert_difference(-> { Restorable::VisibilityChangedRepository.count }, 1) do
        Restorable::VisibilityChangedRepository.ensure_started(@repo)
      end
      assert_predicate instance, :saving?
      refute_predicate instance, :restorable?
    end

    test "returns an existing saving? instance if one is already underway" do
      existing = Restorable::VisibilityChangedRepository.ensure_started(@repo)
      instance = assert_no_difference(-> { Restorable::VisibilityChangedRepository.count }) do
        Restorable::VisibilityChangedRepository.ensure_started(@repo)
      end
      assert_equal existing, instance
      assert_predicate instance, :saving?
      refute_predicate instance, :restorable?
    end
  end

  context ".continue" do
    test "returns an existing saving? instance if one is already underway" do
      original = Restorable::VisibilityChangedRepository.ensure_started(@repo)
      found = Restorable::VisibilityChangedRepository.continue(@repo)
      assert_equal original, found
      assert_predicate found, :saving?
      refute_predicate found, :restorable?
    end

    test "returns a null instance if no restoration is underway" do
      instance = Restorable::VisibilityChangedRepository.continue(@repo)
      refute_predicate instance, :saving?
      refute_predicate instance, :restorable?
    end
  end

  context ".save_stars" do
    test "creates restorable star records associated with the related restorable" do
      users = create_list(:user, 3)
      stars = users.map do |user|
        result = Stars.domain.star_repository(user: user, repository: @repo)
        case result
        when GH::Result::Ok
          result.value
        else
          flunk "Failed to create star: #{result}"
        end
      end

      restorable = Restorable::VisibilityChangedRepository.ensure_started(@repo)
      assert_predicate restorable, :saving?
      restorable = T.cast(restorable, Restorable::VisibilityChangedRepository)

      assert_empty T.must(restorable.restorable).repository_stars

      restorable.save_stars(stars)

      restorable_stars = T.must(restorable.restorable).reload.repository_stars
      assert_equal 3, restorable_stars.size
      assert_equal @repo.id, restorable_stars.map(&:repository_id).uniq.sole
      assert_same_elements users, restorable_stars.map(&:user)
      assert restorable_stars.map(&:original_created_at).none?(&:nil?)
    end
  end

  context ".save_stars_complete" do
    test "marks all restorable stars as saved" do
      vcr = T.cast(
        Restorable::VisibilityChangedRepository.ensure_started(@repo),
        Restorable::VisibilityChangedRepository
      )
      assert T.must(vcr.restorable).saving?([:restorable_repository_stars])
      refute T.must(vcr.restorable).saved?([:restorable_repository_stars])
      assert_predicate vcr, :saving?

      vcr.save_stars_complete

      refute T.must(vcr.restorable).saving?([:restorable_repository_stars])
      assert T.must(vcr.restorable).saved?([:restorable_repository_stars])
      # We're still saving because the other types haven't been marked saved yet.
      assert_predicate vcr, :saving?
    end
  end
end
