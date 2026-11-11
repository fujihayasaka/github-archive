# typed: true
# frozen_string_literal: true

module Platform
  module Loaders
    class CompareRepository < Platform::Loader
      def self.load(repository, head_repository: nil, base_repository: nil)
        self.for(repository).load([head_repository, base_repository])
      end

      def initialize(repository)
        @repository = repository
      end

      def fetch(head_and_base_repository_pairs)
        if @repository.advisory_workspace?
          return head_and_base_repository_pairs.map { |pair| [pair, @repository] }.to_h
        end

        # TODO: Shouldn't all these repositories here belong to the same network?
        Promise.all(head_and_base_repository_pairs.flatten.compact.map(&:async_network)).sync

        compare_repo = Repositories::Public.find_active!(@repository.id)
        head_and_base_repository_pairs.map do |head_and_base_repository_pair|
          GitHub::PrefillAssociations.prefill_associations(compare_repo, :network, available_records: [@repository.network])

          alternates = head_and_base_repository_pair.compact
          compare_repo.extend_rpc_alternates(*alternates) unless alternates.empty?

          [head_and_base_repository_pair, compare_repo]
        end.to_h
      end
    end
  end
end
