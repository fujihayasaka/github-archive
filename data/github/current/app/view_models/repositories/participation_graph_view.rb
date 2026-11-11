# typed: true
# frozen_string_literal: true

module Repositories
  class ParticipationGraphView
    attr_reader :width, :height, :bar_width, :repository

    Bar = Struct.new(:height, :y, :color)
    Week = Struct.new(:all, :owner)

    ALL_COLOR = "#f8f8f8".freeze
    OWNER_COLOR = "#dedede".freeze

    # Create a new view model for a repositories/_participation partial to use.
    #
    # data   - A Hash with keys:
    #          :all   - A 52 element Array of commit count Integers from all
    #                   contributors.
    #          :owner - A 52 element Array of commit count Integers from just
    #                   the repo owner.
    # width  - The Integer pixel width of the svg graph.
    # height - The Integer pixel height of the svg graph.
    # repository - The Repository that the data belongs to.
    def initialize(data:, width:, height:, repository:)
      @data = data
      @width = width
      @height = height
      @repository = repository
      @bar_width = ((width - 52) / 52.to_f).round(2)
      @scale = scale(data["all"])
    end

    # Provide the partial template with an array of weekly bar values to render
    # as svg. Both owner commits and all commits to the repository are graphed
    # as layered bars.
    #
    # Returns a 52 element Array of Bar objects.
    def weeks
      @weeks ||= begin
        counts = @data["all"].zip(@data["owner"])
        counts.map do |all, owner|
          Week.new(
            bar(all, ALL_COLOR),
            bar(owner, OWNER_COLOR))
        end
      end
    end

    private

    # Scale the y-axis of the graph to fit within the maximum pixel height.
    # Prevents commit counts greater than the pixel height from skewing the
    # graph.
    #
    # values - The 52 element Array of commit counts.
    #
    # Returns the Float scale to use on the y-axis values.
    def scale(values)
      max = values.max || 0
      if max > @height
        @height.to_f / max
      else
        1
      end
    end

    # Create a Bar to plot a week's commit count on the graph.
    #
    # count - The Integer commit count, or how tall the bar is.
    # color - The CSS color String to paint the bar.
    #
    # Returns a Bar.
    def bar(count, color)
      height = (count * @scale).round(2)
      y = @height - height
      Bar.new(height, y, color)
    end
  end
end
