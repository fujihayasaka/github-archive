# typed: strict
# frozen_string_literal: true

class IssueFieldMultiSelectValue < IssueFieldValue
  include Issues::IIssueFieldMultiSelectValue
  include MemexProjectColumn::IDataSource
  include GitHub::Memoizer

  validate :validate_raw_value_presence
  validate :value_is_valid_for_multi_select_field

  sig { returns(String) }
  def self.sti_name
    "multi_select"
  end

  sig { returns(T::Array[IssueFieldOption]) }
  def options
    cached = @memoized_options
    return cached unless cached.nil?

    value_ids = raw_value
    computed = if !value_ids.is_a?(Array) || value_ids.empty? || issue_field_id.nil?
      []
    elsif T.must(issue_field).options.loaded?
      T.must(issue_field).options.select { |option| value_ids.include?(option.id) }
    else
      T.must(issue_field).options.where(owner_id: T.must(issue_field).owner_id, id: value_ids).to_a
    end

    @memoized_options = T.let(computed, T.nilable(T::Array[IssueFieldOption]))
    computed
  end

  # Preloads IssueFieldOption rows for a collection of multi-select values in
  # a single query, then assigns each value its subset. Use this when rendering
  # lists (timeline, project views, search results) to avoid N+1 lookups.
  sig { params(values: T::Enumerable[IssueFieldMultiSelectValue]).void }
  def self.batch_load_options(values)
    values = values.to_a
    return if values.empty?

    field_ids = values.filter_map(&:issue_field_id).uniq
    return if field_ids.empty?

    # Batch-preload issue_field of values so we can read owner_id without triggering N+1 loads.
    ActiveRecord::Associations::Preloader.new(records: values, associations: :issue_field).call

    owner_ids = values.filter_map { |v| v.issue_field&.owner_id }.uniq
    return if owner_ids.empty?

    options_by_field = IssueFieldOption.where(owner_id: owner_ids, issue_field_id: field_ids).group_by(&:issue_field_id)

    values.each do |value|
      raw = value.read_attribute(:value)
      field_id = value.issue_field_id
      if !raw.is_a?(Array) || field_id.nil?
        value.preloaded_options = []
        next
      end

      field_options = options_by_field[field_id] || []
      value.preloaded_options = field_options.select { |opt| raw.include?(opt.id) }
    end
  end

  # Internal setter used by .batch_load_options to seed the memoized #options
  # without going through ActiveRecord.
  sig { params(opts: T::Array[IssueFieldOption]).void }
  def preloaded_options=(opts)
    @memoized_options = T.let(opts, T.nilable(T::Array[IssueFieldOption]))
  end

  # Returns the names of the selected IssueFieldOptions as a comma-separated
  # string for backwards compatibility with existing scalar consumers
  # (HydroIssueFieldTimelineEventsJob, IssueEventDetail#issue_field_value,
  # GraphQL Platform::Objects::IssueFieldAddedEvent#value, etc.) that assume
  # `IssueFieldValue#value` is a String.
  #
  # Prefer #values when callers want a typed array of names.
  sig { override.returns(T.nilable(String)) }
  def value
    names = values
    return nil if names.nil?
    names.join(",")
  end

  # Returns the names of the selected IssueFieldOptions as a typed array,
  # sorted by priority (ascending), or nil when no options are selected.
  sig { returns(T.nilable(T::Array[String])) }
  def values
    opts = options
    return nil if opts.empty?
    IssueFieldOption.sorted_options(opts).map(&:name)
  end

  # Returns the option IDs as an array of strings for ElasticSearch indexing
  sig { override.returns(T.nilable(T::Array[String])) }
  def elasticsearch_value
    opts = options
    return nil if opts.empty?
    opts.map { |o| o.id.to_s }
  end

  sig { override.returns(T::Boolean) }
  memoize def memex_column_value_present?
    options.any?
  end

  # MemexProjectColumn::IDataSource expects a single
  # MemexProjectColumnValue::SerializableValue. Projects integration will be
  # implemented later so for now return nil.
  sig { override.returns(T.untyped) }
  def memex_project_column_value
    nil
  end

  private

  sig { void }
  def value_is_valid_for_multi_select_field
    return if issue_field.nil?

    if data_type.nil?
      errors.add(:data_type, :invalid_data_type)
      return
    end

    return unless data_type.to_sym == :multi_select

    option_ids = raw_value
    return if option_ids.nil?

    unless option_ids.is_a?(Array)
      errors.add(:value, :must_be_an_array_of_valid_issue_field_option_ids)
      return
    end

    if option_ids.uniq.length != option_ids.length
      errors.add(:value, :must_not_contain_duplicate_option_ids)
      return
    end

    valid_option_ids = T.must(issue_field).options.map(&:id).to_set

    option_ids.each do |option_id|
      unless option_id.is_a?(Integer)
        errors.add(:value, :must_be_an_array_of_valid_issue_field_option_ids)
        return
      end

      unless valid_option_ids.include?(option_id)
        errors.add(:value, :must_be_a_valid_issue_field_option_id)
        return
      end
    end
  end
end
