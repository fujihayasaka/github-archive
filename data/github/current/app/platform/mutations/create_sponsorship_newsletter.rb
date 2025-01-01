# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class CreateSponsorshipNewsletter < Platform::Mutations::Base
      description "Post an update to your sponsors."

      def self.async_api_can_modify?(permission, **inputs)
        sponsorable_promise = if inputs[:sponsorable_login]
          Loaders::ActiveRecord.load(::User, inputs[:sponsorable_login], column: :login)
        else
          Promise.resolve(permission.viewer)
        end
        sponsorable_promise.then do |sponsorable|
          permission.access_allowed?(:admin_sponsors_listing,
            resource: sponsorable,
            current_org: sponsorable.organization? ? sponsorable : nil,
            current_repo: nil,
            allow_integrations: false,
            allow_user_via_granular_actor: false,
          )
        end
      end

      visibility :under_development, environments: [:dotcom]
      visibility :internal, environments: [:enterprise]

      minimum_accepted_scopes ["user", "admin:org"]

      argument :subject, String, "The subject line of the message.", required: true
      argument :body, String, "The message to deliver to sponsors. Markdown is supported, see " \
        "#{GitHub.markdown_docs_url}, but keep in mind the content will be sent as an HTML email, so not all " \
        "formatting will be supported by all email clients.", required: true
      argument :sponsorable_login, String, "The username of the user or organization whose sponsors should receive " \
        "the newsletter. If omitted, will default to the sponsors of the authenticated user.", required: false
      argument :tier_ids, [ID], "Specify which sponsors should receive the update by targeting those sponsoring at " \
        "specific tiers. If omitted, all your current sponsors will get the update.", required: false,
        default_value: [], loads: Objects::SponsorsTier
      argument :publish, Boolean, "Whether to send the update immediately to sponsors. Defaults " \
        "to saving a draft that will not be sent until it is published.", required: false, default_value: false

      field :sponsorship_newsletter, Objects::SponsorshipNewsletter, "The update that was posted.", null: true

      def resolve(subject:, body:, sponsorable_login: nil, tiers: [], publish: false)
        viewer = context[:viewer]
        sponsorable_promise = if sponsorable_login
          Loaders::ActiveRecord.load(::User, sponsorable_login, column: :login)
        else
          Promise.resolve(viewer)
        end

        sponsorable_promise.then do |sponsorable|
          begin
            newsletter = Sponsors::CreateSponsorshipNewsletter.call(
              sponsorable: sponsorable,
              author: viewer,
              draft: !publish,
              body: body.presence,
              subject: subject.presence,
              tier_ids: tiers.map(&:id),
            )
            { sponsorship_newsletter: newsletter }
          rescue Sponsors::CreateSponsorshipNewsletter::UnprocessableError => err
            raise Errors::Unprocessable.new(err.message)
          rescue Sponsors::CreateSponsorshipNewsletter::ForbiddenError => err
            raise Errors::Forbidden.new(err.message)
          end
        end
      end
    end
  end
end
