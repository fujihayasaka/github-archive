# typed: true
# frozen_string_literal: true

module GitHub
  class TemplateTracingRenderer
    extend T::Sig

    sig { returns(T.nilable(String)) }
    attr_accessor :name

    sig { returns(T.nilable(Time)) }
    attr_accessor :start_time

    sig { params(end_time: Time).returns(Time) }
    attr_writer :end_time

    sig { returns(T.nilable(TemplateTracingRenderer)) }
    attr_accessor :parent

    sig { returns(T::Array[TemplateTracingRenderer]) }
    attr_reader :children

    sig { returns(T::Hash[Symbol, T::Hash[Symbol, Float]]) }
    attr_accessor :additional_stats

    sig { params(name: T.nilable(String)).void }
    def initialize(name)
      @name = name
      @children = T.let([], T::Array[T.untyped])
      @additional_stats = T.let({}, T::Hash[T.untyped, T.untyped])
    end

    sig { params(rendering: TemplateTracingRenderer).void }
    def add(rendering)
      @children << rendering
      rendering.parent = self
    end

    def end_time
      @end_time || Time.now
    end

    def time
      end_time - start_time
    end

    sig { returns(Float) }
    def exclusive_time
      time - child_time
    end

    sig { returns(Float) }
    def child_time
      children.inject(0.0) { |memo, c| memo + c.time }
    end

    sig { returns(String) }
    def time_summary
      if children.any?
        "%.2f <span class='text-small'>ms</span></span><span class='exclusive'>(%.2f <span class='text-small'>ms</span>)" % [time * 1_000, exclusive_time * 1_000]
      else
        "%.2f <span class='text-small'>ms</span>" % (time * 1_000)
      end
    end

    sig { returns(String) }
    def html
      <<-HTML
      <li>
        <div>
          <span class='name'>#{name}</span>
          <span class='timing'>#{time_summary}</span>
          #{additional_stats_summary}
        </div>
        #{children_html}
      </li>
      HTML
    end

    sig { returns(String) }
    def children_html
      return "" unless children.any?

      <<-HTML
        <ul>#{joined_children_html}</ul>
      HTML
    end

    sig { returns(String) }
    def joined_children_html
      children.map { |c| c.html }.join
    end

    sig { returns(String) }
    def additional_stats_summary
      %i(sql authzd).map { |s| summary_for_additional_stat(s) }.join("")
    end

    sig { params(stat: Symbol).returns(String) }
    def summary_for_additional_stat(stat)
      stat_count = additional_stat_count(stat)
      return "" unless stat_count > 0

      inclusive_summary = "<span class='timing'>#{stat_count} <span class='text-small'>#{stat}</span></span>"
      if children.any?
        exclusive_stat_count = stat_count - children.inject(0) { |m, c| m + c.additional_stat_count(stat) }
        if exclusive_stat_count > 0
          return inclusive_summary + "<span class='exclusive'>(#{exclusive_stat_count} <span class='text-small'>#{stat}</span>)</span>"
        end
      end

      inclusive_summary
    end

    sig { params(stat: Symbol).returns(Integer) }
    def additional_stat_count(stat)
      return 0 unless @additional_stats[stat]

      stat_count = @additional_stats[stat][:end] - @additional_stats[stat][:start]
      return 0 unless stat_count > 0

      stat_count
    end
  end
end
