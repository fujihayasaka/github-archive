# typed: true
# frozen_string_literal: true

module Search
  # This view model is used by GHES installations via DotcomCodesearchController
  class DotcomResultsView < ResultsView
    def render_results
      case query
      when Search::Queries::UserQuery
        view.render partial: "dotcom_codesearch/results_user", locals: {
          results: results,
        }
      when Search::Queries::CodeQuery
        view.render partial: "dotcom_codesearch/results_code", locals: {
          results: results,
        }
      when Search::Queries::CommitQuery
        view.render partial: "dotcom_codesearch/results_commit", locals: {
          results: results,
          search: @search,
        }
      when Search::Queries::IssueQuery
        view.render partial: "dotcom_codesearch/results_issue", locals: {
          results: results,
        }
      when Search::Queries::TopicQuery
        view.render partial: "dotcom_codesearch/results_topic", locals: {
          results: results,
        }
      when Search::Queries::WikiQuery
        view.render partial: "dotcom_codesearch/results_wiki", locals: { search: @search }
      else
        view.render partial: "dotcom_codesearch/results_repo", locals: {
          results: results,
        }
      end
    end

    def link_to_wikis(link_classes: "menu-item width-full text-left", fetch_counter: false)
      view.content_tag(:button, "Wikis", class: "btn-link #{link_classes}", disabled: true)
    end

    private

    def results
      return Search::DotcomResults.empty if !GitHub::Connect.unified_search_enabled? || repo_specific?

      @results ||=
        begin
          query.execute_dotcom(self.current_user || User.ghost, @type.downcase)
        rescue => boom # rubocop:todo Lint/GenericRescue
          Failbot.report(boom.with_redacting!)
          Search::DotcomResults.empty
        end
    end

    def link_to_menu(type, label: nil, link_classes: "", fetch_counter: false)
      link_classes = "menu-item" if link_classes.empty?
      link_classes = "#{link_classes} selected" if is_current_view(type)

      url = view.link_to_dotcom_search(type: type.downcase, p: nil, s: nil, o: nil, q: params[:q])
      label ||= type

      view.link_to(label, url, class: link_classes)
    end
  end
end
