# typed: true
# frozen_string_literal: true

module Codespaces
  class TransferPrebuildTemplateOwnerByRepositoryJob < CodespacesJob
    class Error < Codespaces::Error; end
    class TransferPrebuildTemplateOwnerError < Error; end

    retry_on_dirty_exit
    retry_on_recoverable_exceptions

    def perform(repository:)
      Codespaces::PrebuildTemplateBillingEntry.throttle_with_retry { Codespaces::TransferPrebuildTemplateOwnerByRepository.call(repository: repository) }
    end
  end
end
