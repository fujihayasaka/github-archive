# typed: strict
# frozen_string_literal: true

module GH
  module Dev
    class CodeStats
      class Base
        extend T::Helpers

        abstract!

        sig { params(report: ::CodeStats::Report, serviceowners: Serviceowners::Main).void }
        def initialize(report, serviceowners)
          @report = report
          @serviceowners = serviceowners
        end

        sig { returns(::CodeStats::Report) }
        attr_reader :report

        sig { returns(Serviceowners::Main) }
        attr_reader :serviceowners

        sig { abstract.void }
        def report_data!; end
      end
    end
  end
end
