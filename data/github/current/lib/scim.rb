# typed: true
# frozen_string_literal: true

module SCIM
  autoload :ErrorResponse, "scim/error_response"
  autoload :Filter, "scim/filter"
  autoload :Operation, "scim/operation"
  autoload :ResultsCollection, "scim/results_collection"

  CONTENT_TYPE = "application/scim+json"

  ERROR_SCHEMA = "urn:ietf:params:scim:api:messages:2.0:Error"
  LIST_SCHEMA = "urn:ietf:params:scim:api:messages:2.0:ListResponse"
  USER_SCHEMA = "urn:ietf:params:scim:schemas:core:2.0:User"
  GROUP_SCHEMA = "urn:ietf:params:scim:schemas:core:2.0:Group"
end
