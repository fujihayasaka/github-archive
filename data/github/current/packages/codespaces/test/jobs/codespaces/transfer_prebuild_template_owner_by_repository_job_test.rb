# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

class TransferPrebuildTemplateOwnerByRepositoryJobTest < GitHub::TestCase


  test "calls TransferPrebuildTemplateOwnerByRepository" do
    repository = create(:repository)

    Codespaces::TransferPrebuildTemplateOwnerByRepository.expects(:call).with(repository: repository).once

    Codespaces::TransferPrebuildTemplateOwnerByRepositoryJob.perform_now(repository: repository)
  end

end
