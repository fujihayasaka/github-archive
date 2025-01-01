# typed: true
# frozen_string_literal: true

class MemexProject
  # There are some special cases when it comes to figuring out the actual values to compare against.  These
  # special cases could be:
  #   - references (i.e. ID values) in the database.
  #   - macros (i.e. @current, @previous, @next)
  # In these case, the user will pass us a value which we will then have to lookup and/or replace.
  # This class handles this 'resolution' logic for all columns.
  class FilterValueResolver
    # Macros
    CURRENT_MACRO  = "@current"
    NEXT_MACRO     = "@next"
    PREVIOUS_MACRO = "@previous"
    TODAY_MACRO    = "@today"
    CURRENT_MACRO_REGEX = /\A#{CURRENT_MACRO}([+-]{1}\d+)?\z/
    ITERATION_MACRO_REGEX = /\A(#{CURRENT_MACRO}|#{NEXT_MACRO}|#{PREVIOUS_MACRO})([+-]{1}\d+)?\z/

    # Iteration Keys
    ITERATION_DURATION_KEY   = "duration"
    ITERATION_ID_KEY         = "id"
    ITERATION_START_DATE_KEY = "start_date"
    ITERATION_TITLE_KEY      = "title"

    PLACEHOLDER_KEY          = "placeholder"

    # To minimize this classes surface area lets not expose these constants unless we have to.
    private_constant :CURRENT_MACRO,
                     :ITERATION_DURATION_KEY,
                     :ITERATION_ID_KEY,
                     :ITERATION_START_DATE_KEY,
                     :ITERATION_TITLE_KEY,
                     :PLACEHOLDER_KEY,
                     :NEXT_MACRO,
                     :PREVIOUS_MACRO,
                     :TODAY_MACRO

    attr_reader :column, :time, :extrapolate

    delegate :data_type, to: :column

    # Initializes a new FilterValueResolver
    #
    # @param column The field for resolving values.
    # @param time Time value typically used as a reference for Today or Current.
    # @param iteration_key Used to return a particular object property, such as start_date for Iteration fields.
    # @param extrapolate If true, then extrapolate field values with placeholders for relative matching.
    #   For example, extrapolation enables matching on Iteration field values to return <@current even if @current does not exist.
    def initialize(column, time: Time.current, iteration_key: ITERATION_ID_KEY, extrapolate: false)
      raise ArgumentError, "column is required" unless column
      raise ArgumentError, "time is required"   unless time

      @column = column
      @time   = time
      @iteration_key = iteration_key
      @extrapolate = extrapolate

      freeze
    end

    def resolve(filter_values)
      # Implemented with the visitor pattern.  If you wish to provide a custom resolver for a data type then
      # simply implement a new method named "resolve_<data_type>_filter_values" which accepts an array of
      # filter values and returns an array of filter values.
      resolver_method_name = "resolve_#{data_type}_filter_values"

      if respond_to?(resolver_method_name, true)
        send(resolver_method_name, filter_values)
      else
        filter_values
      end
    end

    private

    # Create a hash lookup so we do not nest linear loops.
    def iteration_titles_to_keys_lookup(iterations)
      iterations.each_with_object({}) do |iteration, titles_to_keys|
        next if iteration[PLACEHOLDER_KEY]
        key = iteration[ITERATION_TITLE_KEY].downcase

        # Take the first iteration found, by title.  If iterations have duplicate titles then all subsquent
        # ones will be ignored.  This should be how dotcom works as well.
        next if titles_to_keys.key?(key)

        titles_to_keys[key] = iteration[@iteration_key]
      end
    end

    def find_current_iteration_index(iterations)
      find_iteration_index(iterations, time.to_date)
    end

    def find_iteration_index(iterations, date)
      iterations.find_index do |iteration|
        start_date = iteration[ITERATION_START_DATE_KEY].to_date

        # Offset the start_date by the number of days.  Subtract one so there are no overlaps.
        offset   = iteration[ITERATION_DURATION_KEY].to_i - 1
        end_date = start_date + offset.days

        # Check if the current date is within the iteration's range.
        date >= start_date && date <= end_date
      end
    end

    def resolve_single_select_filter_values(filter_values)
      column.settings_option_ids(filter_values)
    end

    def resolve_date_filter_values(filter_values)
      filter_values.map do |filter_value|
        value_to_match = filter_value.to_s.downcase

        case value_to_match
        when TODAY_MACRO
          time.to_date.to_s
        else
          filter_value
        end
      end
    end

    def resolve_iteration_filter_values(filter_values)
      all_iterations           = Array.new(column.settings_all_iterations)
      add_placeholder_iterations!(all_iterations) if extrapolate
      all_iterations_max_index = all_iterations.length - 1
      title_lookup             = iteration_titles_to_keys_lookup(all_iterations)
      current_iteration_index  = find_current_iteration_index(all_iterations)

      filter_values.map do |filter_value|
        filter_value = filter_value.to_s.downcase
        macro, offset = filter_value.match(ITERATION_MACRO_REGEX)&.captures
        offset = offset.present? ? offset.to_i : 0

        # fallback to the original value if we can't resolve an id
        case macro
        when CURRENT_MACRO_REGEX

          if offset_allowed(offset, current_iteration_index, all_iterations_max_index)
            iteration_value_at_index(all_iterations, current_iteration_index + offset)
          end
        when PREVIOUS_MACRO
          if current_iteration_index && offset_allowed(offset, current_iteration_index - 1, all_iterations_max_index)
            iteration_value_at_index(all_iterations, current_iteration_index - 1 + offset)
          end
        when NEXT_MACRO
          if current_iteration_index && offset_allowed(offset, current_iteration_index + 1, all_iterations_max_index)
            iteration_value_at_index(all_iterations, current_iteration_index + 1 + offset)
          end
        else
          title_lookup[filter_value]
        end || filter_value
      end
    end

    # Add iteration placeholders to the start, end, and current if needed to support range filters
    # that exceed the boundaries of the existing set of defined iterations.
    def add_placeholder_iterations!(all_iterations)
      return unless all_iterations.present? && extrapolate

      # Add current iteration placeholder if missing (could be before, after, or during a break between iterations)
      if find_current_iteration_index(all_iterations).nil?
        current_placeholder = create_iteration_placeholder(time.to_date)
        all_iterations.append(current_placeholder).sort_by! { |i| i[ITERATION_START_DATE_KEY] }
      end

      # Add a placeholder at the start of the existing iterations, if needed
      first_iteration = all_iterations[0]
      unless first_iteration[PLACEHOLDER_KEY]
        first_date = first_iteration[ITERATION_START_DATE_KEY].to_date
        start_placeholder = create_iteration_placeholder(first_date - 1)
        all_iterations.prepend(start_placeholder)
      end

      # Add a placeholder at the end of the existing iterations, if needed
      last_iteration = all_iterations[all_iterations.length - 1]
      unless last_iteration[PLACEHOLDER_KEY]
        last_date = last_iteration[ITERATION_START_DATE_KEY].to_date + last_iteration[ITERATION_DURATION_KEY].to_i
        end_placeholder = create_iteration_placeholder(last_date)
        all_iterations.append(end_placeholder)
      end
    end

    def create_iteration_placeholder(date)
      {
        ITERATION_START_DATE_KEY => date.to_formatted_s(:iso8601),
        ITERATION_DURATION_KEY => 1,
        PLACEHOLDER_KEY => true
      }
    end

    # Check that the requested offset is within the iteration array boundaries if not extrapolating
    def offset_allowed(offset, current_iteration_index, all_iterations_max_index)
      return false if current_iteration_index.nil?
      return true if extrapolate

      # if @current is the first iteration
      if current_iteration_index == 0
        offset_allowed = offset.between?(current_iteration_index, all_iterations_max_index)

      # if @current is a middle iteration
      elsif current_iteration_index.between?(1, all_iterations_max_index - 1)
        offset_allowed = offset.between?(current_iteration_index * -1, all_iterations_max_index - 1)

      # if @current is the last iteration
      elsif current_iteration_index == all_iterations_max_index
        offset_allowed = offset.between?(all_iterations_max_index * -1, 0)

      else
        offset_allowed = false
      end
      offset_allowed
    end

    # Return the iteration value at the requested index, clamped within the boundaries of the iterations array
    def iteration_value_at_index(all_iterations, index)
      clamped_index = index.clamp(0, all_iterations.length - 1)
      all_iterations[clamped_index][@iteration_key]
    end
  end
end
