# typed: true
# frozen_string_literal: true

# Replaces GraphQL::Pro::OperationStore::Endpoint's HMAC authentication as the sync endpoint we are implementing
# uses our own HMAC verification middleware that reads from the 'Request-HMAC' header
GraphQL::Pro::OperationStore::Endpoint.class_eval do

  def authenticated_request?(header_value, body_string)

    # Check that the header has the expected parts
    prelude, client_name, provided_hmac = header_value.split(" ")

    if prelude.nil? || client_name.nil? || provided_hmac.nil?
      # The header is not the expected format; definitely invalid.
      [false, "Invalid header format"]
    end

    # TODO investigate caching clients from the DB
    # Since the client is autheticated already, we need to ensure we have a client in the database.
    @operation_store.upsert_client(client_name, provided_hmac)

    [true, client_name]

  end
end
