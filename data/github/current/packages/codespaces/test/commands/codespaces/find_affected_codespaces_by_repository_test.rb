# typed: true
# frozen_string_literal: true

require "test_helper"

class Codespaces::FindAffectedCodespacesByRepositoryTest < GitHub::TestCase
  fixtures do
    @repository = create(:repository)
    @codespace = create(:codespace, repository: @repository)
  end

  context "#call" do
    test "loads multiple in relation" do
      same_repository = create(:codespace, repository: @repository)
      expected = Codespace.where(repository: @codespace.repository_id)
      assert_equal expected.count, 2
      expected.in_batches do |codespace_batch|
        CodespacesProcessSystemEventJob.expects(:perform_later).with(codespaces: codespace_batch, deletion_reason: Codespace.deletion_reasons[:repository_made_private])
      end
      Codespaces::FindAffectedCodespacesByRepository.new(repository_id: @codespace.repository_id, deletion_reason: Codespace.deletion_reasons[:repository_made_private]).call
    end

    test "doesn't do anything when repository can't be found" do
      CodespacesProcessSystemEventJob.expects(:perform_later).never
      Codespaces::FindAffectedCodespacesByRepository.new(repository_id: -1, deletion_reason: Codespace.deletion_reasons[:repository_made_private]).call
    end
  end
end
