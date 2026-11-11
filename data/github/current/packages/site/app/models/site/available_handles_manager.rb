# typed: true
# frozen_string_literal: true

require "set"

module Site
  class AvailableHandlesManager
    attr_reader :approved_handles, :all_handles, :available_handles, :used_handles, :auto_assigned_pairs

    def initialize(
        approved_handles: Site::AvailableHandles::approved_handles,
        handles: [],
        shuffle_approved: true,
        shuffle: false
      )
      approved_handles = approved_handles.shuffle if shuffle_approved
      handles = handles.shuffle if shuffle
      @all_handles = Set.new(approved_handles)
      @approved_handles = @all_handles.to_a
      @all_handles.merge(handles)
      @available_handles = @approved_handles.dup
      @used_handles = Set.new
      @auto_assigned_pairs = Hash.new
    end

    def use(handle = 0)
      @available_handles = @approved_handles.dup if @available_handles.empty?
      return use_by_index(handle) if handle.is_a?(Numeric)

      @all_handles.include?(handle) ? use_available(handle) : use_next_available(handle)
    end

    private

    def use_available(handle)
      if !@used_handles.include?(handle)
        @available_handles.delete(handle)
        @used_handles.add(handle)
      end

      handle
    end

    def use_by_index(index = 0)
      handle = @available_handles.delete_at(index)
      @used_handles.add(handle)

      handle
    end

    def raise_on_invalid_handle(handle)
      raise ArgumentError.new %(Invalid handle: `#{handle}`
        Handle is not in approved list /config/site/approved_handles.json
        This error is raised in development only, production code will choose next available handle from the list.
      )
    end

    def use_next_available(handle)
      raise_on_invalid_handle(handle) if Rails.env.development?
      return @auto_assigned_pairs[handle] if @auto_assigned_pairs.key?(handle)
      @auto_assigned_pairs[handle] = use_by_index
    end
  end
end
