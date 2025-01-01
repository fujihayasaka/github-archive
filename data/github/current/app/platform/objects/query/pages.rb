# typed: false # rubocop:disable Sorbet/TrueSigil
# frozen_string_literal: true

module Platform::Objects::Query::Pages
  extend ActiveSupport::Concern
  include ::Platform
  include ::GraphQL::Schema::Member::GraphQLTypeNames

  included do
    field :page_certificate, Objects::PageCertificate, description: "Fetch a page certificate by domain", null: false, visibility: :internal do
      argument :domain, String, "The domain of the page certificate", required: true
    end

    def page_certificate(**arguments)
      Loaders::ActiveRecord.load(::Page::Certificate, arguments[:domain], column: :domain).then do |certificate|
        unless certificate
          raise Platform::Errors::NotFound, "Could not find a page certificate with domain #{arguments[:domain]}"
        end

        certificate
      end
    end
  end
end
