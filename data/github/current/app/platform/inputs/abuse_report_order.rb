# typed: true
# frozen_string_literal: true

module Platform
  module Inputs
    class AbuseReportOrder < Platform::Inputs::Base

      description "Ordering options for abuse report connections."
      visibility :internal

      argument :field, Enums::AbuseReportOrderField, "The field to order abuse reports by.",
        required: true
      argument :direction, Enums::OrderDirection, "The ordering direction.", required: true
    end
  end
end
