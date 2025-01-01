# typed: true
# frozen_string_literal: true

require "test_helper"

module Codespaces
  class TransferPrebuildTemplateOwnerByRepositoryTest < GitHub::TestCase
    include CodespacesPlanFixtures

    test "it calls TransferPrebuildTemplateBillableOwner for each prebuild template guid on the repo" do
      repo = create(:repository)
      template1 = create(:codespace_prebuild_template, repository: repo, guid: SecureRandom.uuid)
      template2 = create(:codespace_prebuild_template, repository: repo, guid: SecureRandom.uuid)

      random_template = create(:codespace_prebuild_template, guid: SecureRandom.uuid)

      Codespaces::TransferPrebuildTemplateBillableOwner.expects(:call).with(template1.guid).once
      Codespaces::TransferPrebuildTemplateBillableOwner.expects(:call).with(template2.guid).once
      Codespaces::TransferPrebuildTemplateBillableOwner.expects(:call).with(random_template.guid).never

      Codespaces::TransferPrebuildTemplateOwnerByRepository.call(repository: repo)
    end
  end
end
