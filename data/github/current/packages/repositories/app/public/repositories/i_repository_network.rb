# typed: strict
# frozen_string_literal: true

module Repositories
  module IRepositoryNetwork
    extend T::Helpers

    include Kernel
    include FeatureFlag::IFeatureTarget

    requires_ancestor { Object }

    abstract!

    sig { abstract.returns(T.nilable(Integer)) }
    def id; end

    sig { abstract.returns(T.nilable(IRepository)) }
    def root; end

    sig { abstract.returns(Integer) }
    def root_id; end

    sig { abstract.returns(Integer) }
    def cache_version_number; end

    sig { abstract.returns(T::Boolean) }
    def moving?; end

    sig { abstract.returns(String) }
    def maintenance_queue_name; end

    sig { abstract.returns(String) }
    def storage_path; end

    sig { abstract.returns(T::Boolean) }
    def broken?; end

    sig { abstract.returns(T::Boolean) }
    def read_only?; end

    sig { abstract.returns(String) }
    def shared_storage_path; end

    sig { abstract.returns(T::Boolean) }
    def shared_storage_enabled?; end
  end
end
