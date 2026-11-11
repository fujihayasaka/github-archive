# typed: true
# rubocop:disable Primer/PrimerOcticon
# frozen_string_literal: true

module Stafftools
  module Organization
    module Teams
      class PendingCollaboratorsView < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels
        attr_reader :collaborator_invitations, :filter_seats, :query

        # Should be show the filter seat occupiers link?
        #
        # This is true if there are any collaborators listed, or if we are
        # filtering on seat occupiers (since there could be collaborators without
        # the filter enabled).
        #
        # Returns a Boolean.
        def show_filter?
          filter_seats || collaborator_invitations.any?
        end

        # The link to toggle between filtering and not filtering.
        #
        # Returns a String.
        def filter_link
          seats_part = filter_seats ? "?is_occupying_seat=false" : "?is_occupying_seat=true"
          query_part = "&query=#{query}" if query.present?
          "#{seats_part}#{query_part}"
        end

        # The icon to use for the filter link.
        #
        # Returns a String containg the HTML for an octicon.
        def filter_icon
          filter_seats ? helpers.octicon("x") : helpers.octicon("search")
        end

        # The text we should display for the filter.
        #
        # Returns a String.
        def filter_text
          filter_seats ? "Clear seat occupiers filter" : "Filter seat occupiers"
        end

        # The text displayed if there are no pending collaborators to list.
        #
        # Returns a String.
        def blankslate_text
          query_part = %Q[ matching "#{query}"] if query.present?
          seats_part = " with invitations occupying a seat" if filter_seats
          "There aren't any pending collaborators#{query_part}#{seats_part} for this organization."
        end

        # The title used for the list of pending collaborators.
        #
        # Returns a String.
        def list_title
          if filter_seats
            "Pending collaborators occupying seats"
          else
            "Pending collaborators"
          end
        end

        # A formatted JSON hash of collaborators and the repositories they are
        # invited to, for sending to users.
        #
        # Returns a Hash.
        def collaborators_json
          hash = {}
          collaborator_invitations.each do |invitation|
            key = invitation.email ? invitation.email : invitation.invitee.login

            if hash.has_key? key
              hash[key] << invitation.repository.name_with_owner
            else
              hash[key] = [invitation.repository.name_with_owner]
            end
          end

          JSON.pretty_generate(hash)
        end
      end
    end
  end
end
