# typed: true
# frozen_string_literal: true

module GitHub
  class InstrumentationThread
    DEFAULT_INTERVAL = 15

    def self.start
      new.start
    end

    def initialize(dogstats: GitHub.new_dogstats, interval: DEFAULT_INTERVAL)
      @interval = interval
      @dogstats = dogstats
      @tags = []
      @thread = nil
    end

    def running?
      @thread && @thread.alive?
    end

    def start
      return if running?
      @thread = Thread.new do # rubocop:disable GitHub/ThreadUse
        loop do
          report
          sleep @interval
        end
      end
    end

    def report
      vm_stat = RubyVM.stat
      @dogstats.distribution "ruby.vm.next_shape_id", vm_stat[:next_shape_id], tags: @tags
      # report 0 for Ruby 3.2
      @dogstats.distribution "ruby.vm.shape_cache_size", (vm_stat[:shape_cache_size] || 0), tags: @tags

      gc_stat = GC.stat
      @dogstats.distribution "ruby.gc.eden_pages", gc_stat[:heap_eden_pages], tags: @tags
      @dogstats.distribution "ruby.gc.live_slots", gc_stat[:heap_live_slots], tags: @tags
      @dogstats.distribution "ruby.gc.free_slots", gc_stat[:heap_free_slots], tags: @tags
      @dogstats.distribution "ruby.gc.wb_unprotected_objects", gc_stat[:remembered_wb_unprotected_objects], tags: @tags
      @dogstats.distribution "ruby.gc.malloc_increase_bytes", gc_stat[:malloc_increase_bytes], tags: @tags
      @dogstats.distribution "ruby.gc.oldmalloc_increase_bytes", gc_stat[:oldmalloc_increase_bytes], tags: @tags
      @dogstats.distribution "ruby.gc.old_objects", gc_stat[:old_objects], tags: @tags
      @dogstats.distribution "ruby.memrss", GitHub::Memory.memrss, tags: @tags

      stat_heap = GC.stat_heap
      stat_heap.each_value do |info|
        tags = [*@tags, "slot_size:#{info[:slot_size]}"]
        @dogstats.distribution "ruby.gc.size_pool.eden_pages", info[:heap_eden_pages], tags: tags

        # On RUBY_NEXT, heap_tomb_pages and heap_allocatable_pages are no longer reported in heap_stats
        # Remove these metric once when upgrading to the next Ruby version
        @dogstats.distribution "ruby.gc.size_pool.tomb_pages", info[:heap_tomb_pages] || 0, tags: tags
        @dogstats.distribution "ruby.gc.size_pool.allocatable_pages", info[:heap_allocatable_pages] || 0, tags: tags
      end
    end
  end
end
