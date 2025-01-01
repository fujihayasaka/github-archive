# typed: true
# frozen_string_literal: true

module Repositories
  module Cache
    class InvalidateOn < T::Enum
      enums do
        ApiMutation = new("api_mutation")
        Delete = new("delete")
        Extract = new("extract_fork")
        GraphqlMutation = new("graphql_mutation")
        Push = new("push")
        Rename = new("rename")
        Restore = new("restore")
        Transfer = new("transfer")
        Visibility = new("visibility")
        WebMutation = new("web_mutation")
      end
    end
  end
end
