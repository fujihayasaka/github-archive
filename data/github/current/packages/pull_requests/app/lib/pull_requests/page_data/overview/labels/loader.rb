# typed: strict
# frozen_string_literal: true

module PullRequests::PageData::Overview::Labels
  class Loader
    include GitHub::ResilienceMixin

    sig { returns(PullRequest) }
    attr_reader :pull_request

    class LabelData < T::Struct
      const :id, Integer
      const :name, String
      const :color, String
      const :description, T.nilable(String)
    end

    class LabelsData < T::Struct
      const :labels, T::Array[LabelData]
    end

    sig { params(pull_request: PullRequest).returns(LabelsData) }
    def self.load(pull_request:)
      new(pull_request:).load
    end

    sig { params(pull_request: PullRequest).void }
    def initialize(pull_request:)
      @pull_request = pull_request
    end

    sig { returns(LabelsData) }
    def load
      issue = @pull_request.issue
      raise ArgumentError, "Pull request issue is missing" if issue.nil?

      repository = @pull_request.repository
      raise ArgumentError, "Pull request repository is missing" if repository.nil?

      labels = issue.labels.to_a

      LabelsData.new(
        labels: labels.map do |label|
          LabelData.new(
            id: label.id,
            name: label.name,
            color: label.color,
            description: label.description,
          )
        end,
      )
    end
  end
end
