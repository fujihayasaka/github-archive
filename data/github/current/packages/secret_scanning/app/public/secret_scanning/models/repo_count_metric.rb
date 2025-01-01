# typed: strict
# frozen_string_literal: true

module SecretScanning
  module Models
    class RepoCountMetric
      extend T::Sig

      sig { returns(Integer) }
      attr_reader :count

      sig { returns(Integer) }
      attr_reader :repo_id

      sig { returns(T.nilable(String)) }
      attr_accessor :repo_name


      sig { params(count: Integer, repo_id: Integer, repo_name: T.nilable(String)).void }
      def initialize(count: 0, repo_id: 0, repo_name: nil)
        @count = count
        @repo_id = repo_id
        @repo_name = repo_name
      end

      sig { params(proto: GitHub::Proto::SecretScanning::Metrics::V1::RepoCount).returns(RepoCountMetric) }
      def self.from_proto(proto)
        RepoCountMetric.new(
          count: proto.count,
          repo_id: proto.repo_id
        )
      end
    end
  end
end
