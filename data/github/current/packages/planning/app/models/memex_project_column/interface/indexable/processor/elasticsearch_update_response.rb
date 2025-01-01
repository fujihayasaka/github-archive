# typed: strict
# frozen_string_literal: true

module MemexProjectColumn::Interface::Indexable::Processor
  # A wrapper for the response from the Elasticsearch update API.
  class ElasticsearchUpdateResponse

    UpdateResponseData = T.type_alias do
      T.any(
        Base::NilableGenericHash,
        T::Array[Base::NilableGenericHash],
      )
    end
    ResponseSummary = T.type_alias { Base::GenericHash }

    sig { returns(ResponseSummary) }
    attr_reader :data

    sig { params(data: UpdateResponseData).void }
    def initialize(data:)
      @data = T.let(summarize(data:), ResponseSummary)
    end

    # The data coming in may be a hash or an array of hashes. This method masks
    # that detail and returns a hash of the summary data.
    #
    # At present we don't differentiate between the data in each hash
    # specifically so the summarize method is just an aggregation of what gets
    # passed in.
    sig { params(data: UpdateResponseData).returns(ResponseSummary) }
    private def summarize(data:)
      Array.wrap(data).reduce({}) do |acc, response|
        acc["_raw"] = acc["_raw"].to_a + [response]
        acc["version_conflicts"] = acc["version_conflicts"].to_i + response["version_conflicts"].to_i if response["version_conflicts"]
        acc["updated"] = acc["updated"].to_i + response["updated"].to_i if response["updated"]
        acc["total"] = acc["total"].to_i + response["total"].to_i if response["total"]
        acc["noops"] = acc["noops"].to_i + response["noops"].to_i if response["noops"]
        acc["result"] = response["result"] if response["result"] # Possible future bug here. Last one wins. If you need these data consider moving this to a collection of values
        acc["_version"] = response["_version"] if response["_version"] # Possible future bug here. Last one wins. If you need these data consider moving this to a collection of values
        acc["failures"] = response["failures"] if response["failures"]
        acc["errors"] = response["errors"] if response["errors"]

        acc
      end.with_indifferent_access
    end
  end
end
