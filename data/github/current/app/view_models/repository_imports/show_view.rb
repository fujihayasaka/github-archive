# typed: true
# frozen_string_literal: true

module RepositoryImports
  class ShowView < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels
    include EscapeHelper

    # Internal: The RepositorySourceImport for this view.
    #
    # Returns a RepositorySourceImport.
    attr_reader :repository_import

    # Internal: The percent that the client claims to have already shown.
    attr_reader :start_percent

    # Internal: The status that the client claims to be showing now.
    attr_reader :start_status

    # Public: Error messages for display in the flash-like container
    attr_reader :flash_message

    # Public: Methods defined on the RepositorySourceImport instance that the view
    # needs.
    delegate :repository, :has_large_files?, :error_message, :status,
      :url_params, :authors, :projects, :import_percent, :push_percent,
      :authors_count, to: :repository_import

    # Public: The interval in seconds to refresh the import show page.
    #
    # Returns an Integer or nil.
    def refresh_time
      case status
      when :pushing, :mapping, :detecting
        1.minute
      when :importing
        5.minutes
      else
        1.hour
      end.to_i
    end

    # Add the socket refresh behavior to the repository_import views
    def socket_classes
      "js-socket-channel js-updatable-content"
    end

    def fade_in
      start_status.to_s == status.to_s ? "" : "anim-fade-in"
    end

    # Add the socket refresh behavior info to repository_import views
    def repository_import_data_attrs
      channel = GitHub::WebSocket::Channels.source_import(repository)
      safe_data_attributes({
        channel: GitHub::WebSocket.signed_channel(channel),
        url: urls.repository_import_path(repository_import.url_params.merge(percent: percent_complete, status: status)),
      })
    end

    # Public: The cumulative percent complete for the import.
    #
    # Returns an Integer.
    def percent_complete
      case status
      when :complete
        100
      when :pushing
        push_percent * 0.1 + 90
      when :mapping
        85
      when :importing
        import_percent * 0.7 + 10
      when :detecting, :auth, :choose
        0
      end.to_i
    end

    # Public: The css rules for rendering the progress bar based on state and
    # percent complete.
    def status_range
      "width: #{100 - (start_percent || percent_complete).to_i}%; min-width: #{100 - percent_complete}%; animation-duration: 5s;"
    end

    # Public: Have an authors been found for this import?
    #
    # Returns true or false.
    def authors_found?
      authors.any?
    end

    # Public: Which octicon should be shown next to the authors callout?
    def authors_octicon
      authors_count > 1 ? "organization" : "person"
    end

    # Public: Is the repository import complete?
    #
    # Returns true or false.
    def import_complete?
      repository_import.status?(:complete)
    end

    # Public: The owner name and repository name joined with a /.
    #
    # Example:
    #
    #   jonmagic/scriptular
    #
    # Returns a String.
    def name_with_display_owner
      repository.name_with_display_owner
    end
  end
end
