# typed: false
# frozen_string_literal: true

module ActionsHelper
  def actions_workflow_filtering_enabled?
    FeatureFlag.vexi.enabled?(:actions_workflow_filtering, current_repository, default: false)
  end

  def actions_workflow_path(filters:, workflow: nil)
    actions_filtered_path(filters: filters, replace: { workflow: workflow })
  end

  def actions_filtered_path(filters:, replace: {})
    query = actions_filtered_query(filters: filters, replace: replace)

    return actions_path if query.blank?

    actions_path query: query
  end

  def actions_filtered_query(filters:, replace: {})
    filters = filters.dup

    replace.each_pair do |replace_key, replace_val|
      case replace_val
      when NilClass
        filters.reject! { |comp_key, _| comp_key == replace_key }
      else
        filters.merge!({ replace_key => replace_val })
      end
    end

    # Extract negated filters and expand array values into repeated qualifiers
    # unconditionally when present, so the output is correct regardless of
    # which flag context produced the filters hash.
    negated = filters.delete(:negated)
    has_structured_values = negated || filters.values.any? { |v| v.is_a?(Array) }

    if has_structured_values
      components = filters.flat_map do |key, value|
        if value.is_a?(Array)
          value.map { |v| [key, v] }
        else
          [[key, value]]
        end
      end

      if negated
        negated.each do |key, value|
          if value.is_a?(Array)
            value.each { |v| components << [key, v, true] }
          else
            components << [key, value, true]
          end
        end
      end

      Search::ParsedQuery.stringify(components)
    else
      Search::ParsedQuery.stringify(filters)
    end
  end

  def filtered_runs_by_file_path(filters: {}, replace: {}, filename: nil, lab: nil, show_workflow_tip: nil)
    params = {}
    query = actions_filtered_query(filters: filters, replace: replace)
    params[:query] = query unless query.blank?
    params[:show_workflow_tip] = show_workflow_tip if show_workflow_tip

    if filename
      params[:workflow_file_name] = filename
      params[:lab] = true if lab

      workflow_runs_list_path(params)
    else
      actions_path(params)
    end
  end

  # Get included (positive) values for a multi-select filter key.
  def workflow_filter_included(filters, key)
    Array(filters[key])
  end

  # Get excluded (negated) values for a multi-select filter key.
  def workflow_filter_excluded(filters, key)
    negated = filters[:negated] || {}
    Array(negated[key])
  end

  # Build the base path with a specific filter key removed (both positive and negated).
  # Used by the multi-select panel JS to construct the final URL on close.
  def workflow_filter_base_path(filters:, exclude_key:, filename: nil, lab: nil)
    cleaned = filters.dup
    cleaned.delete(exclude_key)
    if cleaned[:negated]
      cleaned[:negated] = cleaned[:negated].dup
      cleaned[:negated].delete(exclude_key)
      cleaned.delete(:negated) if cleaned[:negated].empty?
    end
    filtered_runs_by_file_path(filters: cleaned, filename: filename, lab: lab)
  end

  def check_run_label_data_to_environment(label_data)
    normalized_label_data = label_data&.map { |label| label.downcase } || []
    if normalized_label_data.any? { |label| label.include?("ubuntu") }
      "UBUNTU"
    elsif normalized_label_data.any? { |label| label.include?("macos") }
      "MACOS"
    elsif normalized_label_data.any? { |label| label.include?("windows") }
      "WINDOWS"
    else
      "RUNTIME_UNKNOWN"
    end
  end

  def filtered_cache_items_path(filters: {}, replace: {})
    params = {}
    query = actions_filtered_query(filters: filters, replace: replace)
    params[:query] = query unless query.blank?
    actions_caches_path(params)
  end

  def get_global_id(entity)
    use_next_gid = !GitHub.enterprise?
    use_next_gid ? entity.next_global_id : entity.global_relay_id
  end

  def is_trial_billing_plan_for_entity?(entity)
    billing_owner = entity.is_a?(Organization) && entity.business.present? ? entity.business : entity
    if billing_owner.is_a?(Business)
      return billing_owner.trial?
    elsif billing_owner.is_a?(Organization)
      return billing_owner.on_enterprise_cloud_trial?
    end

    false
  end
end
