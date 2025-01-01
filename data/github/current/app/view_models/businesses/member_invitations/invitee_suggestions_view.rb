# typed: true
# rubocop:disable Primer/PrimerOcticon
# frozen_string_literal: true

module Businesses::MemberInvitations
  class InviteeSuggestionsView < AutocompleteView
    def suggested_invitees
      suggestions.map do |user|
        [user, SuggestedInvitee.new(business, user, current_user)]
      end
    end

    def email_match?(user)
      email_query? && user.profile.email == query
    end

    class SuggestedInvitee
      include OcticonsHelper

      def initialize(business, user, inviter)
        @invited = business.pending_admin_invitation_for(user).present?
        @member = business.business_user_account_for(user).present?

        @valid = !@member && !@invited
      end

      attr_accessor :valid, :invited, :member

      # Public: Should the suggestion item for the specified user be enabled?
      #
      # Returns a boolean.
      alias_method :item_enabled?, :valid

      # Public: Can the specified user be invited to the organization?
      #
      # Returns a boolean.
      alias_method :invitable?, :valid

      # Public: Get text explaining why the user cannot be invited
      #
      # Returns a string (empty if the user *is* invitable).
      def uninvitable_reason_text
        case
        when invited
          "Already invited to this enterprise"
        when member
          "Already in this enterprise"
        end
      end

      # Public: Get the CSS octicon classes to use in the suggestion item
      #
      # Returns a string.
      def octicon_html
        octicon(octicon_class, class: "float-right") if octicon_class
      end

      def octicon_class
        case
        when invitable?
          "plus"
        else
          "check"
        end
      end
    end
  end
end
