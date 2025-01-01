# typed: true
# frozen_string_literal: true

require "test_helper"
require_relative "../domain_test"

class Repositories::Domain::RecentByOwnerAndTypeForActorTest < GitHub::TestCase
  fixtures do
    @user = create(:user)
    @another_user = create(:user)
    @repo_ids = (0..2).map do |_|
      create(:repository, owner: @user).id
    end
    @private_repo = create(:private_repository, owner: @user)
    @private_collab_repo = create(:private_repository, owner: @user)
    @private_collab_repo.add_member(@another_user)

    current_time = Time.current
    Timecop.freeze(current_time) do
      Repository.where(id: (@repo_ids + [@private_repo.id, @private_collab_repo.id])).order(:id).each_with_index do |repository, index|
        repository.update(pushed_at: current_time - index.minutes)
      end
    end
  end

  context "#by_owner_and_type_for_actor" do
    test "owner is actor" do
      domain = Repositories::Domain.new(:test, actor: @user)
      repos = domain.recent_by_owner_for_actor(owner_id: @user.id)

      assert_equal @user.repositories.order(pushed_at: :desc).pluck(:id), repos.map(&:id)
    end

    test "owner is not actor, actor is another user" do
      domain = Repositories::Domain.new(:test, actor: @another_user)
      repos = domain.recent_by_owner_for_actor(owner_id: @user.id)

      assert_equal @user.repositories.where.not(id: @private_repo.id).order(pushed_at: :desc).pluck(:id), repos.map(&:id)
    end

    test "owner is not actor, actor is anonymous" do
      domain = Repositories::Domain.new(:test, actor: nil)
      repos = domain.recent_by_owner_for_actor(owner_id: @user.id)

      assert_equal @user.public_repositories.order(pushed_at: :desc).pluck(:id), repos.map(&:id)

    end
  end
end
