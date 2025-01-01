# typed: true
# frozen_string_literal: true

require "test_helper"

class MediaTransitionTest < GitHub::TestCase
  include DogstatsTestHelpers
  include GitHub::LoggerHelper

  fixtures do
    @owner = create(:user)
    @repo1 = create :repository, owner: @owner
    @repo2 = create :repository, owner: @owner
  end

  test "accepts old repository network" do
    transition = Media::Transition.create!(transition_attrs.merge(old_repository_network: @repo2.network))
    transition = Media::Transition.find(T.must(transition.id))
    assert !transition.earlier_transition?
    assert_equal @repo1.network, transition.repository_network
    assert_equal @repo2.network, transition.old_repository_network
  end

  test "does not require old repository network" do
    transition = Media::Transition.create!(transition_attrs)
    transition = Media::Transition.find(T.must(transition.id))
    assert !transition.earlier_transition?
    assert_equal @repo1.network, transition.repository_network
    assert_nil transition.old_repository_network
  end

  test "finds earlier transition with matching network id" do
    transition1 = Media::Transition.create!(transition_attrs)
    transition2 = Media::Transition.create!(transition_attrs)
    refute transition1.earlier_transition?
    assert transition2.earlier_transition?
  end

  test "finds earlier transition with matching old network id" do
    transition1 = Media::Transition.create!(transition_attrs)
    transition2 = Media::Transition.create!(transition_attrs.merge(
      repository_network: @repo2.network,
      old_repository_network: @repo1.network,
    ))
    refute transition1.earlier_transition?
    assert transition2.earlier_transition?
  end

  test "requires repository network" do
    transition = Media::Transition.new(transition_attrs.merge(repository_network: nil))
    assert !transition.valid?
    assert transition.errors[:repository_network_id]
  end

  test "verifies destination repository network db existence for copies" do
    transition = Media::Transition.create!(
      old_repository_network: @repo1.network,
      repository_network_id: RepositoryNetwork.maximum(:id) + 100,
      operation: Media::Transition.operations["copying"],
      runs: 4,
    )
    transition.stubs(:each_network_batch).raises(NotImplementedError)

    assert_raises Media::Transition::MissingRepositoryNetworkError do
      transition.perform
    end
  end

  test "verifies destination repository network db existence for copies after many attempts" do
    transition = Media::Transition.create!(
      old_repository_network: @repo1.network,
      repository_network_id: RepositoryNetwork.maximum(:id) + 100,
      operation: Media::Transition.operations["copying"],
      runs: 5,
    )
    transition.stubs(:each_network_batch).raises(NotImplementedError)

    transition.perform

    assert transition.destroyed?
  end

  test "verifies repository network db existence for restores" do
    transition = Media::Transition.create!(
      repository_network_id: RepositoryNetwork.maximum(:id) + 100,
      operation: Media::Transition.operations["restoring"],
      runs: 4,
    )
    transition.stubs(:each_network_batch).raises(NotImplementedError)

    assert_raises Media::Transition::MissingRepositoryNetworkError do
      transition.perform
    end
  end

  test "verifies repository network db existence for restores after many attempts" do
    transition = Media::Transition.create!(
      repository_network_id: RepositoryNetwork.maximum(:id) + 100,
      operation: Media::Transition.operations["restoring"],
      runs: 5,
    )
    transition.stubs(:each_network_batch).raises(NotImplementedError)

    transition.perform

    assert transition.destroyed?
  end

  test "logs common and conditional transition data after completion" do
    transition = Media::Transition.create!(transition_attrs)

    expected_keys = {
      "code.namespace": "Media::Transition",
      "code.function": "copying",
      "gh.repo.network.id": @repo1.network.id,
      "gh.media.transition.id": transition.id,
      "gh.media.transition.runs": 0,
      "gh.media.transition.created_at": transition.created_at&.iso8601,
    }

    assert_logged(**expected_keys) do
      transition.perform
    end

    transition = Media::Transition.create!(transition_attrs.merge(
      repository_network_id: RepositoryNetwork.maximum(:id) + 100,
      old_repository_network: @repo2.network,
    ))

    assert_raises Media::Transition::MissingRepositoryNetworkError do
      transition.perform
    end

    transition.update!(repository_network_id: @repo1.network.id)
    transition.reload

    expected_keys.merge!(
      "gh.media.transition.id": transition.id,
      "gh.media.transition.old_repository_network.id": @repo2.network.id,
      "gh.media.transition.runs": 1,
      "gh.media.transition.created_at": transition.created_at&.iso8601,
      "gh.media.transition.run_at": transition.run_at&.iso8601,
    )

    assert_logged(**expected_keys) do
      transition.perform
    end
  end

  test "emits transition job wait time metric" do
    GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)

    transition = Media::Transition.create!(transition_attrs.merge(
      repository_network_id: RepositoryNetwork.maximum(:id) + 100,
    ))

    assert_raises Media::Transition::MissingRepositoryNetworkError do
      transition.perform
    end

    assert_dogstats_distribution 1, "lfs.transition_job.wait.dist.time", tags: ["op:copying"]
  end

  sig { returns(T::Hash[Symbol, T.untyped]) }
  def transition_attrs
    {
      repository_network: @repo1.network,
      operation: Media::Transition.operations["copying"],
    }
  end
end
