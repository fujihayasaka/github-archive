# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class TeamChangeParentRequestDirection < Platform::Enums::Base
      description "Direction of the team change request"
      visibility :internal

      value "INBOUND_PARENT_INITIATED", "Parent-initiated requests to be approved by a maintainer of this team", value: "inbound_parent_initiated"
      value "OUTBOUND_PARENT_INITIATED", "Parent-initiated requests originated from this team", value: "outbound_parent_initiated"
      value "INBOUND_CHILD_INITIATED", "Child-initiated requests to be approved by a maintainer of this team", value: "inbound_child_initiated"
      value "OUTBOUND_CHILD_INITIATED", "Child-initiated requests originated from this team", value: "outbound_child_initiated"
      value "ALL", "All requests", value: "all"
    end
  end
end
