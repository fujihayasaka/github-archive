# typed: strict
# frozen_string_literal: true

module GitHub
  module Billing
    # Public: Utility class to search for disputes using Braintree's disputes
    # API and write the results to a file. This helps to get around limitations
    # in the disputes reporting available through Braintree's control panel
    #
    # Examples
    #
    #   fd = File.open("disputes.csv", "w")
    #   GitHub::Billing::DisputeSearch.run(out: fd) do |search|
    #     search.received_date.between Date.new(2017, 1, 1), Date.new(2017, 12, 31)
    #   end
    #   fd.close
    class DisputeSearch
      extend T::Sig

      # Public: Run a dispute search and write the results to a file
      #
      # out   - An IO where dispute search results will be written
      # block - A block which provides criteria for the Braintree dispute search;
      #         See https://developers.braintreepayments.com/reference/request/dispute/search/ruby
      #         for more information
      sig { params(out: T.any(IO, StringIO), block: T.proc.params(search: Braintree::DisputeSearch).void).void }
      def self.run(out:, &block)
        new(out: out).run(&block)
      end

      # Public: Initializes a new DisputeSearch
      #
      sig { params(out: T.any(IO, StringIO)).void }
      def initialize(out:)
        @out = out
      end

      # Public: Runs a dispute search and write the results to the desired
      # output file as a CSV
      #
      # block - A block which proivdes critera for the Braintree dispute search
      sig { params(block: T.proc.params(search: Braintree::DisputeSearch).void).void }
      def run(&block)
        result = Braintree::Dispute.search(&block)

        @out.puts(CSV.generate_line([
          "Dispute ID",
          "Transaction ID",
          "Reason",
          "Status",
          "Received Date",
          "Amount Disputed",
        ]))

        result.disputes.each do |dispute|
          @out.puts(CSV.generate_line([
            dispute.id,
            dispute.transaction.id,
            dispute.reason,
            dispute.status,
            dispute.received_date,
            dispute.amount_disputed,
          ]))
        end
      end
    end
  end
end
