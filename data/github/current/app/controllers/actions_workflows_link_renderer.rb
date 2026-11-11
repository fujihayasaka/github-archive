# typed: true
# frozen_string_literal: true

class ActionsWorkflowsLinkRenderer < WillPaginate::ActionView::LinkRenderer
  def prepare(collection, options, template)
    @collection = collection
    @options = options
    @template = template
  end

  # When the workflow runs count is capped, insert a link to the page beyond
  # the cap (e.g. page 101) so it appears before the "Next" button.
  def pagination
    items = super
    if @options[:count_is_capped]
      next_index = items.index(:next_page)
      extra_page = GitHub.max_ui_pagination_page + 1
      items.insert(next_index || items.length, extra_page)
    end
    items
  end

  # Used to override the URLs for Previous and Next page in the Actions tab when viewing a specific workflow
  def url(page)
    url_params = merge_get_params(default_url_params)
    url_params[:only_path] = true
    merge_optional_params(url_params)
    add_current_page_param(url_params, page)
    url_params.delete(:page) if page == 1

    return @template.workflow_runs_list_path(url_params) if url_params[:workflow_file_name].present?
    @template.actions_path(url_params)
  end
end
