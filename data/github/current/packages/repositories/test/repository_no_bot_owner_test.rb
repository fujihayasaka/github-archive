# typed: strict
# frozen_string_literal: true

require "test_helper"

require "test_helpers/dgit"

unless GitHub.single_business_environment?
  class RepositoryNoBotOwnerTest < GitHub::TestCase
    test "cannot create a repo with a bot owner" do
      bot = create(:bot)
      repository = build(:repository, owner: bot)

      repository.valid?

      assert repository.invalid?
      assert_equal ["Owner must be a User or Organization"], repository.errors.full_messages
    end

    test "cannot transfer a repo to a bot owner" do
      bot = create(:bot)
      repository = create(:repository)

      assert_raises Repository::TransferDependency::TransferFailedError do
        repository.transfer_ownership_to(bot, actor: repository.owner)
      end
    end

    test "cannot fork a repo to a bot owner" do
      bot = create(:bot)
      repository = create(:repository)

      bot_fork, error = repository.fork(forker: bot)

      refute bot_fork
      assert_equal :invalid, error
    end
  end
end
