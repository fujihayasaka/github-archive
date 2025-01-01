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

    # To minimize this classes surface area lets not expose these constants unless we have to.
    private_constant :CURRENT_MACRO,
                     :ITERATION_DURATION_KEY,
                     :ITERATION_ID_KEY,
                     :ITERATION_START_DATE_KEY,
                     :ITERATION_TITLE_KEY,
                     :NEXT_MACRO,
                     :PREVIOUS_MACRO,
                     :TODAY_MACRO

    attr_reader :column, :time

    delegate :data_type, to: :column

    def initialize(column, time: Time.current, iteration_key: ITERATION_ID_KEY)
      raise ArgumentError, "column is required" unless column
      raise ArgumentError, "time is required"   unless time

      @column = column
      @time   = time
      @iteration_key = iteration_key

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
      all_iterations           = column.settings_all_iterations
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
            all_iterations[current_iteration_index + offset][@iteration_key]
          end
        when PREVIOUS_MACRO
          if current_iteration_index && offset_allowed(offset, current_iteration_index - 1, all_iterations_max_index)
            all_iterations[current_iteration_index - 1 + offset][@iteration_key]
          end
        when NEXT_MACRO
          if current_iteration_index && offset_allowed(offset, current_iteration_index + 1, all_iterations_max_index)
            all_iterations[current_iteration_index + 1 + offset][@iteration_key]
          end
        else
          title_lookup[filter_value]
        end || filter_value
      end
    end

    def offset_allowed(offset, current_iteration_index, all_iterations_max_index)
      return false if current_iteration_index.nil?

      # if @current is the first iteration
      if current_iteration_index == 0
        offset_allowed = offset.between?(current_iteration_index, all_iterations_max_index)

      # if @current is a middle iteration
      elsif current_iteration_index.between?(1, all_iterations_max_index - 1)
        offset_allowed = offset.between?(current_iteration_index * -1 , all_iterations_max_index - 1)

      # if @current is the last iteration
      elsif current_iteration_index == all_iterations_max_index
        offset_allowed = offset.between?(all_iterations_max_index * -1 , 0)

      else
        offset_allowed = false
      end
      offset_allowed
    end
  end
end
