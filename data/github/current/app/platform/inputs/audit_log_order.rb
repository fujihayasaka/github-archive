# typed: true
# frozen_string_literal: true

module Platform
  module Inputs
    class AuditLogOrder < Platform::Inputs::Base

      description "Ordering options for Audit Log connections."

      argument :field, Enums::AuditLogOrderField, "The field to order Audit Logs by.", required: false
      argument :direction, Enums::OrderDirection, "The ordering direction.", required: false
    end
  end
end
