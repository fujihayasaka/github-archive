# typed: true
# frozen_string_literal: true

module OrgOverviewHelper
  def top_right_marketing_promos(context)
    current_user = context[:current_user]
    current_organization = context[:current_organization]
    request = context[:request]
    []
  end
end
