# typed: strict
# frozen_string_literal: true

require "pull_requests/v1/labels_pb"

module PullRequests::PageData::Overview::Labels
  # Builds the protobuf LabelsResponse from the same Loader::LabelsData that
  # Payload consumes, mirroring Payload's per-field transforms. This keeps the
  # proto branch a pure re-encoding of the exact same data the legacy JSON
  # renders.
  #
  # The legacy `description` is nilable; proto3 omits empty strings, so a nil or
  # empty description serializes as an absent field (the consumer reads it back
  # as "").
  class ProtoPayload
    sig do
      params(
        labels_data: Loader::LabelsData,
      ).returns(Github::PullRequests::V1::LabelsResponse)
    end
    def self.call(labels_data)
      new(labels_data:).call
    end

    sig { params(labels_data: Loader::LabelsData).void }
    def initialize(labels_data:)
      @labels_data = T.let(labels_data, Loader::LabelsData)
    end

    sig { returns(Github::PullRequests::V1::LabelsResponse) }
    def call
      Github::PullRequests::V1::LabelsResponse.new(
        labels: @labels_data.labels.map { |label| build_label(label) },
      )
    end

    private

    sig { params(data: Loader::LabelData).returns(Github::PullRequests::V1::PullRequestLabel) }
    def build_label(data)
      Github::PullRequests::V1::PullRequestLabel.new(
        id: data.id,
        name: data.name,
        color: data.color,
        description: data.description || "",
      )
    end
  end
end
