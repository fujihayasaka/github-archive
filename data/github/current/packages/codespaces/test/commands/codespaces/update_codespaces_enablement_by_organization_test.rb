# typed: true
# frozen_string_literal: true

require "test_helper"

class Codespaces::UpdateCodespacesEnablementByOrganizationTest < GitHub::TestCase
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
        CodespacesProcessSystemEventJob.expects(:perform_later).with(codespaces: codespace_batch.sort)
      end
      Codespaces::UpdateCodespacesEnablementByOrganization.new(organization_id: @organization.id).call
    end


    test "handles disabling codespaces with multiple codespaces on a repo" do
      @second_codespace = create(:codespace, repository: @repository, billable_owner: @organization)
      assert @codespace.repository_id, @second_codespace.repository_id

      @other_repository = create(:repository, owner: @organization)
      @other_codespace = create(:codespace, repository: @other_repository, billable_owner: @organization)

      expected = Codespace.for_organization(@organization)
      expected.in_batches do |codespace_batch|
        CodespacesProcessSystemEventJob.expects(:perform_later).with(codespaces: codespace_batch.sort)
      end
      Codespaces::UpdateCodespacesEnablementByOrganization.new(organization_id: @organization.id, disabled: true).call
    end

    test "Ignores billable owner" do
      repo = create(:private_repository, owner: @organization)
      other_user = create(:user)
      repo.add_member(other_user, action: :admin)
      second_codespace = create(:codespace, repository: repo)
      second_codespace.update(owner: other_user, billable_owner: other_user)

      @other_repository = create(:repository, owner: @organization)
      @other_codespace = create(:codespace, repository: @other_repository, billable_owner: @organization)

      expected = Codespace.where(id: [@codespace.id, second_codespace.id, @other_codespace.id])

      expected.in_batches do |codespace_batch|
        CodespacesProcessSystemEventJob.expects(:perform_later).with(codespaces: codespace_batch.sort)
      end
      Codespaces::UpdateCodespacesEnablementByOrganization.new(
        organization_id: @organization.id,
        disabled: true,
      ).call
    end
  end
end unless GitHub.enterprise?
