# typed: true
# rubocop:disable Primer/PrimerOcticon
# frozen_string_literal: true

module Stafftools
  module RepositoryViews
    class ImporterView < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels
      include StatusChecklist
      include Porter::Urls

      attr_reader :repository, :porter_status

      def page_title
        "#{repository.name_with_owner} - Importer"
      end

      def admin_url
        porter_admin_repository_url(repository: repository)
      end

      def import_active_li
        status_li(repository.is_importing?, ["GitHub: will redirect to porter, if repository is empty", "GitHub: will not redirect to porter"])
      end

      def import_refs_li
        if repository.online?
          status = repository.extended_refs("refs/import/").any?
          text = [
            helpers.safe_join(["GitHub: ", helpers.content_tag(:code, "refs/import/*"), " is present"]), # rubocop:disable Rails/ViewModelHTML
            helpers.safe_join(["GitHub: ", helpers.content_tag(:code, "refs/import/*"), " is not present"]), # rubocop:disable Rails/ViewModelHTML
          ]
          status_li(status, text)
        else
          status_li(false, ["repository offline, cannot check refs"])
        end
      end

      def porter_state_li
        request_result, info = porter_status
        case request_result
        when :ok
          case status_text = info["status"]
          when "complete"
            status_li(true, "Porter: complete")
          when "error"
            status_li(:failed, "Porter: error (in #{info["failed_step"]})")
          else
            # Using a different octicon is not supported by status_li.
            octicon = helpers.octicon("ellipsis")
            text = ERB::Util.html_escape(" Porter: #{info["status"]}")
            helpers.content_tag :li, octicon + text, class: "neutral" # rubocop:disable Rails/ViewModelHTML
          end
        when :not_found
          status_li(:neutral, "Porter: not used")
        else
          helpers.content_tag :li, "Porter: (status could not be fetched)" # rubocop:disable Rails/ViewModelHTML
        end
      end

      private

      def status_li(state, text, *args)
        if text.is_a?(Array)
          true_text, false_text = text
          super(state, state ? true_text : false_text, [*args])
        else
          super
        end
      end

      def admin_url_template
        GitHub.porter_repository_admin_url_template
      end
    end
  end
end
