# typed: true
# frozen_string_literal: true

module CopilotSpaces::Pagination
  extend ActiveSupport::Concern

  DEFAULT_PER_PAGE = 30
  MAX_PER_PAGE = 100

  # ========================================================================
  # PAGINATION PARAMETER PARSING
  # ========================================================================

  # Parse and validate pagination parameters, matching the platform-wide
  # Rest::Paginator convention: silently coerce invalid input (non-numeric,
  # nil, zero, or negative) to the default, and clamp values above the max.
  #
  # @param params [Hash] Request parameters hash
  # @return [Integer] validated per_page value between 1 and 100
  def parse_per_page(params)
    per_page = begin
      Kernel.Integer(params[:per_page])
    rescue TypeError, ArgumentError
      DEFAULT_PER_PAGE
    end
    per_page = DEFAULT_PER_PAGE if per_page <= 0
    per_page = MAX_PER_PAGE if per_page > MAX_PER_PAGE
    per_page
  end

  # Parse pagination cursor from HTTP parameters and determine cursor direction
  #
  # This method handles the bidirectional cursor pagination logic. It supports both
  # forward ('after') and reverse ('before') cursors. We start with cursor-based paging
  # and may add offset-based paging in the future if necessary.
  # See: https://github.com/github/secret-scanning/issues/1914
  #
  # Reverse cursors are used for "previous page" navigation. When a user clicks "previous page",
  # we need to:
  # 1. Take the cursor that represents the boundary of the current page
  # 2. Mark it as 'reverse: true' to indicate we want to paginate backwards
  # 3. Flip the query logic to fetch records in the opposite direction
  # 4. Reverse the final results to maintain consistent display order
  #
  # This approach ensures proper bidirectional navigation without gaps or overlaps,
  # even when data is being modified concurrently.
  #
  # @param params [Hash] Request parameters hash
  # @param per_page [Integer] Number of records per page (1-100)
  # @return [Hash] Cursor data with keys:
  #   - :number [Integer|nil] The copilot space number boundary for pagination
  #   - :per_page [Integer] Number of records per page
  #   - :reverse [Boolean] Whether this is reverse (previous page) pagination
  def parse_pagination_cursor(params, per_page)
    # Determine which cursor to use
    if params[:before].present?
      before_cursor_data = decode_cursor(params[:before])
      # Previous page navigation - mark as reverse
      # The 'before' cursor represents where we want to paginate backwards from
      # IMPORTANT: Respect the per_page from the cursor to maintain pagination consistency
      return before_cursor_data.merge(reverse: true) if before_cursor_data
    elsif params[:after].present?
      after_cursor_data = decode_cursor(params[:after])
      # Next page navigation - keep as forward
      # The 'after' cursor represents where we want to paginate forwards from
      # IMPORTANT: Respect the per_page from the cursor to maintain pagination consistency
      return after_cursor_data.merge(reverse: false) if after_cursor_data
    end

    # First page - no cursor boundary, use the requested per_page
    { number: nil, per_page: per_page, reverse: false }
  end

  # ========================================================================
  # SPACE QUERYING WITH PAGINATION
  # ========================================================================

  # Core method for finding spaces with cursor pagination
  #
  # @param scope [ActiveRecord::Relation] Base query scope for copilot spaces
  # @param cursor [Hash] Cursor state for pagination
  # @return [Array<CopilotSpace>] Array of spaces (including extra record for pagination)
  def find_spaces_for_owner(scope, cursor)
    # Base query for owner's copilot spaces
    spaces = scope
      .includes(:owner, :resources)
      .order(number: :desc) # Order by number for consistent cursor pagination

    # Apply cursor filtering based on cursor state
    if cursor[:reverse]
      # For reverse (previous page) cursors, we need to flip the query direction
      if cursor[:number]
        spaces = spaces.where("number > ?", cursor[:number])
      end
      # Reverse cursors query in opposite direction
      spaces = spaces.order(number: :asc)
    else
      # For forward (next page) cursors
      if cursor[:number]
        spaces = spaces.where("number < ?", cursor[:number])
      end
      # Keep descending order for forward pagination
    end

    # Limit results (fetch one extra to determine if there are more pages)
    # This extra record is crucial for proper cursor calculation
    spaces = spaces.limit(cursor[:per_page] + 1)

    spaces_array = spaces.to_a

    # If we're doing reverse pagination, we need to reverse the results
    # to get them back in descending order for display
    if cursor[:reverse]
      spaces_array.reverse!
    end

    spaces_array
  end

  # Core method for finding spaces with cursor pagination using the `id` column
  #
  # NOTE: This method paginates on `id` instead of `number` because `number` is
  # only unique per owner. For compatibility with the shared cursor
  # encode/decode logic, we still use the `:number` key in the cursor hash to
  # store the numeric boundary, which in this method represents an `id` value.
  #
  # Callers should treat `cursor[:number]` here as the last seen `id`, not the
  # `number` column.
  #
  # @param scope [ActiveRecord::Relation] Base query scope for copilot spaces
  # @param cursor [Hash] Cursor state for pagination
  # @return [Array<CopilotSpace>] Array of spaces (including extra record for pagination)
  def find_spaces(scope, cursor)
    spaces = scope.reorder(id: :desc) # Use reorder to replace any existing ordering; order by id instead of number, because number is only unique per owner

    # Apply cursor filtering based on cursor state
    if cursor[:reverse]
      # For reverse (previous page) cursors, we need to flip the query direction
      if cursor[:number]
        # Here cursor[:number] represents the last seen `id` (see method docs)
        spaces = spaces.where("id > ?", cursor[:number])
      end
      # Reverse cursors query in opposite direction
      spaces = spaces.reorder(id: :asc)
    else
      # For forward (next page) cursors
      if cursor[:number]
        # Here cursor[:number] represents the last seen `id` (see method docs)
        spaces = spaces.where("id < ?", cursor[:number])
      end
      # Keep descending order for forward pagination
    end

    # Limit results (fetch one extra to determine if there are more pages)
    # This extra record is crucial for proper cursor calculation
    spaces = spaces.limit(cursor[:per_page] + 1)

    spaces_array = spaces.to_a

    # If we're doing reverse pagination, we need to reverse the results
    # to get them back in descending order for display
    if cursor[:reverse]
      spaces_array.reverse!
    end

    spaces_array
  end

  # ========================================================================
  # PAGINATION RESPONSE HANDLING
  # ========================================================================

  # Calculate pagination state and cursors for copilot spaces
  #
  # This method calculates the pagination state without making assumptions about
  # how the response will be delivered or what methods are available on the caller.
  #
  # @param spaces_plus_one [Array<CopilotSpace>] spaces with extra record for pagination
  # @param current_cursor [Hash] current cursor state
  # @param per_page [Integer] number of records per page
  # @param sort_field [Symbol] field to use for cursor values (:number or :id)
  # @return [Hash] Pagination result with keys:
  #   - :spaces [Array<CopilotSpace>] Spaces to return in the response
  #   - :cursors [Hash] Pagination cursors with :after and :before keys
  #   - :has_more [Boolean] Whether there are more pages available
  def calculate_pagination_response(spaces_plus_one, current_cursor, per_page, sort_field: :number)
    # Determine if there are more pages and extract actual page
    has_more = spaces_plus_one.length > per_page
    spaces_to_return = has_more ? spaces_plus_one.first(per_page) : spaces_plus_one

    # Generate pagination cursors
    cursors = generate_cursors(spaces_plus_one, spaces_to_return, current_cursor, per_page, has_more, sort_field: sort_field)

    {
      spaces: spaces_to_return,
      cursors: cursors,
      has_more: has_more
    }
  end

  # Generate Link header string for pagination
  #
  # This method generates the Link header string with next/prev relationships
  # that can be set by the calling controller.
  #
  # @param cursors [Hash] Cursors hash containing :after and :before keys
  # @param per_page [Integer] Number of records per page
  # @param base_url [String] Base URL for the pagination links
  # @return [String|nil] Link header string or nil if no links
  def generate_pagination_link_header(cursors, per_page, base_url)
    links = []

    if cursors[:after]
      links << %(<#{base_url}?per_page=#{per_page}&after=#{cursors[:after]}>; rel="next")
    end
    if cursors[:before]
      links << %(<#{base_url}?per_page=#{per_page}&before=#{cursors[:before]}>; rel="prev")
    end

    links.any? ? links.join(", ") : nil
  end

  # ========================================================================
  # CURSOR PAGINATION IMPLEMENTATION
  # ========================================================================

  # Generate pagination cursors for API response
  #
  # This method calculates the previous and next cursors based on the fetched data
  # and current pagination state. We start with cursor-based paging and may add
  # offset-based paging in the future if necessary.
  # This follows following doc and pattern
  # https://docs.github.com/en/rest/using-the-rest-api/using-pagination-in-the-rest-api?apiVersion=2022-11-28#using-link-headers
  # See: https://github.com/github/secret-scanning/issues/1914
  #
  # @param spaces_plus_one [Array<CopilotSpace>] All fetched spaces (including extra record)
  # @param spaces_to_return [Array<CopilotSpace>] Spaces to include in the response
  # @param current_cursor [Hash] Current cursor state
  # @param per_page [Integer] Number of records per page
  # @param has_more [Boolean] Whether there are more records available
  # @param sort_field [Symbol] Field to use for cursor values (:number or :id)
  # @return [Hash] Cursors hash with :after and :before keys
  def generate_cursors(spaces_plus_one, spaces_to_return, current_cursor, per_page, has_more, sort_field: :number)
    cursors = {}
    previous_cursor = nil
    next_cursor = nil

    if spaces_to_return.any?
      # Calculate previous cursor
      if current_cursor[:reverse]
        # For reverse cursors: use second-to-last record if we have enough
        if spaces_plus_one.length > per_page
          previous_cursor = encode_cursor(cursor_value_for_space(spaces_plus_one[spaces_plus_one.length - 2], sort_field), per_page, reverse: true)
        end
      else
        # For forward cursors: use first record as the start of previous page
        # But only if we're not on the first page
        if current_cursor[:number] # We have a cursor, so not first page
          previous_cursor = encode_cursor(cursor_value_for_space(spaces_to_return.first, sort_field), per_page, reverse: true)
        end
      end

      # Calculate next cursor
      if has_more
        # Use the last record from the page being returned as the cursor boundary
        # This ensures the next page starts after the last returned item, not the extra record
        next_cursor = encode_cursor(cursor_value_for_space(spaces_to_return.last, sort_field), per_page, reverse: false)
      end
    else
      # Empty page case: if we have a cursor, we're not on the first page
      # and should provide a previous link for navigation back
      if current_cursor[:number]
        # For empty pages, use the cursor number itself as the boundary for going back
        previous_cursor = encode_cursor(current_cursor[:number], per_page, reverse: true)
      end
    end

    # Add the proper after/before cursors to the cursors hash for API response
    if next_cursor
      cursors[:after] = next_cursor
    end
    if previous_cursor
      cursors[:before] = previous_cursor
    end

    cursors
  end

  # ========================================================================
  # CURSOR ENCODING/DECODING
  # ========================================================================

  # Extract the cursor value from a space based on the sort field
  # @param space [CopilotSpace] The space to extract the value from
  # @param sort_field [Symbol] The field to use (:number or :id)
  # @return [Integer] The cursor value
  def cursor_value_for_space(space, sort_field)
    case sort_field
    when :id
      space.id
    else
      space.number
    end
  end

  def encode_cursor(space_number, per_page, reverse: false)
    # Create opaque cursor with space number, page size, and direction info
    cursor_data = {
      number: space_number,
      per_page: per_page,
      reverse: reverse,
      sort: "number"
    }
    Base64.urlsafe_encode64(cursor_data.to_json)
  end

  def decode_cursor(cursor)
    return nil if cursor.blank?

    begin
      decoded = Base64.urlsafe_decode64(cursor)
      cursor_data = JSON.parse(decoded)
      return nil unless valid_cursor_data?(cursor_data)

      {
        number: cursor_data["number"],
        per_page: cursor_data["per_page"],
        reverse: cursor_data["reverse"]
      }
    rescue ArgumentError, JSON::ParserError
      nil
    end
  end

  private

  def valid_cursor_data?(cursor_data)
    return false unless cursor_data.is_a?(Hash)

    number = cursor_data["number"]
    per_page = cursor_data["per_page"]
    reverse = cursor_data["reverse"]
    sort = cursor_data["sort"]

    number.is_a?(Integer) &&
      number.positive? &&
      per_page.is_a?(Integer) &&
      per_page.between?(1, MAX_PER_PAGE) &&
      [true, false].include?(reverse) &&
      sort == "number"
  end
end
