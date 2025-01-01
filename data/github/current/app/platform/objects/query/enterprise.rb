# typed: true
# frozen_string_literal: true

module Platform::Objects::Query::Enterprise
  extend T::Helpers
  extend ActiveSupport::Concern
  include ::Platform
  include ::GraphQL::Schema::Member::GraphQLTypeNames

  requires_ancestor { Platform::Objects::Query }

  included do
    T.bind(self, T.class_of(Platform::Objects::Query))

    field :enterprise_support_contact, Objects::SupportContact, description: "The support contact for this enterprise", mobile_only: true, null: true

    def enterprise_support_contact
      { 'link': GitHub.support_link, 'link_type': GitHub.support_link_type }
    end

    field :enterprise, Objects::Enterprise, description: "Look up an enterprise by URL slug.", null: true do
      argument :slug, String, "The enterprise URL slug.", required: true
      argument :invitation_token, String, "The enterprise invitation token.", required: false
    end

    def enterprise(**arguments)
      Loaders::ActiveRecord.load(::Business, arguments[:slug], column: :slug, case_sensitive: false).then do |business|
        unless business
          raise Platform::Errors::NotFound, "Could not resolve to a Business with the URL slug of '#{arguments[:slug]}'."
        end

        Models::Enterprise.new(business, ::BusinessAdministratorInvitation.digest_token(arguments[:invitation_token]))
      end
    end

    field :enterprise_administrator_invitation, Objects::EnterpriseAdministratorInvitation,
      visibility: { public: { environments: [:dotcom] }, internal: { environments: [:enterprise] } },
      description: "Look up a pending enterprise administrator invitation by invitee, enterprise and role.", null: true do
      argument :user_login, String, "The login of the user invited to join the business.", required: true
      argument :enterprise_slug, String, "The slug of the enterprise the user was invited to join.", required: true
      argument :role, Enums::EnterpriseAdministratorRole, "The role for the business member invitation.", required: true
    end

    def enterprise_administrator_invitation(**arguments)
      Promise.all([
        Loaders::ActiveRecord.load(::Business, arguments[:enterprise_slug], column: :slug, case_sensitive: false),
        Loaders::ActiveRecord.load(::User, arguments[:user_login], column: :login, case_sensitive: false),
      ]).then do |business, user|
        if business.nil?
          raise Platform::Errors::NotFound, "Could not resolve to an enterprise with the URL slug of '#{arguments[:enterprise_slug]}'"
        elsif user.nil?
          raise Platform::Errors::NotFound, "Could not resolve to a user with the login '#{arguments[:user_login]}'"
        end

        invitation = ::BusinessAdministratorInvitation.pending.find_by(role: arguments[:role], business: business, invitee: user)
        if invitation.nil?
          raise Platform::Errors::NotFound, "Could not resolve to a pending invitation for #{user.display_login} to join #{business.name} in the #{arguments[:role]} role."
        end

        invitation
      end
    end

    field :enterprise_administrator_invitation_by_token, Objects::EnterpriseAdministratorInvitation,
      visibility: { public: { environments: [:dotcom] }, internal: { environments: [:enterprise] } },
      description: "Look up a pending enterprise administrator invitation by invitation token.", null: true do
      argument :invitation_token, String, "The invitation token sent with the invitation email.", required: true
    end

    def enterprise_administrator_invitation_by_token(**arguments)
      hashed_token = ::BusinessAdministratorInvitation.digest_token(arguments[:invitation_token])
      Loaders::ActiveRecord.load(::BusinessAdministratorInvitation, hashed_token, column: :hashed_token, case_sensitive: true).then do |invitation|
        if invitation.nil? || !invitation.pending?
          raise Platform::Errors::NotFound, "Could not resolve to a pending invitation for token #{arguments[:invitation_token]}."
        end

        invitation
      end
    end

    field :enterprise_member_invitation, Objects::EnterpriseMemberInvitation,
      visibility: { public: { environments: [:dotcom] }, internal: { environments: [:enterprise] } },
      description: "Look up a pending enterprise unaffiliated member invitation by invitee and enterprise.", null: true do
      argument :user_login, String, "The login of the user invited to join the business.", required: true
      argument :enterprise_slug, String, "The slug of the enterprise the user was invited to join.", required: true
    end

    def enterprise_member_invitation(**arguments)
      Promise.all([
        Loaders::ActiveRecord.load(::Business, arguments[:enterprise_slug], column: :slug, case_sensitive: false),
        Loaders::ActiveRecord.load(::User, arguments[:user_login], column: :login, case_sensitive: false),
      ]).then do |business, user|
        raise Platform::Errors::Unprocessable.new("Invalid user login: #{arguments[:user_login]}") if arguments[:user_login].present? && arguments[:user_login].include?("_")
        if business.nil?
          raise Platform::Errors::NotFound, "Could not resolve to an enterprise with the URL slug of '#{arguments[:enterprise_slug]}'"
        elsif user.nil?
          raise Platform::Errors::NotFound, "Could not resolve to a user with the login '#{arguments[:user_login]}'"
        end

        invitation = ::BusinessMemberInvitation.pending.find_by(role: :unaffiliated, business: business, invitee: user)
        if invitation.nil?
          raise Platform::Errors::NotFound, "Could not resolve to a pending unaffiliated member invitation for #{user.display_login} to join #{business.name}."
        end

        invitation
      end
    end

    field :enterprise_member_invitation_by_token, Objects::EnterpriseMemberInvitation,
      visibility: { public: { environments: [:dotcom] }, internal: { environments: [:enterprise] } },
      description: "Look up a pending enterprise unaffiliated member invitation by invitation token.", null: true do
      argument :invitation_token, String, "The invitation token sent with the invitation email.", required: true
    end

    def enterprise_member_invitation_by_token(**arguments)
      hashed_token = ::BusinessAdministratorInvitation.digest_token(arguments[:invitation_token])
      Loaders::ActiveRecord.load(::BusinessAdministratorInvitation, hashed_token, column: :hashed_token, case_sensitive: true).then do |invitation|
        if invitation.nil? || !invitation.pending? || !invitation.unaffiliated?
          raise Platform::Errors::NotFound, "Could not resolve to a pending invitation for token #{arguments[:invitation_token]}."
        end

        invitation
      end
    end
  end
end
