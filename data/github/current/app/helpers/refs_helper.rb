# typed: false
# frozen_string_literal: true

module RefsHelper
  PLACEHOLDER_STRING = "___REFNAME_PLACEHOLDER_TO_FIX_AUTO_ESCAPING_IN_URL_FOR_WHICH_IS_NOT_OK_IN_THIS_CASE___"
  TEMPLATE = "{{ urlEncodedRefName }}"

  # Returns a path string with a template component intented for use in a
  # template-parts href field that will point to a route equivalent to the
  # current one but on a different ref.
  def ref_path_template
    safe_url_for(
      controller: params[:controller].to_s,
      action: params[:action].to_s,
      name: PLACEHOLDER_STRING,
      path: params[:path],
    ).sub(PLACEHOLDER_STRING, TEMPLATE)
  end

  def base_ref_comparison_path_template(comparison:, expand:)
    base_ref_comparison_path(
      comparison,
      RefsHelper::PLACEHOLDER_STRING,
      expand: expand
    ).sub(PLACEHOLDER_STRING, TEMPLATE)
  end

  def head_ref_comparison_path_template(comparison:, expand:)
    head_ref_comparison_path(
      comparison,
      RefsHelper::PLACEHOLDER_STRING,
      expand: expand
    ).sub(PLACEHOLDER_STRING, TEMPLATE)
  end
end
