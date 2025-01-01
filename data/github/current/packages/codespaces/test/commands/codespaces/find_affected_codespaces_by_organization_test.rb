# typed: true
# frozen_string_literal: true

require "test_helper"

class Codespaces::FindAffectedCodespacesByOrganizationTest < GitHub::TestCase
  fixtures do
    @organization = create(:organization)
    @repository = create(:repository, owner: @organization)
    @codespace = create(:codespace, repository: @repository, billable_owner: @organization)
  end

  context "#call" do
    test "handles enabling codespaces with multiple codespaces on a repo" do
      @second_codespace = create(:codespace, repository: @repository)
      assert @codespace.repository_id, @second_codespace.repository_id

      @other_repository = create(:repository, owner: @organization)
      @other_codespace = create(:codespace, repository: @other_repository)

      expected = Codespace.where(repository: [@repository.id, @other_repository.id])
      expected.in_batches do |codespace_batch|
        CodespacesProcessSystemEventJob.expects(:perform_later).with(codespaces: codespace_batch.to_a, deletion_reason: nil)
      end
      Codespaces::FindAffectedCodespacesByOrganization.new(organization_id: @organization.id).call
    end


    test "handles disabling codespaces with multiple codespaces on a repo" do
      @second_codespace = create(:codespace, repository: @repository, billable_owner: @organization)
      assert @codespace.repository_id, @second_codespace.repository_id

      @other_repository = create(:repository, owner: @organization)
      @other_codespace = create(:codespace, repository: @other_repository, billable_owner: @organization)

      expected = Codespace.for_organization(@organization)
      expected.in_batches do |codespace_batch|
        CodespacesProcessSystemEventJob.expects(:perform_later).with(codespaces: codespace_batch.to_a, deletion_reason: nil)
      end
      Codespaces::FindAffectedCodespacesByOrganization.new(organization_id: @organization.id, disabled: true).call
    end
  end
end unless GitHub.enterprise?
