# typed: true
# frozen_string_literal: true

module RepositoryAdvisories
  class EventView < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels
    ICONS = {
      "closed"               => "shield-check",
      "collaborator_added"   => "person",
      "collaborator_removed" => "person",
      "credit_accepted"      => "trophy",
      "credit_assigned"      => "trophy",
      "credit_declined"      => "trophy",
      "credit_type_changed"  => "trophy",
      "credit_unassigned"    => "trophy",
      "cve_assigned"         => "check",
      "cve_not_assigned"     => "x",
      "cve_requested"        => "shield",
      "github_published"     => "shield",
      "github_withdrawn"     => "shield-x",
      "published"            => "shield",
      "renamed"              => "pencil",
      "reopened"             => "dot-fill",
      "accepted"             => "check",
      "workspace_created"    => "repo-forked",
      "workspace_deleted"    => "repo-deleted",
    }
    ICONS.default = "dot"
    ICONS.freeze

    COLORS = {
      "closed"           => "purple",
      "cve_assigned"     => "green",
      "cve_not_assigned" => "red",
      "published"        => "green",
      "reopened"         => "green",
      "accepted"         => "green",
    }.freeze

    delegate :actor,
             :actor_id,
             :changed_attribute,
             :subject,
             :subject_id,
             :value_is,
             :value_was,
             to: :event

    attr_reader :event, :show_credit_action_button

    def visible?
      # We're hiding GitHub "rejection" for now because it's not helpful for a
      # maintainer and carries a negative connotation.
      event.name != "github_rejected"
    end

    def dom_id
      "event-#{event.id}"
    end

    def icon
      ICONS[event.name]
    end

    def badge_color
      case color
      when "red"
        "color-fg-on-emphasis color-bg-danger-emphasis"
      when "green"
        "color-fg-on-emphasis color-bg-success-emphasis"
      when "purple"
        "color-fg-on-emphasis color-bg-done-emphasis"
      else
        ""
      end
    end

    def indefinite_article_for(word)
      case word
      when "analyst" then "an"
      else
        "a"
      end
    end

    def show_credit_suffix?
      (event.credit_assigned? || event.credit_unassigned?) && value_is.present?
    end

    def credit_suffix
      case event.name
      when "credit_assigned"
        if value_is == "other"
          "with credit type \"other\""
        else
          "as #{indefinite_article_for(value_is)} #{value_is}"
        end
      when "credit_unassigned"
        "had a credit of type \"#{value_is}\" removed"
      else
        ""
      end
    end

    def verb
      case event.name
      when "collaborator_added"
        "added"
      when "collaborator_removed"
        "removed"
      when "credit_accepted"
        "accepted credit"
      when "credit_assigned"
        "was credited"
      when "credit_declined"
        "declined credit"
      when "credit_type_changed"
        if value_is == "other"
          "was credited with credit type"
        else
          "was credited as #{indefinite_article_for(value_is)}"
        end
      when "credit_unassigned"
        ""
      when "github_published"
        "released"
      when "github_rejected"
        "dismissed"
      when "github_withdrawn"
        "withdrew"
      when "accepted"
        "accepted this report"
      when "workspace_created"
        "created the temporary private fork"
      when "workspace_deleted"
        "deleted the temporary private fork"
      else
        event.name
      end
    end

    def event_name
      event.name
    end

    def timestamp
      event.created_at
    end

    def link_to_global_advisory?
      (event.github_published? || event.github_withdrawn?) &&
        event.repository_advisory&.vulnerability&.globally_available?
    end

    def global_advisory_path
      urls.global_advisory_path(event.repository_advisory.ghsa_id)
    end

    def advisory_ghsa_id
      event.repository_advisory.vulnerability.ghsa_id
    end

    def credit_action_button_path
      path_arguments = [
        event.repository_advisory.repository.owner,
        event.repository_advisory.repository,
        event.repository_advisory
      ]

      case event_name
      when "credit_accepted"
        urls.decline_repository_advisory_credit_path(*path_arguments)
      when "credit_declined"
        urls.accept_repository_advisory_credit_path(*path_arguments)
      end
    end

    def credit_action_button_text
      case event_name
      when "credit_accepted"
        "Decline credit"
      when "credit_declined"
        "Accept credit"
      end
    end

    def event_workspace_repository
      return unless changed_attribute == "workspace_repository_id"

      subject
    end

    private

    def color
      COLORS[event.name]
    end
  end
end
