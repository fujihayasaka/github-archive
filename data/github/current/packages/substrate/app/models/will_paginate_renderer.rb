# typed: true
# frozen_string_literal: true

require "will_paginate/view_helpers/action_view"

class WillPaginateRenderer < WillPaginate::ActionView::LinkRenderer
  PARAMS_TO_STRIP = %w[controller action user_id repository page].map(&:to_sym).freeze

  # Copy of the upstream will_paginate page_number implementation with the addition of `data-total-pages`
  def page_number(page)
    aria_label = @template.will_paginate_translate(:page_aria_label, page: page.to_i) { "Page #{page}" }
    if page == current_page
      tag(:em, page, class: "current", "aria-label": aria_label, "aria-current": "page", "data-total-pages": total_pages)
    else
      link(page, page, rel: rel_value(page), "aria-label": aria_label)
    end
  end

  def url(page)
    return super(page) unless @options[:url_override].present?

    url_params = merge_get_params({})

    url_params.reject! do |key, _value|
      PARAMS_TO_STRIP.include?(key)
    end

    add_current_page_param(url_params, page)
    "#{@options[:url_override]}?#{url_params.to_query}"
  end

  private

  def merge_get_params(url_params)
    if @template.respond_to?(:request) && @template.request && @template.request.get?
      symbolized_update(url_params, existing_parameters, ::UrlHelper::DANGEROUS_KEYS)
    end
    url_params
  end

  def existing_parameters
    template_params_hash =
      @template.params.dup.permit!.to_h

    valid_params(
      template_params_hash.reject do |name, _value|
        name.to_s.include?("\0")
      end.with_indifferent_access,
    )
  end

  def valid_params(options)
    unless options[:params].respond_to?(:merge)
      options.delete(:params)
    end
    options
  end
end
