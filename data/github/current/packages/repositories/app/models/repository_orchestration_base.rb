# typed: true
# frozen_string_literal: true
module RepositoryOrchestrationBase
  extend ActiveSupport::Concern
  extend T::Helpers

  requires_ancestor { Orchestration }

  sig { returns(T.nilable(Repository)) }
  def repository; super; end

  included do
    T.bind(self, T.class_of(ApplicationRecord::Base))
    belongs_to :repository
    validates :repository_id, presence: true, unless: :skip_repository_id_validation
    validate :validate_no_duplicates, on: :create

    sig { params(block: T.proc.void).void }
    def infer_tenant(&block)
      infer_tenant_from_repo(&block)
    end

    sig { params(block: T.proc.void).void }
    def infer_tenant_from_repo(&block)
      return yield unless GitHub.multi_tenant_enterprise? && GitHub::CurrentTenant.get.blank? && repository.present?

      tenant = GitHub::CurrentTenant.unscope { Business.find_by(id: T.must(repository).tenant_id) }

      GitHub::CurrentTenant.set(tenant) { yield }
    end
  end

  sig { returns(T::Boolean) }
  def skip_repository_id_validation
    false
  end
end
