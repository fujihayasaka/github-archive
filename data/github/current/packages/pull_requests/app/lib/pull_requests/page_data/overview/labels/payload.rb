# typed: strict
# frozen_string_literal: true

module PullRequests::PageData::Overview::Labels
  class Payload
    class LabelPayload < T::Struct
      const :id, Integer
      const :name, String
      const :color, String
      const :description, T.nilable(String)
    end

    class LabelsPayload < T::Struct
      const :labels, T::Array[LabelPayload]
    end

    sig do
      params(
        labels_data: PullRequests::PageData::Overview::Labels::Loader::LabelsData,
      ).returns(LabelsPayload)
    end
    def self.call(labels_data)
      new(labels_data:).call
    end

    sig do
      params(
        labels_data: PullRequests::PageData::Overview::Labels::Loader::LabelsData,
      ).void
    end
    def initialize(labels_data:)
      @labels_data = labels_data
    end

    sig { returns(LabelsPayload) }
    def call
      LabelsPayload.new(
        labels: @labels_data.labels.map { |label| build_label(label) },
      )
    end

    private

    sig { params(label_data: Loader::LabelData).returns(LabelPayload) }
    def build_label(label_data)
      LabelPayload.new(
        id: label_data.id,
        name: label_data.name,
        color: label_data.color,
        description: label_data.description,
      )
    end
  end
end
